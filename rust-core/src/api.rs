// Публичный API, который flutter_rust_bridge экспортирует в Dart.
// Правила flutter_rust_bridge 2.x:
//   — всё что должно быть доступно из Dart — в этом модуле
//   — флаг #[frb(...)] управляет деталями генерации
//   — Stream<T> на Rust-стороне = Stream<T> на Dart-стороне
//   — async fn автоматически превращается в Future<T> в Dart

use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::Arc;
use tokio::sync::OnceCell;

use crate::storage::{StorageBackend, sqlite::SqliteStorage};
use crate::types::news::StoringNews;
use crate::types::server::{ClientMessage, ConnectionState};
use crate::websocket::{WsClient, WsEvent};

// ============================================================================
// Глобальное состояние приложения (init'ится один раз из Flutter на старте)
// ============================================================================

static STORAGE: OnceCell<Arc<dyn StorageBackend>> = OnceCell::const_new();

/// Инициализация ядра: путь к БД приходит из Flutter (platform-specific directory).
/// Вызывается один раз при старте приложения.
pub async fn init_core(db_path: String) -> Result<()> {
    env_logger::try_init().ok();
    let storage: Arc<dyn StorageBackend> = Arc::new(SqliteStorage::open(&db_path)?);
    STORAGE
        .set(storage)
        .map_err(|_| anyhow::anyhow!("Core already initialized"))?;
    Ok(())
}

// ============================================================================
// POC: моковая лента
// ============================================================================

/// Возвращает несколько моковых новостей — для проверки FFI-моста без реального WS.
#[frb(sync)]
pub fn mock_news_list() -> Vec<StoringNews> {
    vec![
        StoringNews {
            id: 1,
            timestamp: Some(1_744_800_000_000 / 10),
            title: "Газпром рассматривает возможность выплаты дивидендов по итогам года".into(),
            short: Some("Совет директоров рекомендует выплатить 25 рублей на акцию.".into()),
            source: Some("Интерфакс".into()),
            tickers: vec!["$GAZP".into()],
            tags: vec!["дивиденды".into()],
            files: vec![],
            full_text_link: None,
        },
        StoringNews {
            id: 2,
            timestamp: Some(1_744_803_600_000 / 10),
            title: "ЦБ РФ СОХРАНИЛ КЛЮЧЕВУЮ СТАВКУ НА УРОВНЕ 21%".into(),
            short: None,
            source: Some("ЦБ".into()),
            tickers: vec![],
            tags: vec![],
            files: vec![],
            full_text_link: None,
        },
        StoringNews {
            id: 3,
            timestamp: Some(1_744_807_200_000 / 10),
            title: "Сбер объявил buyback на 50 млрд рублей".into(),
            short: Some("Обратный выкуп акций стартует 1 мая.".into()),
            source: Some("Ведомости".into()),
            tickers: vec!["$SBER".into()],
            tags: vec!["buyback".into()],
            files: vec![],
            full_text_link: None,
        },
    ]
}

// ============================================================================
// Реальное API (подключаем по фазам)
// ============================================================================

/// Сохранить токен.
pub async fn set_token(token: String) -> Result<()> {
    let storage = STORAGE
        .get()
        .ok_or_else(|| anyhow::anyhow!("Core not initialized"))?;
    storage.set_string("token", &token)?;
    Ok(())
}

pub async fn get_token() -> Result<Option<String>> {
    let storage = STORAGE
        .get()
        .ok_or_else(|| anyhow::anyhow!("Core not initialized"))?;
    storage.get_string("token")
}

pub async fn read_all_news() -> Result<Vec<StoringNews>> {
    let storage = STORAGE
        .get()
        .ok_or_else(|| anyhow::anyhow!("Core not initialized"))?;
    storage.read_all_news()
}

/// Валидирует токен через сервер: открывает WS, ждёт TokenResultOk или TokenResultInvalid.
/// Таймаут 15 секунд. Возвращает Ok(()) если токен валиден, Err(сообщение) — иначе.
pub async fn validate_token(token: String) -> Result<(), String> {
    use crate::types::server::{
        ACTUAL_CONNECTION_VERSION, ClientMessage, Connection, TokenError,
    };
    use bitcode::{decode, encode};
    use futures::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::connect_async;
    use tokio_tungstenite::tungstenite::Message;
    use tokio_tungstenite::tungstenite::client::IntoClientRequest;
    use tokio_tungstenite::tungstenite::http::HeaderValue;

    // Гарантируем что crypto-провайдер rustls установлен
    crate::websocket::client::ensure_crypto_provider_public();

    // Собираем запрос с нужными заголовками
    let mut request = crate::websocket::client::DEFAULT_WS_URL
        .into_client_request()
        .map_err(|e| format!("Ошибка URL: {e}"))?;
    let headers = request.headers_mut();
    headers.insert("Origin", HeaderValue::from_static("https://www.tbank.ru"));
    headers.insert(
        "User-Agent",
        HeaderValue::from_static(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
             (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        ),
    );

    // Подключаемся (с таймаутом)
    let (ws, _) = tokio::time::timeout(Duration::from_secs(10), connect_async(request))
        .await
        .map_err(|_| "Нет ответа от сервера".to_string())?
        .map_err(|e| format!("Не удалось подключиться: {e}"))?;

    let (mut write, mut read) = ws.split();

    // Отправляем handshake
    let connect = Connection {
        version: ACTUAL_CONNECTION_VERSION,
        token: token.clone(),
    };
    write
        .send(Message::Binary(encode(&connect).into()))
        .await
        .map_err(|e| format!("Ошибка отправки: {e}"))?;

    // Ждём TokenResultOk или TokenResultInvalid (до 15 сек)
    let result = tokio::time::timeout(Duration::from_secs(15), async {
        while let Some(msg) = read.next().await {
            let msg = msg.map_err(|e| format!("Ошибка чтения: {e}"))?;
            let Message::Binary(bytes) = msg else { continue };
            let Ok(mut client_msg) = decode::<ClientMessage>(&bytes) else { continue };
            // Разворачиваем CompressedMessage если нужно
            if let ClientMessage::CompressedMessage(compressed) = &client_msg {
                let Ok(decompressed) = lz4_flex::block::decompress_size_prepended(compressed)
                else { continue };
                let Ok(inner) = decode::<ClientMessage>(&decompressed) else { continue };
                client_msg = inner;
            }
            match client_msg {
                ClientMessage::TokenResultOk(_) => return Ok(()),
                ClientMessage::TokenResultInvalid(err) => {
                    let text = match err {
                        TokenError::Wrong => "Неверный токен",
                        TokenError::ServerError => "Ошибка сервера при проверке",
                        TokenError::TooManyConnections => "Слишком много подключений",
                    };
                    return Err(text.to_string());
                }
                _ => continue, // игнорируем другие сообщения
            }
        }
        Err("Соединение закрыто сервером".to_string())
    })
    .await
    .map_err(|_| "Таймаут проверки токена".to_string())?;

    let _ = write.close().await;
    result
}

// ════════════════════════════════════════════════════════════════════════════
// Settings persistence (source/filter settings)
// ════════════════════════════════════════════════════════════════════════════

const WIDGET_ID: &str = "default";

fn storage_ref() -> Result<Arc<dyn StorageBackend>> {
    STORAGE
        .get()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("Core not initialized"))
}

/// Сохранение per-source overrides (map: source_name → enabled).
pub async fn set_source_enabled(source_name: String, enabled: bool) -> Result<()> {
    let s = storage_ref()?;
    let mut settings = s.read_settings(WIDGET_ID)?;
    settings.source_settings.retain(|x| x.source != source_name);
    settings.source_settings.push(crate::types::settings::SourceSetting {
        source: source_name,
        enabled,
    });
    s.write_settings(WIDGET_ID, &settings)?;
    Ok(())
}

/// Возвращает текущие overrides источников (для инициализации UI).
pub async fn get_source_settings() -> Result<Vec<(String, bool)>> {
    let s = storage_ref()?;
    let settings = s.read_settings(WIDGET_ID)?;
    Ok(settings
        .source_settings
        .into_iter()
        .map(|x| (x.source, x.enabled))
        .collect())
}

/// Сохраняет чёрный/белый список тикеров/хэштегов/фраз.
/// `filter_type` = "tickers_black" | "tickers_white" | "hashtags_black" | "hashtags_white" |
///                 "phrases_black" | "phrases_white"
pub async fn set_filter(
    filter_type: String,
    enabled: bool,
    values: Vec<String>,
) -> Result<()> {
    let s = storage_ref()?;
    let mut settings = s.read_settings(WIDGET_ID)?;
    match filter_type.as_str() {
        "tickers_black" => {
            settings.tickers_black_filter_enabled = enabled;
            settings.tickers_black_filter = values;
        }
        "tickers_white" => {
            settings.tickers_white_filter_enabled = enabled;
            settings.tickers_white_filter = values;
        }
        "hashtags_black" => {
            settings.hashtags_black_filter_enabled = enabled;
            settings.hashtags_black_filter = values;
        }
        "hashtags_white" => {
            settings.hashtags_white_filter_enabled = enabled;
            settings.hashtags_white_filter = values;
        }
        "phrases_black" => {
            settings.phrases_black_filter_enabled = enabled;
            settings.phrases_black_filter = values;
        }
        "phrases_white" => {
            settings.phrases_white_filter_enabled = enabled;
            settings.phrases_white_filter = values;
        }
        _ => return Err(anyhow::anyhow!("unknown filter type: {filter_type}")),
    }
    s.write_settings(WIDGET_ID, &settings)?;
    Ok(())
}

/// Читает один фильтр: (enabled, values).
pub async fn get_filter(filter_type: String) -> Result<(bool, Vec<String>)> {
    let s = storage_ref()?;
    let settings = s.read_settings(WIDGET_ID)?;
    Ok(match filter_type.as_str() {
        "tickers_black" => (
            settings.tickers_black_filter_enabled,
            settings.tickers_black_filter,
        ),
        "tickers_white" => (
            settings.tickers_white_filter_enabled,
            settings.tickers_white_filter,
        ),
        "hashtags_black" => (
            settings.hashtags_black_filter_enabled,
            settings.hashtags_black_filter,
        ),
        "hashtags_white" => (
            settings.hashtags_white_filter_enabled,
            settings.hashtags_white_filter,
        ),
        "phrases_black" => (
            settings.phrases_black_filter_enabled,
            settings.phrases_black_filter,
        ),
        "phrases_white" => (
            settings.phrases_white_filter_enabled,
            settings.phrases_white_filter,
        ),
        _ => return Err(anyhow::anyhow!("unknown filter type: {filter_type}")),
    })
}

/// Проверяет, должна ли новость быть отфильтрована при текущих настройках.
/// Делегирует в `filters::is_filtered`.
pub async fn news_is_filtered(news: StoringNews) -> Result<bool> {
    let s = storage_ref()?;
    let settings = s.read_settings(WIDGET_ID)?;
    Ok(crate::filters::is_filtered(&settings, &news))
}

/// Сохраняет актуальный source_list от сервера в NewsSettings.
/// Вызывается автоматически при получении TokenResultOk.
pub async fn update_source_list(
    groups: Vec<crate::types::server::GroupedSourceList>,
) -> Result<()> {
    let s = storage_ref()?;
    let mut settings = s.read_settings(WIDGET_ID)?;
    settings.source_list = groups;
    s.write_settings(WIDGET_ID, &settings)?;
    Ok(())
}

// ══════════════════════════════════════════════════════════════════════════
// Hashtag alerts (L)
// ══════════════════════════════════════════════════════════════════════════

/// Сохраняет список алертов (hashtags → sound). Перезаписывает все существующие.
pub async fn set_hashtag_alerts(
    alerts: Vec<(Vec<String>, String)>,
) -> Result<()> {
    let s = storage_ref()?;
    let mut settings = s.read_settings(WIDGET_ID)?;
    settings.hashtag_alerts = alerts
        .into_iter()
        .map(|(hashtags, sound)| crate::types::settings::HashtagAlert {
            hashtags,
            chosen_alert: sound,
        })
        .collect();
    s.write_settings(WIDGET_ID, &settings)?;
    Ok(())
}

/// Загружает список алертов.
pub async fn get_hashtag_alerts() -> Result<Vec<(Vec<String>, String)>> {
    let s = storage_ref()?;
    let settings = s.read_settings(WIDGET_ID)?;
    Ok(settings
        .hashtag_alerts
        .into_iter()
        .map(|a| (a.hashtags, a.chosen_alert))
        .collect())
}

/// Сохранить DSL правил подсветки текста (парсится в Dart).
pub async fn set_text_highlight_dsl(dsl: String) -> Result<()> {
    let s = storage_ref()?;
    s.set_string("text_highlight_dsl", &dsl)?;
    Ok(())
}

/// Загрузить DSL правил подсветки.
pub async fn get_text_highlight_dsl() -> Result<String> {
    let s = storage_ref()?;
    Ok(s.get_string("text_highlight_dsl")?.unwrap_or_default())
}

/// Включена ли подсветка слов и фраз.
/// Дефолт — true (если ключа нет, считаем включённой).
pub async fn get_text_highlight_enabled() -> Result<bool> {
    let s = storage_ref()?;
    Ok(s.get_string("text_highlight_enabled")?
        .map(|v| v != "0")
        .unwrap_or(true))
}

/// Переключатель подсветки слов и фраз.
pub async fn set_text_highlight_enabled(enabled: bool) -> Result<()> {
    let s = storage_ref()?;
    s.set_string("text_highlight_enabled", if enabled { "1" } else { "0" })?;
    Ok(())
}

/// Выбранная тема оформления: "dark" / "light" / "system".
/// Дефолт — "dark" (как было раньше).
pub async fn get_theme_mode() -> Result<String> {
    let s = storage_ref()?;
    Ok(s.get_string("theme_mode")?
        .unwrap_or_else(|| "dark".to_string()))
}

/// Сохранить выбор темы.
pub async fn set_theme_mode(mode: String) -> Result<()> {
    let s = storage_ref()?;
    s.set_string("theme_mode", &mode)?;
    Ok(())
}

/// Включены ли системные push-уведомления о новостях.
/// Дефолт — false (пользователь явно включает).
pub async fn get_push_enabled() -> Result<bool> {
    let s = storage_ref()?;
    Ok(s.get_string("push_enabled")?
        .map(|v| v == "1")
        .unwrap_or(false))
}

/// Переключатель push-уведомлений.
pub async fn set_push_enabled(enabled: bool) -> Result<()> {
    let s = storage_ref()?;
    s.set_string("push_enabled", if enabled { "1" } else { "0" })?;
    Ok(())
}

/// Проверяет, какой алерт сработал для новости (возвращает название звука).
/// Возвращает None если нет подходящего алерта.
pub async fn matching_alert_sound(news_tags: Vec<String>) -> Result<Option<String>> {
    let s = storage_ref()?;
    let settings = s.read_settings(WIDGET_ID)?;
    for alert in &settings.hashtag_alerts {
        // Правило срабатывает если все хэштеги из правила присутствуют в новости
        if alert
            .hashtags
            .iter()
            .all(|h| news_tags.contains(h))
        {
            return Ok(Some(alert.chosen_alert.clone()));
        }
    }
    Ok(None)
}

/// Возвращает URL логотипа компании по тикеру, либо None если неизвестно.
/// Формат: https://invest-brands.cdn-tinkoff.ru/{ISIN}x160.png
pub fn get_ticker_icon_url(ticker: &str) -> Option<String> {
    let ticker = ticker.trim_start_matches('$');
    let ticker = ticker.split_whitespace().next().unwrap_or("");
    if ticker.is_empty() {
        return None;
    }
    let icon = crate::icons::default_get_icon(ticker);
    if icon.is_empty() {
        None
    } else {
        Some(format!(
            "https://invest-brands.cdn-tinkoff.ru/{icon}x160.png"
        ))
    }
}

/// Проверка формата токена (UUID v4: 36 символов, 4 дефиса, hex-цифры).
/// Возвращает None если валидный, Some(ошибка) иначе.
pub fn check_token_format(token: &str) -> Option<String> {
    if token.is_empty() {
        return Some("Токен не введён".to_string());
    }
    if token.len() != 36 {
        return Some("Токен должен быть длиной 36 символов".to_string());
    }
    let bytes = token.as_bytes();
    for (i, b) in bytes.iter().enumerate() {
        if [8, 13, 18, 23].contains(&i) {
            if *b != b'-' {
                return Some("Неверный формат: ожидался дефис".to_string());
            }
        } else if !b.is_ascii_hexdigit() {
            return Some("Неверный формат: недопустимый символ".to_string());
        }
    }
    None
}

/// Подписка на события WS. Flutter получает стрим событий для обновления UI.
pub async fn start_websocket(token: String) -> impl futures::Stream<Item = WsEventDto> {
    let client = WsClient::new(
        crate::websocket::client::DEFAULT_WS_URL.to_string(),
        token,
    );
    let mut rx = client.spawn();
    async_stream::stream! {
        while let Some(ev) = rx.recv().await {
            yield WsEventDto::from(ev);
        }
    }
}

/// DTO-обёртка для Stream (flutter_rust_bridge не умеет сложные enum'ы в стримах напрямую).
#[derive(Debug, Clone)]
pub enum WsEventDto {
    ConnectionConnecting,
    ConnectionConnected,
    ConnectionDisconnected,
    ConnectionError(String),
    NewsAdded(StoringNews),
    NewsDeleted(Vec<u32>),
    /// Полный reload списка новостей.
    NewsReset(Vec<StoringNews>),
}

impl From<WsEvent> for WsEventDto {
    fn from(ev: WsEvent) -> Self {
        match ev {
            WsEvent::ConnectionChanged(c) => match c {
                ConnectionState::Connecting => WsEventDto::ConnectionConnecting,
                ConnectionState::Connected => WsEventDto::ConnectionConnected,
                ConnectionState::Disconnected => WsEventDto::ConnectionDisconnected,
                ConnectionState::Error(e) => WsEventDto::ConnectionError(e),
                ConnectionState::TokenInvalid(e) => WsEventDto::ConnectionError(e),
            },
            WsEvent::Message(msg) => match msg {
                ClientMessage::News(n) => WsEventDto::NewsAdded(StoringNews::from(n)),
                ClientMessage::DeleteNews(ids) => WsEventDto::NewsDeleted(ids),
                ClientMessage::NewsHistory(list) => {
                    WsEventDto::NewsReset(list.into_iter().map(StoringNews::from).collect())
                }
                _ => WsEventDto::ConnectionDisconnected,
            },
            WsEvent::SessionTakenOver(msg) => WsEventDto::ConnectionError(msg),
        }
    }
}
