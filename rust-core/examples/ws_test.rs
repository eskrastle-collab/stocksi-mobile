// Проверка реального WebSocket соединения с серверным протоколом Stocksi.
//
// Запуск:
//   1. Создайте файл stocksi-mobile/ws_token.txt с вашим токеном (одна строка)
//   2. cargo run --example ws_test
//
// Или через переменную окружения:
//   STOCKSI_TOKEN=... cargo run --example ws_test

use std::time::Duration;
use stocksi_core::types::server::ClientMessage;
use stocksi_core::websocket::{WsClient, WsEvent};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env_logger::try_init().ok();

    // 1. Читаем токен
    let token = read_token()?;
    println!("\n=== WebSocket Test ===");
    println!(
        "Token: {}...{} ({} chars)",
        &token.chars().take(4).collect::<String>(),
        token.chars().rev().take(4).collect::<String>().chars().rev().collect::<String>(),
        token.len()
    );
    println!("URL: wss://websocket.priority.news");
    println!("Timeout: 30s\n");

    // Диагностика сети
    println!("[pre] DNS lookup websocket.priority.news...");
    match tokio::net::lookup_host("websocket.priority.news:443").await {
        Ok(addrs) => {
            let list: Vec<_> = addrs.collect();
            println!("     OK → {list:?}");
        }
        Err(e) => {
            println!("     FAIL → {e}");
            return Ok(());
        }
    }

    println!("[pre] TCP connect to websocket.priority.news:443...");
    match tokio::time::timeout(
        Duration::from_secs(5),
        tokio::net::TcpStream::connect("websocket.priority.news:443"),
    )
    .await
    {
        Ok(Ok(_)) => println!("     OK"),
        Ok(Err(e)) => println!("     FAIL → {e}"),
        Err(_) => println!("     TIMEOUT"),
    }
    println!();

    // Подключение к WS
    let client = WsClient::new(
        stocksi_core::websocket::client::DEFAULT_WS_URL.to_string(),
        token,
    );
    let mut rx = client.spawn();

    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let mut news_count = 0;
    let mut tick = 0;

    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(deadline) => {
                println!("\n[timeout 30s reached]");
                break;
            }
            ev = rx.recv() => {
                let Some(ev) = ev else {
                    println!("[channel closed]");
                    break;
                };
                tick += 1;
                match ev {
                    WsEvent::ConnectionChanged(c) => {
                        println!("[{tick:02}] connection → {c:?}");
                    }
                    WsEvent::Message(msg) => match msg {
                        ClientMessage::TokenResultOk((subs, sources)) => {
                            println!("[{tick:02}] TokenResultOk");
                            println!("     subscriptions: {} шт.", subs.len());
                            for s in &subs {
                                println!(
                                    "       - {} | persistent={} | until={}",
                                    s.subscription_group_name, s.persistent, s.until_timestamp
                                );
                            }
                            let total: usize = sources.iter().map(|g| g.source_list.len()).sum();
                            println!(
                                "     sources: {} групп, {} источников всего",
                                sources.len(),
                                total
                            );
                            for g in &sources {
                                let name = g.group_name.as_deref().unwrap_or("Базовые");
                                println!("       · [{}] {} шт.", name, g.source_list.len());
                            }
                        }
                        ClientMessage::TokenResultInvalid(err) => {
                            println!("[{tick:02}] TokenResultInvalid: {err:?}");
                        }
                        ClientMessage::NewsHistory(list) => {
                            news_count += list.len();
                            println!("[{tick:02}] NewsHistory — {} новостей", list.len());
                            for n in list.iter().take(3) {
                                let title: String = n.title.chars().take(80).collect();
                                println!("       · #{} {}", n.id, title);
                            }
                            if list.len() > 3 {
                                println!("       · ... ещё {}", list.len() - 3);
                            }
                        }
                        ClientMessage::News(n) => {
                            news_count += 1;
                            let title: String = n.title.chars().take(80).collect();
                            println!("[{tick:02}] News — #{} {}", n.id, title);
                        }
                        ClientMessage::UpdateNews(c) => {
                            println!("[{tick:02}] UpdateNews — #{}", c.id);
                        }
                        ClientMessage::DeleteNews(ids) => {
                            println!("[{tick:02}] DeleteNews — {} шт.: {:?}", ids.len(), ids);
                        }
                        ClientMessage::Ticker(t) => {
                            println!("[{tick:02}] Ticker — {} (group {})", t.ticker, t.group_id);
                        }
                        ClientMessage::FilePreload(f) => {
                            println!("[{tick:02}] FilePreload — {} ({} bytes)", f.url, f.data.len());
                        }
                        ClientMessage::Ping => {
                            println!("[{tick:02}] Ping (pong отправлен)");
                        }
                        ClientMessage::Pong => {
                            println!("[{tick:02}] Pong");
                        }
                        ClientMessage::CheckConnection => {
                            println!("[{tick:02}] CheckConnection");
                        }
                        ClientMessage::RequestPersonalInfo => {
                            println!("[{tick:02}] RequestPersonalInfo");
                        }
                        ClientMessage::CompressedMessage(_) => {
                            // Уже разжато в client.rs
                            println!("[{tick:02}] CompressedMessage (should not reach here)");
                        }
                    },
                }
            }
        }
    }

    println!("\n=== Итого ===");
    println!("Событий получено: {tick}");
    println!("Новостей:         {news_count}");
    println!();
    Ok(())
}

fn read_token() -> anyhow::Result<String> {
    if let Ok(t) = std::env::var("STOCKSI_TOKEN") {
        if !t.trim().is_empty() {
            return Ok(t.trim().to_string());
        }
    }
    let path = std::path::Path::new("ws_token.txt");
    if path.exists() {
        let content = std::fs::read_to_string(path)?;
        let token = content.trim().to_string();
        if !token.is_empty() {
            return Ok(token);
        }
    }
    anyhow::bail!(
        "Токен не найден. Создайте файл ws_token.txt в stocksi-mobile/ \
         или задайте переменную STOCKSI_TOKEN"
    );
}
