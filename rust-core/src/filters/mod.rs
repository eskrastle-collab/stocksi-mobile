// Логика фильтрации и подсветки. Портируется 1-в-1 из расширения
// (`src/types/news_settings.rs` и `src/page/html_utils.rs`).

use crate::types::news::StoringNews;
use crate::types::settings::NewsSettings;

/// Возвращает true если новость надо отфильтровать (скрыть).
pub fn is_filtered(settings: &NewsSettings, news: &StoringNews) -> bool {
    if settings.only_caps_news && !news.title.chars().any(|c| c.is_uppercase()) {
        return true;
    }
    if filtered_by_tickers(settings, news) {
        return true;
    }
    if filtered_by_hashtags(settings, news) {
        return true;
    }
    if filtered_by_phrases(settings, news) {
        return true;
    }
    if filtered_by_source(settings, news) {
        return true;
    }
    false
}

fn filtered_by_tickers(s: &NewsSettings, n: &StoringNews) -> bool {
    let tickers_upper: Vec<String> = n.tickers.iter().map(|t| t.to_uppercase()).collect();

    if s.tickers_black_filter_enabled && !s.tickers_black_filter.is_empty() {
        let black: Vec<String> = s.tickers_black_filter.iter().map(|t| t.to_uppercase()).collect();
        if tickers_upper.iter().any(|t| black.contains(t)) {
            return true;
        }
    }
    if s.tickers_white_filter_enabled && !s.tickers_white_filter.is_empty() {
        let white: Vec<String> = s.tickers_white_filter.iter().map(|t| t.to_uppercase()).collect();
        if !tickers_upper.iter().any(|t| white.contains(t)) {
            return true;
        }
    }
    false
}

fn filtered_by_hashtags(s: &NewsSettings, n: &StoringNews) -> bool {
    if s.hashtags_black_filter_enabled && !s.hashtags_black_filter.is_empty() {
        if n.tags.iter().any(|t| s.hashtags_black_filter.contains(t)) {
            return true;
        }
    }
    if s.hashtags_white_filter_enabled && !s.hashtags_white_filter.is_empty() {
        if !n.tags.iter().any(|t| s.hashtags_white_filter.contains(t)) {
            return true;
        }
    }
    false
}

fn filtered_by_phrases(s: &NewsSettings, n: &StoringNews) -> bool {
    let haystack = format!(
        "{} {}",
        n.title.to_lowercase(),
        n.short.as_deref().unwrap_or("").to_lowercase()
    );
    if s.phrases_black_filter_enabled && !s.phrases_black_filter.is_empty() {
        if s.phrases_black_filter
            .iter()
            .any(|p| haystack.contains(&p.to_lowercase()))
        {
            return true;
        }
    }
    if s.phrases_white_filter_enabled && !s.phrases_white_filter.is_empty() {
        if !s
            .phrases_white_filter
            .iter()
            .any(|p| haystack.contains(&p.to_lowercase()))
        {
            return true;
        }
    }
    false
}

fn filtered_by_source(s: &NewsSettings, n: &StoringNews) -> bool {
    let Some(source) = &n.source else { return false };
    if let Some(setting) = s.source_settings.iter().find(|x| x.source == *source) {
        return !setting.enabled;
    }
    for group in &s.source_list {
        if let Some(src) = group.source_list.iter().find(|x| x.source_name == *source) {
            return !src.default_enabled;
        }
    }
    false
}
