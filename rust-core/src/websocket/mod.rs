// WebSocket-клиент к wss://websocket.priority.news.
// Заменяет web-sys WebSocket из расширения на tokio-tungstenite.

pub mod client;

pub use client::{WsClient, WsEvent};
