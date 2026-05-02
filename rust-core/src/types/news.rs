use serde::{Deserialize, Serialize};

use super::server::News;

/// Новость для хранения и отображения.
/// Конвертируется из серверной `News` (где `timestamp: i64`, а у нас Option для будущих правок).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
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

impl StoringNews {
    pub fn make(id: u32, title: String) -> Self {
        Self {
            id,
            timestamp: None,
            title,
            short: None,
            source: None,
            tickers: vec![],
            tags: vec![],
            files: vec![],
            full_text_link: None,
        }
    }
}

impl From<News> for StoringNews {
    fn from(n: News) -> Self {
        Self {
            id: n.id,
            timestamp: Some(n.timestamp),
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
