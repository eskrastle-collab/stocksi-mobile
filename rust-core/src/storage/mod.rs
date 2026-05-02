// Абстракция хранилища: типаж + конкретная реализация SQLite.
// Аналог IndexedDB + chrome.storage.local из расширения.

use anyhow::Result;

use crate::types::news::StoringNews;
use crate::types::settings::NewsSettings;

pub mod sqlite;

/// Универсальный интерфейс хранилища. Реализуется SQLite, потенциально in-memory для тестов.
pub trait StorageBackend: Send + Sync {
    // Новости
    fn insert_news(&self, news: &StoringNews) -> Result<()>;
    fn update_news(&self, news: &StoringNews) -> Result<()>;
    fn delete_news(&self, ids: &[u32]) -> Result<()>;
    fn read_all_news(&self) -> Result<Vec<StoringNews>>;
    fn clear_news(&self) -> Result<()>;

    // Настройки (один профиль "default" для мобилы)
    fn read_settings(&self, widget_id: &str) -> Result<NewsSettings>;
    fn write_settings(&self, widget_id: &str, settings: &NewsSettings) -> Result<()>;

    // KV-хранилище для токена, таймзоны, alias'ов источников
    fn get_string(&self, key: &str) -> Result<Option<String>>;
    fn set_string(&self, key: &str, value: &str) -> Result<()>;
}
