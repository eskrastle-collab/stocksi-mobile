# Stocksi Ultimate — Claude context

Кратко для новой Claude-сессии в этом репо.

## Что это

**Stocksi Ultimate** — агрегатор биржевых новостей в реальном времени для русскоязычных трейдеров.
Стек: **Flutter 3.41.9 + Rust** через `flutter_rust_bridge` 2.12.

- Bundle ID: `ru.stocksi.ultimate`
- Apple Team ID: `923976S3S8`
- Apple ID (App Store Connect): `6766567212`

## Текущий статус релиза

См. полную хронологию: **[`APPSTORE_RELEASE_JOURNAL.md`](./APPSTORE_RELEASE_JOURNAL.md)** ← начни отсюда

Кратко: **v1.0.9 (build 10) отправлен в App Store на review 2026-05-07**, ждём результата 24–48 часов.

## Где что лежит

| Документ | О чём |
|---|---|
| `APPSTORE_RELEASE_JOURNAL.md` | **Главное** — журнал всего пути v1.0.9 |
| `STORE_LISTING_APPSTORE.md` | Тексты для App Store Connect (RU + EN) |
| `APPSTORE_PRIVACY_ANSWERS.md` | Ответы на App Privacy questionnaire |
| `APPSTORE_SUBMIT_CHECKLIST.md` | Чек-лист перед Submit |
| `IOS_SIGNING_SETUP.md` | Signing infrastructure (cert / profile / CI) |
| `RUSTORE_LISTING.md` / `STORE_LISTING.md` | Альтернативные store-листинги |

## Ключевые скрипты

- `scripts/make_appstore_screenshots.py` — генерация маркетинговых скринов в 3 размерах (1320×2868 / 1242×2688 / 2064×2752). Запуск: `PYTHONIOENCODING=utf-8 python scripts/make_appstore_screenshots.py`. Source-скрины кладутся в `C:\Users\eskra\Downloads\appstore-screenshots\source\`.
- `.github/workflows/ios-release.yml` — CI для TestFlight (триггер: `git tag v1.x.y && git push --tags`).

## Архитектура

- **UI:** `flutter-app/lib/`
- **Bridge:** `flutter_rust_bridge` (`flutter-app/rust_builder/`)
- **Rust core:** `rust/src/` — WebSocket, парсинг, бизнес-логика
- **Crash reporting:** Sentry SDK → self-hosted GlitchTip (`flutter-app/lib/state/sentry_setup.dart`). DSN зашит, активен по дефолту, `sendDefaultPii = false`.
- **Push:** локальные iOS уведомления через `flutter_local_notifications`. Реальные APNs background pushes — на v1.1.

## Roadmap

- **v1.1** APNs server-side для real background pushes
- **v1.2** Mac App Store (после тестирования на M1+)
- **v1.3** iPad-native adaptive UI

## Если возвращаемся к проекту через время

1. Сначала прочитай **`APPSTORE_RELEASE_JOURNAL.md`** целиком.
2. Проверь актуальный статус в App Store Connect → My Apps → Stocksi Ultimate.
3. Если был rejection — полный текст письма от Apple = твой следующий вход.
4. Любая правка → новый build → bump `pubspec.yaml` версии → push git tag → CI собирает.
