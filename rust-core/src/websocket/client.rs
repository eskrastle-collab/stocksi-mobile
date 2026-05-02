// WebSocket-клиент совместимый с серверным протоколом Stocksi.
//
// Протокол:
//   1. Открываем WS к wss://websocket.priority.news с браузерными заголовками
//   2. Шлём серверу bitcode-encoded Connection { version: 9, token }
//   3. Клиент шлёт Ping каждые 2.5 сек (иначе сервер отключает через ~10 сек)
//   4. На ClientMessage::Ping от сервера отвечаем Pong
//   5. На ClientMessage::CheckConnection отвечаем ConnectionInfo
//   6. ClientMessage::CompressedMessage разжимаем через lz4_flex и декодируем рекурсивно

use anyhow::{Context, Result};
use bitcode::{decode, encode};
use futures::stream::{SplitSink, SplitStream};
use futures::{SinkExt, StreamExt};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Once};
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async};

use crate::types::server::{
    ACTUAL_CONNECTION_VERSION, ClientMessage, ClientMessageForServer, Connection, ConnectionInfo,
    ConnectionState, TokenError,
};

/// Если сервер молчит дольше этого времени — считаем соединение мёртвым
/// и переподключаемся. На мобильных сетях бывают задержки до 15-30 сек,
/// 45 сек — разумный порог между «явно мертво» и ложным срабатыванием.
const SERVER_SILENCE_TIMEOUT: Duration = Duration::from_secs(45);

pub const DEFAULT_WS_URL: &str = "wss://websocket.priority.news";

/// Rustls требует явно выбрать crypto-провайдер. Делаем это один раз за процесс.
static CRYPTO_INIT: Once = Once::new();
fn ensure_crypto_provider() {
    CRYPTO_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Публичная обёртка для api.rs — чтобы одноразовый validate_token мог подготовить rustls.
pub fn ensure_crypto_provider_public() {
    ensure_crypto_provider();
}

type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;
type WsSink = SplitSink<WsStream, Message>;
type WsRead = SplitStream<WsStream>;

#[derive(Debug, Clone)]
pub enum WsEvent {
    ConnectionChanged(ConnectionState),
    Message(ClientMessage),
    /// Сервер ответил что токен уже используется другим клиентом
    /// (TokenResultInvalid::TooManyConnections). Клиент должен показать
    /// пользователю сообщение и предложить «Обновить сессию».
    SessionTakenOver(String),
}

pub const SESSION_TAKEN_OVER_TEXT: &str =
    "Другая сессия ULTIMATE уже запущена.\n\nПродолжите работу на том устройстве, или закройте ULTIMATE на нём, затем обновите сессию здесь, чтобы продолжить, кнопка обновления сессии находится внизу.";

pub struct WsClient {
    url: String,
    token: String,
}

impl WsClient {
    pub fn new(url: String, token: String) -> Self {
        Self { url, token }
    }

    pub fn spawn(self) -> mpsc::Receiver<WsEvent> {
        ensure_crypto_provider();
        let (tx, rx) = mpsc::channel::<WsEvent>(128);
        tokio::spawn(async move {
            self.run_loop(tx).await;
        });
        rx
    }

    async fn run_loop(self, tx: mpsc::Sender<WsEvent>) {
        let mut backoff = Duration::from_secs(1);
        loop {
            if tx.is_closed() {
                log::info!("WS run_loop: receiver closed, exiting");
                return;
            }
            let _ = tx
                .send(WsEvent::ConnectionChanged(ConnectionState::Connecting))
                .await;
            let rejected = Arc::new(AtomicBool::new(false));
            match self.connect_once(&tx, Arc::clone(&rejected)).await {
                Ok(_) => backoff = Duration::from_secs(1),
                Err(err) => {
                    let full = format!("{err:?}");
                    log::warn!("WS disconnect: {full}");
                    if tx
                        .send(WsEvent::ConnectionChanged(
                            ConnectionState::Disconnected,
                        ))
                        .await
                        .is_err()
                    {
                        return;
                    }
                }
            }
            // Сервер отклонил нас с TooManyConnections — не спамим reconnect,
            // ждём долго, чтобы primary-сессия спокойно работала и не было
            // «пинг-понга» между двумя устройствами за один и тот же токен.
            if rejected.load(Ordering::Relaxed) {
                backoff = Duration::from_secs(60);
            }
            tokio::select! {
                _ = tokio::time::sleep(backoff) => {}
                _ = tx.closed() => return,
            }
            if !rejected.load(Ordering::Relaxed) {
                backoff = (backoff * 2).min(Duration::from_secs(30));
            }
        }
    }

    async fn connect_once(
        &self,
        tx: &mpsc::Sender<WsEvent>,
        rejected: Arc<AtomicBool>,
    ) -> Result<()> {
        // Браузерные заголовки (иначе nginx возвращает 502)
        let mut request = self
            .url
            .as_str()
            .into_client_request()
            .context("bad url")?;
        let headers = request.headers_mut();
        headers.insert("Origin", HeaderValue::from_static("https://www.tbank.ru"));
        headers.insert(
            "User-Agent",
            HeaderValue::from_static(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            ),
        );

        let (ws, _) = connect_async(request)
            .await
            .with_context(|| format!("WS connect failed: {}", self.url))?;
        let (mut write, mut read) = ws.split();

        // 1. Handshake: Connection { version, token }
        let connect_msg = Connection {
            version: ACTUAL_CONNECTION_VERSION,
            token: self.token.clone(),
        };
        write.send(Message::Binary(encode(&connect_msg).into())).await?;

        let _ = tx
            .send(WsEvent::ConnectionChanged(ConnectionState::Connected))
            .await;

        // 2. Основной цикл: периодический Ping + чтение входящих + watchdog
        let mut ping_interval = tokio::time::interval(Duration::from_millis(2500));
        ping_interval.tick().await;
        let mut last_recv = tokio::time::Instant::now();

        let result: Result<()> = async {
            loop {
                tokio::select! {
                    _ = ping_interval.tick() => {
                        let ping = encode(&ClientMessageForServer::Ping);
                        write.send(Message::Binary(ping.into())).await
                            .context("failed to send ping")?;
                        // Watchdog: если сервер молчит дольше порога — TCP
                        // мог зависнуть без FIN. Принудительно разрываем и
                        // переподключаемся.
                        if last_recv.elapsed() > SERVER_SILENCE_TIMEOUT {
                            log::warn!(
                                "WS server silent for {:?} — forcing reconnect",
                                last_recv.elapsed()
                            );
                            anyhow::bail!("server silent timeout");
                        }
                    }
                    msg = read.next() => {
                        let Some(msg) = msg else { break };
                        let msg = msg.context("read error")?;
                        last_recv = tokio::time::Instant::now();
                        if !handle_incoming(msg, &mut write, tx, &rejected).await? {
                            break;
                        }
                    }
                    _ = tx.closed() => {
                        let _ = write.close().await;
                        break;
                    }
                }
            }
            Ok(())
        }
        .await;

        let _ = tx
            .send(WsEvent::ConnectionChanged(ConnectionState::Disconnected))
            .await;
        result
    }
}

/// Возвращает false если нужно прервать цикл (close-frame).
async fn handle_incoming(
    msg: Message,
    write: &mut WsSink,
    tx: &mpsc::Sender<WsEvent>,
    rejected: &AtomicBool,
) -> Result<bool> {
    match msg {
        Message::Binary(bytes) => {
            let Some(client_msg) = decode_message(&bytes) else {
                log::warn!("Failed to decode binary message, {} bytes", bytes.len());
                return Ok(true);
            };
            if matches!(client_msg, ClientMessage::Ping) {
                let pong = encode(&ClientMessageForServer::Pong);
                write.send(Message::Binary(pong.into())).await?;
            }
            if matches!(client_msg, ClientMessage::CheckConnection) {
                let info = ClientMessageForServer::ConnectionInfo(ConnectionInfo {
                    screen: None,
                    hardware_concurrency: 0,
                    device_memory: 0,
                    url: "stocksi-mobile://app".to_string(),
                    language: "ru".to_string(),
                    timezone_offset: 0.0,
                    network_information: "unknown".to_string(),
                });
                write.send(Message::Binary(encode(&info).into())).await?;
            }
            // Токен уже используется другим клиентом — эмитим отдельный event
            // чтобы UI мог показать баннер «Сессия перехвачена».
            if let ClientMessage::TokenResultInvalid(TokenError::TooManyConnections) =
                &client_msg
            {
                rejected.store(true, Ordering::Relaxed);
                let _ = tx
                    .send(WsEvent::SessionTakenOver(
                        SESSION_TAKEN_OVER_TEXT.to_string(),
                    ))
                    .await;
            }
            let _ = tx.send(WsEvent::Message(client_msg)).await;
            Ok(true)
        }
        Message::Close(frame) => {
            log::info!("Server closed WS: {frame:?}");
            Ok(false)
        }
        _ => Ok(true),
    }
}

/// Декодирует входящее сообщение, рекурсивно разжимая CompressedMessage.
fn decode_message(bytes: &[u8]) -> Option<ClientMessage> {
    let msg: ClientMessage = decode(bytes).ok()?;
    if let ClientMessage::CompressedMessage(compressed) = msg {
        let decompressed = lz4_flex::block::decompress_size_prepended(&compressed).ok()?;
        return decode::<ClientMessage>(&decompressed).ok();
    }
    Some(msg)
}

// Подавляем unused для импорта WsRead (может понадобиться в будущем)
#[allow(dead_code)]
fn _unused(_: WsRead) {}
