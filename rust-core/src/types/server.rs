// Типы, совпадающие 1-в-1 с серверным протоколом (расширение).
// Используется bitcode::Encode/Decode — НАТИВНЫЙ bitcode-формат, не serde!
// Важен порядок вариантов enum'ов — он влияет на байты.

use bitcode::{Decode, Encode};
use serde::{Deserialize, Serialize};

/// Версия протокола. Обязана совпадать с серверной.
pub const ACTUAL_CONNECTION_VERSION: u16 = 9;

/// Первое сообщение клиента серверу: { version, token }.
#[derive(Clone, Debug, Encode)]
pub struct Connection {
    pub version: u16,
    pub token: String,
}

#[derive(Clone, Debug, Decode)]
pub enum TokenError {
    Wrong,
    ServerError,
    TooManyConnections,
}

#[derive(Clone, Debug, Decode)]
pub struct ClientSubscriptionInfo {
    pub subscription_group_name: String,
    pub persistent: bool,
    pub until_timestamp: u64,
}

#[derive(Clone, PartialEq, Eq, Debug, Encode, Decode, Serialize, Deserialize)]
pub struct Source {
    pub source_name: String,
    pub default_enabled: bool,
}

#[derive(Clone, PartialEq, Eq, Debug, Encode, Decode, Serialize, Deserialize)]
pub struct GroupedSourceList {
    pub group_name: Option<String>,
    pub source_list: Vec<Source>,
}

#[derive(Clone, Debug, Decode, Default)]
pub struct News {
    pub id: u32,
    pub title: String,
    pub short: Option<String>,
    pub full_text_link: Option<String>,
    pub source: Option<String>,
    pub tickers: Vec<String>,
    pub tags: Vec<String>,
    pub files: Vec<String>,
    pub timestamp: i64,
}

#[derive(Clone, Debug, Decode, Default)]
pub struct NewsChange {
    pub id: u32,
    pub title: Option<String>,
    pub short: Option<Option<String>>,
    pub full_text_link: Option<Option<String>>,
    pub source: Option<Option<String>>,
    pub tickers: Option<Vec<String>>,
    pub tags: Option<Vec<String>>,
    pub files: Option<Vec<String>>,
    pub timestamp: Option<i64>,
    pub full_news: News,
}

#[derive(Clone, Debug, Decode)]
pub struct FilePreload {
    pub url: String,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, Decode)]
pub struct SwitchTicker {
    pub ticker: String,
    pub user_id: u64,
    pub group_id: u8,
}

/// Сообщение от сервера. ПОРЯДОК вариантов важен для bitcode!
#[derive(Clone, Debug, Decode)]
pub enum ClientMessage {
    Pong,
    News(News),
    FilePreload(FilePreload),
    Ticker(SwitchTicker),
    DeleteNews(Vec<u32>),
    UpdateNews(NewsChange),
    NewsHistory(Vec<News>),
    /// Сжатое lz4 сообщение, внутри такое же bitcode-кодированное ClientMessage.
    CompressedMessage(Vec<u8>),
    TokenResultInvalid(TokenError),
    TokenResultOk((Vec<ClientSubscriptionInfo>, Vec<GroupedSourceList>)),
    Ping,
    CheckConnection,
    RequestPersonalInfo,
}

#[derive(Clone, Debug, Encode)]
pub struct RequestNewsHistory {
    pub offset: u32,
    pub limit: u32,
}

/// Телеметрия клиента, сервер требует её после CheckConnection.
/// На мобиле большинство полей отсутствуют (None) — они специфичны для браузера.
#[derive(Clone, Debug, Encode, Default)]
pub struct ConnectionInfo {
    pub screen: Option<Screen>,
    pub hardware_concurrency: u8,
    pub device_memory: u32,
    pub url: String,
    pub language: String,
    pub timezone_offset: f64,
    pub network_information: String,
}

#[derive(Clone, Debug, Encode)]
pub struct Screen {
    pub avail_width: Option<i32>,
    pub avail_height: Option<i32>,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub color_depth: Option<i32>,
    pub pixel_depth: Option<i32>,
    pub top: Option<i32>,
    pub left: Option<i32>,
    pub avail_top: Option<i32>,
    pub avail_left: Option<i32>,
    pub orientation: ScreenOrientation,
    pub luminance: Option<ScreenLuminance>,
}

#[derive(Clone, Debug, Encode)]
pub struct ScreenLuminance {
    pub min: f64,
    pub max: f64,
    pub max_average: f64,
}

#[derive(Clone, Debug, Encode)]
pub struct ScreenOrientation {
    pub type_: Option<String>,
    pub angle: Option<u16>,
}

#[derive(Clone, Debug, Encode)]
pub enum ClientMessageForServer {
    RequestNewsHistory(RequestNewsHistory),
    Ping,
    Pong,
    ConnectionInfo(ConnectionInfo),
    UserInfo(String),
    ConsoleReport(f64, f64),
}

/// Состояние соединения для UI (не передаётся по сети).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    TokenInvalid(String),
    Error(String),
}
