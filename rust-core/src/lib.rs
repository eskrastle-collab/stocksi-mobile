// Stocksi Mobile Core — shared Rust library для Flutter-приложения.
//
// Публичный API через `api` модуль экспортируется в Dart через flutter_rust_bridge.
// Приватные модули — внутренняя логика.

pub mod api;
pub mod filters;
pub mod icons;
pub mod storage;
pub mod types;
pub mod websocket;

// Реэкспорт основных типов для удобства
pub use types::news::StoringNews;
pub use types::settings::{NewsSettings, SourceSetting};
pub use types::server::{ClientMessage, Source, GroupedSourceList};
