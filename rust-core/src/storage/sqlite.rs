// SQLite-реализация StorageBackend.

use anyhow::{Context, Result};
use rusqlite::{Connection, params};
use std::sync::Mutex;

use super::StorageBackend;
use crate::types::news::StoringNews;
use crate::types::settings::NewsSettings;

pub struct SqliteStorage {
    conn: Mutex<Connection>,
}

impl SqliteStorage {
    /// Открывает/создаёт SQLite базу по пути. Путь обычно даёт платформа
    /// (на Android это `getFilesDir()`, на iOS — `NSDocumentDirectory`).
    pub fn open(path: &str) -> Result<Self> {
        let conn = Connection::open(path).context("Failed to open SQLite DB")?;
        Self::init_schema(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    fn init_schema(conn: &Connection) -> Result<()> {
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS news (
                id          INTEGER PRIMARY KEY,
                json        TEXT NOT NULL,
                timestamp   INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_news_timestamp ON news(timestamp);

            CREATE TABLE IF NOT EXISTS settings (
                widget_id   TEXT PRIMARY KEY,
                json        TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS kv (
                key         TEXT PRIMARY KEY,
                value       TEXT NOT NULL
            );
            ",
        )?;
        Ok(())
    }
}

impl StorageBackend for SqliteStorage {
    fn insert_news(&self, news: &StoringNews) -> Result<()> {
        let json = serde_json::to_string(news)?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO news (id, json, timestamp) VALUES (?1, ?2, ?3)",
            params![news.id, json, news.timestamp],
        )?;
        Ok(())
    }

    fn update_news(&self, news: &StoringNews) -> Result<()> {
        self.insert_news(news)
    }

    fn delete_news(&self, ids: &[u32]) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        for id in ids {
            conn.execute("DELETE FROM news WHERE id = ?1", params![id])?;
        }
        Ok(())
    }

    fn read_all_news(&self) -> Result<Vec<StoringNews>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT json FROM news ORDER BY timestamp DESC")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            let json: String = row?;
            if let Ok(n) = serde_json::from_str::<StoringNews>(&json) {
                out.push(n);
            }
        }
        Ok(out)
    }

    fn clear_news(&self) -> Result<()> {
        self.conn.lock().unwrap().execute("DELETE FROM news", [])?;
        Ok(())
    }

    fn read_settings(&self, widget_id: &str) -> Result<NewsSettings> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT json FROM settings WHERE widget_id = ?1")?;
        let row: Option<String> = stmt
            .query_row(params![widget_id], |r| r.get(0))
            .ok();
        Ok(row
            .and_then(|j| serde_json::from_str::<NewsSettings>(&j).ok())
            .unwrap_or_default())
    }

    fn write_settings(&self, widget_id: &str, settings: &NewsSettings) -> Result<()> {
        let json = serde_json::to_string(settings)?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO settings (widget_id, json) VALUES (?1, ?2)",
            params![widget_id, json],
        )?;
        Ok(())
    }

    fn get_string(&self, key: &str) -> Result<Option<String>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT value FROM kv WHERE key = ?1")?;
        Ok(stmt.query_row(params![key], |r| r.get(0)).ok())
    }

    fn set_string(&self, key: &str, value: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO kv (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }
}
