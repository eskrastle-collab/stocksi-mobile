// Smoke test для Rust-ядра. Запуск: cargo run --example smoke
// Проверяет: mock-новости → SQLite запись/чтение → фильтрация → KV-хранилище.

use stocksi_core::{
    api,
    filters::is_filtered,
    storage::{StorageBackend, sqlite::SqliteStorage},
    types::settings::NewsSettings,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("\n=== Stocksi Core Smoke Test ===\n");

    // 1. Моковые новости
    println!("[1] mock_news_list()");
    let mock = api::mock_news_list();
    for n in &mock {
        let tickers = if n.tickers.is_empty() {
            "—".to_string()
        } else {
            n.tickers.join(", ")
        };
        let tags = if n.tags.is_empty() {
            "—".to_string()
        } else {
            n.tags.iter().map(|t| format!("#{t}")).collect::<Vec<_>>().join(", ")
        };
        println!(
            "    #{} | {} | [{}] [{}] | src={:?}",
            n.id,
            n.title.chars().take(60).collect::<String>(),
            tickers,
            tags,
            n.source
        );
    }

    // 2. Открываем SQLite во временной папке
    let tmp = std::env::temp_dir().join("stocksi_smoke.db");
    let _ = std::fs::remove_file(&tmp);
    println!("\n[2] Opening SQLite at {}", tmp.display());
    let storage = SqliteStorage::open(&tmp.to_string_lossy())?;
    println!("    OK — schema initialized");

    // 3. Запись новостей
    println!("\n[3] Writing {} news to SQLite", mock.len());
    for n in &mock {
        storage.insert_news(n)?;
    }
    println!("    OK");

    // 4. Чтение обратно
    println!("\n[4] Reading all news back");
    let read_back = storage.read_all_news()?;
    println!("    Found {} rows", read_back.len());
    assert_eq!(read_back.len(), mock.len(), "count mismatch");
    println!("    OK — round-trip consistent");

    // 5. Настройки — запись/чтение
    println!("\n[5] Settings round-trip");
    let mut settings = NewsSettings::default();
    settings.tickers_black_filter_enabled = true;
    settings.tickers_black_filter = vec!["$GAZP".into()];
    settings.alert_enabled = true;
    settings.alert_volume = 80;
    storage.write_settings("default", &settings)?;
    let read_settings = storage.read_settings("default")?;
    assert_eq!(settings, read_settings);
    println!("    OK — NewsSettings serializable and persistent");

    // 6. Логика фильтрации
    println!("\n[6] Filter logic");
    let gazp_news = &mock[0];
    let sber_news = &mock[2];
    let filtered_gazp = is_filtered(&settings, gazp_news);
    let filtered_sber = is_filtered(&settings, sber_news);
    println!("    GAZP news with black filter [$GAZP]: filtered = {filtered_gazp}");
    println!("    SBER news with black filter [$GAZP]: filtered = {filtered_sber}");
    assert!(filtered_gazp, "GAZP should be filtered");
    assert!(!filtered_sber, "SBER should NOT be filtered");
    println!("    OK — filtering logic works");

    // 7. KV-хранилище
    println!("\n[7] KV storage");
    storage.set_string("token", "test_token_abc123")?;
    storage.set_string("timezone", "Europe/Moscow")?;
    let token = storage.get_string("token")?;
    let timezone = storage.get_string("timezone")?;
    let missing = storage.get_string("nonexistent")?;
    println!("    token: {:?}", token);
    println!("    timezone: {:?}", timezone);
    println!("    nonexistent: {:?}", missing);
    assert_eq!(token.as_deref(), Some("test_token_abc123"));
    assert_eq!(timezone.as_deref(), Some("Europe/Moscow"));
    assert_eq!(missing, None);
    println!("    OK — KV works");

    println!("\n=== All checks passed ===\n");
    Ok(())
}
