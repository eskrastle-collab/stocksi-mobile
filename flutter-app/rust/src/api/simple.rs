// Публичный API для Flutter. Делегирует в stocksi_core.
//
// StoringNews определён здесь (а не импортирован из stocksi_core) — чтобы
// flutter_rust_bridge сгенерировал настоящий Dart-класс с полями,
// а не непрозрачный RustOpaqueInterface.

use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::OnceLock;

/// Собственный tokio runtime для фоновых задач (WebSocket, reconnect loop).
/// frb по умолчанию не использует tokio, поэтому `tokio::spawn` требует
/// явной runtime-handle.
static TOKIO_RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn tokio_runtime() -> &'static tokio::runtime::Runtime {
    TOKIO_RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("stocksi-tokio")
            .build()
            .expect("failed to init tokio runtime")
    })
}

/// Новость — mirror of stocksi_core::types::news::StoringNews для Dart.
#[derive(Debug, Clone)]
pub struct StoringNews {
    pub id: u32,
    pub timestamp: Option<i64>,
    pub title: String,
    pub short: Option<String>,
    pub source: Option<String>,
    pub tickers: Vec<String>,
    pub tags: Vec<String>,
    pub files: Vec<String>,
    pub full_text_link: Option<String>,
}

impl From<stocksi_core::types::news::StoringNews> for StoringNews {
    fn from(n: stocksi_core::types::news::StoringNews) -> Self {
        Self {
            id: n.id,
            timestamp: n.timestamp,
            title: n.title,
            short: n.short,
            source: n.source,
            tickers: n.tickers,
            tags: n.tags,
            files: n.files,
            full_text_link: n.full_text_link,
        }
    }
}

/// Инициализация утилит flutter_rust_bridge (логирование, panic handler).
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// POC: моковые новости для проверки FFI.
#[frb(sync)]
pub fn mock_news_list() -> Vec<StoringNews> {
    stocksi_core::api::mock_news_list()
        .into_iter()
        .map(StoringNews::from)
        .collect()
}

/// Инициализация ядра с SQLite.
pub async fn init_core(db_path: String) -> Result<()> {
    stocksi_core::api::init_core(db_path).await
}

pub async fn set_token(token: String) -> Result<()> {
    stocksi_core::api::set_token(token).await
}

pub async fn get_token() -> Result<Option<String>> {
    stocksi_core::api::get_token().await
}

/// Валидация формата токена (UUID v4). Возвращает текст ошибки или null если ОК.
#[frb(sync)]
pub fn check_token_format(token: String) -> Option<String> {
    stocksi_core::api::check_token_format(&token)
}

/// Получить URL логотипа компании по тикеру. Null если тикер неизвестен.
#[frb(sync)]
pub fn ticker_icon_url(ticker: String) -> Option<String> {
    stocksi_core::api::get_ticker_icon_url(&ticker)
}

/// Реальная проверка токена через сервер WebSocket (TokenResultOk / TokenResultInvalid).
/// Возвращает null если токен принят, либо текст ошибки.
pub async fn validate_token(token: String) -> Option<String> {
    match stocksi_core::api::validate_token(token).await {
        Ok(()) => None,
        Err(e) => Some(e),
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Live news stream
// ────────────────────────────────────────────────────────────────────────────

/// Один источник новостей для UI.
#[derive(Debug, Clone)]
pub struct SourceItem {
    pub source_name: String,
    pub default_enabled: bool,
}

/// Группа источников (None = «Базовые»).
#[derive(Debug, Clone)]
pub struct SourceGroup {
    pub group_name: Option<String>,
    pub sources: Vec<SourceItem>,
}

/// События от WebSocket-ленты для UI. Локальный тип, который видит frb.
#[derive(Debug, Clone)]
pub enum NewsStreamEvent {
    Connecting,
    Connected,
    Disconnected,
    Error(String),
    /// Полный reload списка (NewsHistory от сервера).
    NewsReset(Vec<StoringNews>),
    /// Одна новая новость.
    NewsAdded(StoringNews),
    /// Обновление существующей новости (сервер прислал NewsChange).
    NewsUpdated(StoringNews),
    /// Удаление по id.
    NewsDeleted(Vec<u32>),
    /// Пришёл обновлённый каталог источников (TokenResultOk).
    SourceListUpdated(Vec<SourceGroup>),
    /// Токен используется другим клиентом — UI показывает баннер.
    SessionTakenOver(String),
}

/// Открывает WS-соединение и шлёт события через sink. Flutter получает это
/// как Stream<NewsStreamEvent>. Sink закрывается при отписке в Dart.
pub fn start_news_stream(
    token: String,
    sink: crate::frb_generated::StreamSink<NewsStreamEvent>,
) {
    use stocksi_core::types::news::StoringNews as CoreNews;
    use stocksi_core::types::server::ClientMessage;
    use stocksi_core::websocket::{WsClient, WsEvent};
    tokio_runtime().spawn(async move {
        let client = WsClient::new(
            stocksi_core::websocket::client::DEFAULT_WS_URL.to_string(),
            token,
        );
        let mut rx = client.spawn();
        while let Some(ev) = rx.recv().await {
            let dto = match ev {
                WsEvent::ConnectionChanged(c) => match c {
                    stocksi_core::types::server::ConnectionState::Connecting => {
                        NewsStreamEvent::Connecting
                    }
                    stocksi_core::types::server::ConnectionState::Connected => {
                        NewsStreamEvent::Connected
                    }
                    stocksi_core::types::server::ConnectionState::Disconnected => {
                        NewsStreamEvent::Disconnected
                    }
                    stocksi_core::types::server::ConnectionState::Error(e)
                    | stocksi_core::types::server::ConnectionState::TokenInvalid(e) => {
                        NewsStreamEvent::Error(e)
                    }
                },
                WsEvent::Message(msg) => match msg {
                    ClientMessage::NewsHistory(list) => NewsStreamEvent::NewsReset(
                        list.into_iter()
                            .map(|n| CoreNews::from(n))
                            .map(StoringNews::from)
                            .collect(),
                    ),
                    ClientMessage::News(n) => {
                        NewsStreamEvent::NewsAdded(StoringNews::from(CoreNews::from(n)))
                    }
                    ClientMessage::UpdateNews(change) => {
                        // В UpdateNews.full_news сервер присылает актуальное состояние
                        // новости целиком (после всех изменений).
                        NewsStreamEvent::NewsUpdated(StoringNews::from(
                            CoreNews::from(change.full_news),
                        ))
                    }
                    ClientMessage::DeleteNews(ids) => NewsStreamEvent::NewsDeleted(ids),
                    ClientMessage::TokenResultOk((_subs, source_list)) => {
                        // Автосохранение source_list в NewsSettings — чтобы фильтры работали
                        let _ = stocksi_core::api::update_source_list(source_list.clone()).await;
                        NewsStreamEvent::SourceListUpdated(
                            source_list
                                .into_iter()
                                .map(|g| SourceGroup {
                                    group_name: g.group_name,
                                    sources: g
                                        .source_list
                                        .into_iter()
                                        .map(|s| SourceItem {
                                            source_name: s.source_name,
                                            default_enabled: s.default_enabled,
                                        })
                                        .collect(),
                                })
                                .collect(),
                        )
                    }
                    _ => continue, // Ping, Pong и прочие — пропускаем
                },
                WsEvent::SessionTakenOver(text) => NewsStreamEvent::SessionTakenOver(text),
            };
            if sink.add(dto).is_err() {
                break; // Dart отписался
            }
        }
    });
}

pub async fn read_all_news() -> Result<Vec<StoringNews>> {
    Ok(stocksi_core::api::read_all_news()
        .await?
        .into_iter()
        .map(StoringNews::from)
        .collect())
}

// ════════════════════════════════════════════════════════════════════════════
// Settings API (для SettingsScreen)
// ════════════════════════════════════════════════════════════════════════════

/// Вкл/выкл источник по имени. Сохраняется в SQLite.
pub async fn set_source_enabled(source_name: String, enabled: bool) -> Result<()> {
    stocksi_core::api::set_source_enabled(source_name, enabled).await
}

/// Возвращает user-overrides: список (source_name, enabled).
/// Источник считается "по умолчанию" если его нет в этом списке.
pub async fn get_source_settings() -> Result<Vec<(String, bool)>> {
    stocksi_core::api::get_source_settings().await
}

/// Фильтр черный/белый по тикерам/хэштегам/фразам.
/// filter_type ∈ { tickers_black, tickers_white, hashtags_black, hashtags_white,
///                  phrases_black, phrases_white }
pub async fn set_filter(
    filter_type: String,
    enabled: bool,
    values: Vec<String>,
) -> Result<()> {
    stocksi_core::api::set_filter(filter_type, enabled, values).await
}

/// Возвращает фильтр: (enabled, values).
pub async fn get_filter(filter_type: String) -> Result<(bool, Vec<String>)> {
    stocksi_core::api::get_filter(filter_type).await
}

/// Применить текущие фильтры: true если новость отфильтрована.
pub async fn news_is_filtered(news: StoringNews) -> Result<bool> {
    stocksi_core::api::news_is_filtered(stocksi_core::types::news::StoringNews {
        id: news.id,
        timestamp: news.timestamp,
        title: news.title,
        short: news.short,
        source: news.source,
        tickers: news.tickers,
        tags: news.tags,
        files: news.files,
        full_text_link: news.full_text_link,
    })
    .await
}

// ══════════════════════════════════════════════════════════════════════════
// Hashtag alerts
// ══════════════════════════════════════════════════════════════════════════

/// Сохранить DSL подсветки.
pub async fn set_text_highlight_dsl(dsl: String) -> Result<()> {
    stocksi_core::api::set_text_highlight_dsl(dsl).await
}

/// Загрузить DSL подсветки.
pub async fn get_text_highlight_dsl() -> Result<String> {
    stocksi_core::api::get_text_highlight_dsl().await
}

/// Включена ли подсветка слов и фраз.
pub async fn get_text_highlight_enabled() -> Result<bool> {
    stocksi_core::api::get_text_highlight_enabled().await
}

/// Переключатель подсветки слов и фраз.
pub async fn set_text_highlight_enabled(enabled: bool) -> Result<()> {
    stocksi_core::api::set_text_highlight_enabled(enabled).await
}

/// Выбранная тема: "dark" / "light" / "system".
pub async fn get_theme_mode() -> Result<String> {
    stocksi_core::api::get_theme_mode().await
}

/// Сохранить выбор темы.
pub async fn set_theme_mode(mode: String) -> Result<()> {
    stocksi_core::api::set_theme_mode(mode).await
}

/// Включены ли системные push-уведомления о новостях.
pub async fn get_push_enabled() -> Result<bool> {
    stocksi_core::api::get_push_enabled().await
}

/// Переключатель push-уведомлений.
pub async fn set_push_enabled(enabled: bool) -> Result<()> {
    stocksi_core::api::set_push_enabled(enabled).await
}

/// Сохранить список алертов: пары (хэштеги, имя звука).
pub async fn set_hashtag_alerts(alerts: Vec<(Vec<String>, String)>) -> Result<()> {
    stocksi_core::api::set_hashtag_alerts(alerts).await
}

/// Загрузить список алертов.
pub async fn get_hashtag_alerts() -> Result<Vec<(Vec<String>, String)>> {
    stocksi_core::api::get_hashtag_alerts().await
}

/// Вернуть имя звука для алерта, соответствующего хэштегам новости,
/// либо None если ни один алерт не подходит.
pub async fn matching_alert_sound(news_tags: Vec<String>) -> Result<Option<String>> {
    stocksi_core::api::matching_alert_sound(news_tags).await
}
