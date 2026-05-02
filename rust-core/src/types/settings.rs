use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use super::server::GroupedSourceList;

/// Настройки для конкретного виджета / профиля.
/// В мобильном приложении обычно используется один "default" профиль.
/// Портировано из `src/types/news_settings.rs`.
/// Внимание: `Eq` не выводим из-за полей f64.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct NewsSettings {
    // Фильтры тикеров
    pub tickers_black_filter_enabled: bool,
    pub tickers_black_filter: Vec<String>,
    pub tickers_white_filter_enabled: bool,
    pub tickers_white_filter: Vec<String>,

    // Фильтры хэштегов
    pub hashtags_black_filter_enabled: bool,
    pub hashtags_black_filter: Vec<String>,
    pub hashtags_white_filter_enabled: bool,
    pub hashtags_white_filter: Vec<String>,

    // Фильтры фраз
    pub phrases_black_filter_enabled: bool,
    pub phrases_black_filter: Vec<String>,
    pub phrases_white_filter_enabled: bool,
    pub phrases_white_filter: Vec<String>,

    // Источники
    pub source_settings: Vec<SourceSetting>,
    pub source_list: Vec<GroupedSourceList>,

    // Прочие флаги
    pub only_caps_news: bool,
    pub news_created_highlight_enabled: bool,
    pub news_created_highlight_delay: f64,

    // Подсветка текста
    pub text_highlight_enabled: bool,
    pub text_highlight: Vec<TextHighlightRule>,

    // Уведомления
    pub alert_enabled: bool,
    pub alert_volume: u8,
    pub chosen_alert: String,
    pub hashtag_alerts: Vec<HashtagAlert>,

    // Мобила: горячие клавиши не используются, авто-переключение тикера — опционально
    pub ticker_autoswitch_enabled: bool,
    pub ticker_autoswitch_timeout: f64,
}

/// Пользовательский override «включён ли источник».
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SourceSetting {
    pub source: String,
    pub enabled: bool,
}

/// Правило подсветки: список фраз + CSS-стили (для мобилы — парсится в Flutter TextStyle).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TextHighlightRule {
    pub phrases: Vec<String>,
    pub style: String,
    pub comment: String,
}

/// Звуковой алерт для группы хэштегов.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HashtagAlert {
    pub hashtags: Vec<String>,
    pub chosen_alert: String,
}

/// Сводный кэш всех настроек (мапа widget_id → настройки).
#[derive(Debug, Clone, Default)]
pub struct SettingsCache {
    pub settings: HashMap<String, NewsSettings>,
    pub source_name_aliases: HashMap<String, String>,
    pub timezone: String,
}

impl SettingsCache {
    pub fn get_default_settings(&self) -> NewsSettings {
        self.settings.get("default").cloned().unwrap_or_default()
    }
}
