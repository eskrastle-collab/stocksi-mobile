# Stocksi Mobile — POC (Flutter + Rust FFI)

Мобильное приложение на базе Stocksi Ultimate Chrome Extension.

## Структура

```
stocksi-mobile/
├── Cargo.toml                      # workspace root
├── flutter_rust_bridge.yaml        # конфиг кодогенератора FFI
├── rust-core/                      # shared Rust library
│   ├── examples/smoke.rs           # smoke-test без Flutter (cargo run --example smoke)
│   └── src/
│       ├── lib.rs                  # entry point
│       ├── api.rs                  # публичный API → Dart
│       ├── types/                  # StoringNews, NewsSettings, ClientMessage
│       ├── websocket/              # tokio-tungstenite клиент
│       ├── storage/                # SQLite (rusqlite)
│       └── filters/                # is_filtered()
└── flutter-app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── bridge/                 # сгенерированный Dart-код
        ├── state/                  # Riverpod провайдеры
        └── ui/                     # экраны
```

## Быстрая проверка Rust-ядра (без Flutter)

```bash
cd stocksi-mobile
cargo run --example smoke
```

Должен напечатать 7 OK-проверок: mock-новости, SQLite round-trip, фильтрация, KV.

## Запуск мобильного приложения

### 1. Установить инструменты

```bash
# Flutter SDK
# https://docs.flutter.dev/get-started/install

# Rust (если ещё нет)
# https://rustup.rs

# flutter_rust_bridge codegen
cargo install flutter_rust_bridge_codegen

# Для Android:
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Для iOS:
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

### 2. Создать Flutter-проект внутри flutter-app/

```bash
cd flutter-app
flutter create --platforms=android,ios .
```

### 3. Инициализировать flutter_rust_bridge

```bash
# Из корня stocksi-mobile/
flutter_rust_bridge_codegen integrate
flutter_rust_bridge_codegen generate
```

### 4. Подключить `mock_news_list()` в UI

В `flutter-app/lib/state/news_provider.dart` раскомментировать импорт и вызов:

```dart
import '../bridge/api.dart';

final newsListProvider = FutureProvider<List<StoringNews>>((ref) async {
  return mockNewsList();
});
```

### 5. Запустить

```bash
cd flutter-app
flutter run
```

## Архитектура: data flow

```
┌────────────────┐         ┌──────────────────┐         ┌─────────────┐
│  Flutter UI    │◄────────┤  FFI (generated) │◄────────┤  Rust core  │
│  (Riverpod)    │  Stream │   Dart↔Rust      │         │             │
└────────────────┘         └──────────────────┘         └──────┬──────┘
                                                                │
                                               ┌────────────────┼────────────────┐
                                               │                │                │
                                               ▼                ▼                ▼
                                       ┌──────────────┐  ┌────────────┐  ┌──────────────┐
                                       │  WebSocket   │  │  Storage   │  │   Filters    │
                                       │  (tungste-   │  │  (SQLite)  │  │  /highlight  │
                                       │   nite)      │  │            │  │              │
                                       └──────┬───────┘  └────────────┘  └──────────────┘
                                              │
                                              ▼
                                     wss://websocket.priority.news
```

**Rust-слой держит всё бизнес-состояние** (кэш новостей, настройки, WS-подключение). Flutter подписывается на стрим событий из `api.rs::start_websocket()` и просто отображает данные.

## Background и push-уведомления

| Платформа | Подход |
|-----------|--------|
| Android   | Foreground Service с WebSocket + уведомление в шторке. Работает пока процесс жив. |
| iOS       | WebSocket в фоне недоступен → сервер отправляет APNs push при новости → приложение пробуждается, берёт недостающие новости за период сна. |
