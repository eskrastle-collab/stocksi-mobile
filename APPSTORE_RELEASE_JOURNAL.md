# App Store Release Journal — Stocksi Ultimate

Журнал работы по релизу приложения в Apple App Store.
Используется как single-source-of-truth для контекста: новая Claude-сессия / новый разработчик / возврат к проекту через полгода — всё что нужно знать здесь.

---

## TL;DR

**Что:** Stocksi Ultimate, агрегатор биржевых новостей в реальном времени для русскоязычных трейдеров.
**Стек:** Flutter 3.41.9 + Rust (через flutter_rust_bridge 2.12).
**Bundle ID:** `ru.stocksi.ultimate`
**Apple ID:** `6766567212`
**Apple Team ID:** `923976S3S8`
**Текущий статус:** ✅ **РЕЛИЗ** — v1.0.9 (build 10) одобрен Apple и опубликован в App Store **2026-05-07/08**. Прошли review с первой попытки.

---

## Архитектура и зависимости

- **UI:** Flutter (`flutter-app/lib/`)
- **Bridge:** `flutter_rust_bridge` 2.12 (`flutter-app/rust_builder/`)
- **Rust core:** `rust/src/` — WebSocket, парсинг, бизнес-логика
- **CI:** GitHub Actions (`.github/workflows/ios-release.yml`)
- **Crash reporting:** `sentry_flutter` → self-hosted GlitchTip (`flutter-app/lib/state/sentry_setup.dart`)
- **Push:** локальные iOS уведомления через `flutter_local_notifications` (пока приложение запущено). APNs server-side — на v1.1.

---

## Хронология релиза iOS (декабрь 2025 — май 2026)

### Этап 0 — Apple Developer Program

- Регистрация в Apple Developer Program ($99/год)
- Подтверждение оплаты, Team ID `923976S3S8`

### Этап 1 — Signing infrastructure

См. подробно: [`IOS_SIGNING_SETUP.md`](./IOS_SIGNING_SETUP.md)

Создано:
1. **CSR** (Certificate Signing Request) → загружено в Apple Developer
2. **Apple Distribution Certificate** (.cer → .p12 с приватным ключом)
3. **App ID** `ru.stocksi.ultimate` (Capabilities: Push Notifications заявлено, но не используется в v1.0)
4. **Provisioning Profile** `Stocksi Ultimate AppStore` (App Store distribution)
5. **App Store Connect API Key** (Issuer `ZFSJ8882JD`, Key ID `927d134b-0f9f-4911-a664-cc45276c19ec`) — для CI upload

GitHub Secrets:
- `APPLE_DISTRIBUTION_P12_BASE64` — .p12 в base64
- `APPLE_DISTRIBUTION_P12_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_BASE64` — App Store Connect API

### Этап 2 — GitHub Actions CI

Workflow: `.github/workflows/ios-release.yml`

Ключевые фиксы по ходу первого билда:
- **macos-latest + Xcode latest-stable** через `maxim-lobanov/setup-xcode@v1` — Apple требует iOS 26 SDK с осени 2025, дефолтный Xcode 16.4 на macos-latest не подходил.
- **Manual signing** в `Runner.xcodeproj/project.pbxproj` (`CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM=923976S3S8`, `CODE_SIGN_IDENTITY="Apple Distribution"`) — без этого `apple-actions/import-codesign-certs@v3` не находил cert в keychain.
- **Decode .p8 from base64** перед передачей в `apple-actions/upload-testflight-build@v3`: action ожидает plain-text PEM, а в Secrets хранится base64 (commit `7c8c06d`).

`ExportOptions.plist`:
```xml
signingStyle: manual
teamID: 923976S3S8
provisioningProfiles: { "ru.stocksi.ultimate": "Stocksi Ultimate AppStore" }
```

### Этап 3 — Privacy Manifest

Apple требует `PrivacyInfo.xcprivacy` с 2024. Зарегистрирован в `Runner.xcodeproj/project.pbxproj` (4 references). Содержит required-reason API declarations + флаг `NSPrivacyTracking=false`.

### Этап 4 — TestFlight builds (1.0.1 → 1.0.9)

| Версия | Тег | Что нового |
|---|---|---|
| 1.0.1 (2) | `v1.0.1` | Первый успешный build в TestFlight. Базовый функционал. |
| 1.0.2 (3) | `v1.0.2` | Push permission UX (SnackBar с «Открыть» → `openAppSettings()`); SafeArea для нижней плашки; sound iOS category fix. |
| 1.0.3 (4) | `v1.0.3` | iOS sound: `playback` category (играл всегда, даже в silent). |
| 1.0.4 (5) | `v1.0.4` | Share button: добавлен `sharePositionOrigin` (без него iPhone-share падал). |
| 1.0.5 (6) | `v1.0.5` | iOS sound revert: `ambient` + `duckOthers` (silent switch снова уважается, по фидбэку). |
| 1.0.6 (7) | `v1.0.6` | UI: status bar перенесён сверху на низ. |
| 1.0.7 (8) | `v1.0.7` | UX: pull-down toggle top-bar, scroll-top FAB снизу, красный dot для disconnected, `playLoud` для теста звука в silent. |
| 1.0.8 (9) | `v1.0.8` | UI revert: bottom bar обратно вниз (pull-down toggle не зашёл), home-indicator зона задействована. |
| 1.0.9 (10) | `v1.0.9` | UX финал: убрали pull-to-refresh, переименовали лейбл «STOCKSI ULTIMATE» → «ULTIMATE CONNECT», смягчили формулировку про push в STORE_LISTING (без обещания background pushes). |

### Этап 5 — Marketing screenshots

Скрипт: [`scripts/make_appstore_screenshots.py`](./scripts/make_appstore_screenshots.py)

5 готовых маркетинговых скринов с:
- Брендовый вертикальный градиент (#0F1721 → #1C293A)
- Tagline (Segoe UI Bold, белый) + subtitle (Segoe UI Regular, серый)
- Скрин телефона со скруглёнными углами (radius=64) и тенью-свечением (blur=50, opacity=110)

Содержание (порядок в App Store):

1. **Лента биржевых новостей** / В реальном времени через WebSocket (тёмная тема)
2. **Тёмная и светлая темы** / Переключение в одно касание (светлая тема)
3. **Свой звук для каждого триггера** / Алерты по хэштегам (настройки → уведомления)
4. **Фильтры и подсветка** / Свой DSL для ключевых слов (настройки → фильтры)
5. **Десятки источников** / Эмитенты, агентства, тг-каналы и прочие (настройки → источники)

Генерируется в трёх размерах (Apple App Store Connect требует все три tab):
- `final/6.9/` — 1320×2868 (iPhone 16 Pro Max)
- `final/6.5/` — 1242×2688 (iPhone 11 Pro Max / XS Max)
- `final/ipad-13/` — 2064×2752 (iPad Pro 13" — universal app требование)

Source-скрины: iPhone 15 Pro Max, native 1290×2796 PNG.
Папка: `C:\Users\eskra\Downloads\appstore-screenshots\`

Запуск:
```bash
PYTHONIOENCODING=utf-8 python scripts/make_appstore_screenshots.py
```

### Этап 6 — App Store Connect listing

См. полные тексты: [`STORE_LISTING_APPSTORE.md`](./STORE_LISTING_APPSTORE.md)

Заполнено:
- **Название:** Stocksi Ultimate
- **Subtitle:** Биржевые новости в реальном
- **Категория:** Новости (primary), Финансы (secondary)
- **Возрастной рейтинг:** 4+ (Unrestricted Web Access = Yes, остальное None)
- **Локализации:** Russian (основная) + English (для App Reviewer)
- **Promotional Text + Description + Keywords:** см. STORE_LISTING_APPSTORE.md
- **Support URL:** https://stocksi-ultimate.ru
- **Privacy Policy URL:** https://stocksi-ultimate.ru/privacy
- **Pricing:** Free, базовая страна US (Russia убрана из base pricing после 2022), доступен по миру
- **Mac App Store:** **выключено** (не тестировали на M1+, оставили на v1.2)

### Этап 7 — App Privacy

См. подробно: [`APPSTORE_PRIVACY_ANSWERS.md`](./APPSTORE_PRIVACY_ANSWERS.md)

⚠️ **Важно:** заявили **«Yes, we collect data»** (а не «No data collected»).

Причина: в проекте активен Sentry → GlitchTip (`flutter-app/lib/state/sentry_setup.dart`). DSN зашит, шлёт по умолчанию. Apple отслеживает реальный network traffic и режет на расхождении с декларацией.

Категории:
- **Diagnostics → Crash Data**
- **Diagnostics → Performance Data**

Для каждой:
- Linked to User: **No** (`sendDefaultPii = false` в коде)
- Used for Tracking: **No**
- Purpose: **App Functionality** (single)

### Этап 8 — Encryption + Content Rights

- **Encryption:** Yes / Exempt (только HTTPS/TLS). В `Info.plist` стоит `ITSAppUsesNonExemptEncryption = false` — Apple больше не спрашивает на каждый билд.
- **Content Rights:** Yes / Yes (новости — публичная информация, источники указаны в самом UI).

### Этап 9 — Submit for Review

Дата отправки: **2026-05-07**.
Ожидаемый срок проверки: 24–48 часов.

### Этап 10 — Approved & Released ✅

**Дата релиза: 2026-05-07/08.** Apple одобрил с первой попытки, без замечаний.
Приложение доступно в App Store по ссылке:
```
https://apps.apple.com/app/id6766567212
```

---

## Что НЕ сделано / Roadmap

### v1.1 — Background pushes (APNs)

**Сейчас:** local-notifications работают только пока приложение запущено. iOS suspend'ит app через ~30s в background → WebSocket рвётся → пушей нет.

**Решение:** APNs server-side. Сервер генерит push через Apple endpoint. Требует:
- APNs Auth Key (`.p8`) или APNs cert
- Регистрация device token на старте app (через `flutter_local_notifications` или native FCM)
- Backend integration для отправки push при новой новости из WebSocket

Оценка: 2-3 дня работы.

### v1.2 — Mac App Store

Сейчас отключено. Требует:
- Тестирование на M1/M2/M3/M4 Mac
- Проверка `audioplayers` на macOS (может потребоваться отдельная конфигурация)
- Проверка `flutter_local_notifications` permissions для macOS
- Adaptive UI для широкого экрана

### v1.3 — iPad-native UI

Сейчас iPad-скрины показывают iPhone-форм-фактор на iPad-полотне (так Apple принимает для universal apps). Для качественного iPad-experience нужен:
- Sidebar layout
- Multi-pane (список + детали)
- Hover states для trackpad

---

## Файлы документации в репо

| Файл | Назначение |
|---|---|
| `APPSTORE_RELEASE_JOURNAL.md` | **(этот файл)** Хронология релиза |
| `STORE_LISTING_APPSTORE.md` | Тексты для App Store Connect (RU + EN) |
| `APPSTORE_PRIVACY_ANSWERS.md` | Ответы на App Privacy questionnaire |
| `APPSTORE_SUBMIT_CHECKLIST.md` | Чек-лист перед Submit for Review |
| `IOS_SIGNING_SETUP.md` | Setup signing infrastructure (cert/profile/CI) |
| `PRIVACY.md` | Privacy Policy (исходник) |
| `DATA_SAFETY.md` | Заполнение Google Data Safety (для RuStore/GP) |
| `RUSTORE_LISTING.md` | Тексты для RuStore |
| `STORE_LISTING.md` | Общий store listing (база) |
| `README.md` | Обзор проекта |

## Ключевые пути на машине разработчика

```
C:\Users\eskra\Downloads\stocksi-mobile\               проект
C:\Users\eskra\Downloads\appstore-screenshots\          скрины
  ├── source\                                            iPhone-original PNG
  └── final\
      ├── 6.9\        1320×2868
      ├── 6.5\        1242×2688
      └── ipad-13\    2064×2752
```

## Telegram-бот (для пользователей и App Reviewer)

`@StocksiUltimate_bot` — выдача токенов авторизации. Reviewer Token генерируется там же при необходимости.

---

## После одобрения / Rejection — план действий

### Если Approved
1. Apple отправляет письмо «Your App Has Been Approved»
2. Если выбран **Manual release** в App Store Connect — жмём **Release** когда готово
3. Опционально: включить **Phased Release** (1%/2%/5%/10%/20%/50%/100% за 7 дней)
4. Мониторим crash reports через GlitchTip первые 24-48 часов

### Если Rejected
Полный текст письма скидываем в новую Claude-сессию с указанием Guideline (например, `2.1 Performance` или `5.1.1 Privacy`). Типичные причины и фиксы:

- **2.1 Performance / Sign-In** — reviewer не смог залогиниться: подкрутить Reviewer Token + Notes
- **2.3.7 Metadata** — скрины не отражают функционал: пересмотреть marketing screenshots
- **5.1.1 Privacy** — нестыковка декларации с реальным трафиком: проверить App Privacy answers
- **5.2.1 Intellectual Property** — источники без прав: дополнить Notes объяснением (новости публичные)
- **4.0 Design** — UX замечания: правки по их feedback

Любая правка → новый билд → bump версии до 1.0.10 → push tag → CI собирает → новый Submit.

---

*Последнее обновление: 2026-05-08 (релиз в App Store).*
