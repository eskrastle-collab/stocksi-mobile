# App Privacy — ответы для App Store Connect

Это **самый муторный** раздел App Store Connect. Apple очень дотошны — отвечать врать нельзя, проверяют (ATT-проверка, network sniffing, Privacy Manifest). Лучше **честно сказать** что crash-репорты собираем, чем потом ловить rejection за нераскрытые данные.

Заполняется в App Store Connect → твоё приложение → **App Privacy** (в левой колонке) → **Edit** напротив "Data Types".

---

## Главный вопрос: Do you or your third-party partners collect data from this app?

**Ответ: Yes**

⚠️ Хотя сами мы не собираем — у нас GlitchTip получает crash-данные. С точки зрения Apple это «сбор данных», даже если мы их не используем для рекламы.

После этого Apple покажет матрицу из 14 категорий и ~30 типов данных. Идём по порядку.

---

## Какие данные собираем (заполняем чекбоксами в App Store Connect)

### ✅ Diagnostics → Crash Data

**Включить**: ✅ Yes

Использование (Apple спросит **для чего**):
- ✅ **App Functionality** — да (для исправления багов)
- ❌ Analytics
- ❌ Product Personalization
- ❌ Developer's Advertising or Marketing
- ❌ Third-Party Advertising
- ❌ Other Purposes

Linked to user identity?
- **No** — мы не привязываем краши к Apple ID, токену, IP

Used for tracking?
- **No** — не используем для cross-app/website tracking

### ✅ Diagnostics → Performance Data

**Включить**: ✅ Yes (включается автоматически если используешь Sentry/GlitchTip — отправляет breadcrumbs)

Использование:
- ✅ **App Functionality**

Linked to user identity? **No**
Used for tracking? **No**

### ✅ Diagnostics → Other Diagnostic Data

**Включить**: ✅ Yes (для подстраховки — GlitchTip может отправлять модель устройства, версию iOS)

Использование:
- ✅ **App Functionality**

Linked to user identity? **No**
Used for tracking? **No**

---

## Какие данные **НЕ** собираем (всё остальное оставляем без галочки)

Для справки — **что Apple предложит, и почему мы оставляем без галочки**:

### Contact Info — НЕТ
- ❌ Name
- ❌ Email Address
- ❌ Phone Number
- ❌ Physical Address
- ❌ Other User Contact Info

*(Мы не запрашиваем e-mail / имя / телефон. Связь только через Telegram-бот.)*

### Health & Fitness — НЕТ

*(Совсем не наша тема.)*

### Financial Info — НЕТ
- ❌ Payment Info
- ❌ Credit Info
- ❌ Other Financial Info

*(Подписка идёт через Telegram-бот, не через приложение. У нас в IPA нет SDK Stripe / RevenueCat / Apple Pay платежей.)*

### Location — НЕТ
- ❌ Precise Location
- ❌ Coarse Location

*(Не запрашиваем `CoreLocation`. В Info.plist нет ключей `NSLocationWhenInUseUsageDescription` и т. п.)*

### Sensitive Info — НЕТ

### Contacts — НЕТ

*(Не запрашиваем доступ к адресной книге.)*

### User Content — НЕТ
- ❌ Emails or Text Messages
- ❌ Photos or Videos
- ❌ Audio Data
- ❌ Customer Support
- ❌ Other User Content

*(Пользователь ничего не пишет, ничего не загружает на наши серверы. Кэш новостей хранится локально.)*

### Browsing History — НЕТ

### Search History — НЕТ

### Identifiers — НЕТ
- ❌ User ID
- ❌ Device ID

*(Токен авторизации — это **наш** UUID, выданный сервером, а не идентификатор устройства / Apple ID. Хранится локально в Keychain. Не привязан к IDFA / IDFV.)*

⚠️ **Важно для Apple Review**: токен это **не User ID** в смысле Apple — это authorization secret, аналог пароля. Apple различает "User ID" (стабильный публичный идентификатор пользователя для аналитики) и authorization tokens. Мы — второе.

### Purchases — НЕТ

*(Нет In-App Purchase. Подписка вне приложения, через Telegram-бот.)*

### Usage Data — НЕТ
- ❌ Product Interaction (clicks, sessions, etc.)
- ❌ Advertising Data
- ❌ Other Usage Data

*(Никакой аналитики. Никаких событий, которые бы мы отправляли при открытии экрана / клике на новость.)*

### Other Data — НЕТ

---

## Итого — Privacy Label, который увидит пользователь в App Store

Apple покажет такую плашку:

```
Data Not Linked to You

The following data may be collected but it is not linked to your identity:

  • Diagnostics
```

И всё. Для пользователя это **«самое чистое»** что можно получить — нет ни "Data Linked to You", ни "Data Used to Track You".

---

## Privacy Manifest (PrivacyInfo.xcprivacy) — нужно создать

С 2024 г. Apple **требует** для всех новых приложений файл `PrivacyInfo.xcprivacy` с детализацией по API. Без него **rejection с цитатой ITMS-91056**.

Нужно положить файл `flutter-app/ios/Runner/PrivacyInfo.xcprivacy` со следующим содержимым (создаю отдельно, см. ниже).

Также Apple требует, чтобы у каждой third-party SDK тоже был свой Privacy Manifest. У нас есть SDK без `.xcprivacy`:
- `flutter` framework — Apple добавил поддержку в 3.22
- `sentry_flutter` (мы используем для GlitchTip) — Sentry добавил в v8.0
- `flutter_secure_storage` — добавили в 9.0
- `audioplayers` — добавили в 6.x
- `path_provider` — Apple-провайденный
- `shared_preferences` — Apple-провайденный
- `flutter_local_notifications` — добавили в 17.x
- `flutter_html` — обычно не использует tracking API

Большинство мы уже на новых версиях (см. `pubspec.yaml`). На всякий случай я добавлю проверку перед первым релизом (отдельная задача `Verify all SDK manifests`).

---

## Что отвечать App Reviewer'у если придерётся

Apple Review иногда спрашивает в ITMS-91056 формате: "We've identified that your app uses an API that has been declared in the API Declaration sections of your privacy manifest... The API declaration includes the reason `XXX`. The reason is approved..."

Это **формальная переписка**, не реальная проверка. Приложение **не отклоняют** при первой жалобе — просят пояснить или добавить декларацию. У нас в `PrivacyInfo.xcprivacy` (отдельный файл) уже всё прописано:

- `NSPrivacyAccessedAPICategoryFileTimestamp` — `C617.1` (для path_provider, shared_preferences)
- `NSPrivacyAccessedAPICategoryUserDefaults` — `CA92.1` (для shared_preferences)
- `NSPrivacyAccessedAPICategorySystemBootTime` — `35F9.1` (для timing метрики Flutter framework)
- `NSPrivacyAccessedAPICategoryDiskSpace` — не используем

---

## TL;DR

В App Store Connect → App Privacy:
1. **Yes** на "do you collect data"
2. Чекбоксы: только **Diagnostics → Crash Data, Performance Data, Other Diagnostic Data**
3. Все три: **App Functionality**, **Not Linked**, **Not Used for Tracking**
4. Всё остальное **без галочки**
5. Privacy Manifest `PrivacyInfo.xcprivacy` → положить в репо (см. отдельный шаг ниже)
