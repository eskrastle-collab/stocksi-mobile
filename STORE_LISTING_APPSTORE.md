# App Store Connect — заготовка listing

Все тексты с учётом лимитов Apple. Для каждого поля указан лимит. **Считай по символам, не по словам**: Apple режет жёстко по count символов.

Локализации: **основная — Russian (Russia)**, дополнительная — **English (U.S.)**. Apple Review будет читать английскую версию.

---

## App Information

### App Name (макс 30 символов)

**RU:**
```
Stocksi Ultimate
```
*(16 символов)*

**EN:**
```
Stocksi Ultimate
```
*(16 символов)*

### Subtitle (макс 30 символов)

**RU:**
```
Биржевые новости в реальном
```
*(27 символов)*

**EN:**
```
Real-time stock market news
```
*(27 символов)*

### Bundle ID

```
ru.stocksi.ultimate
```

### SKU (любой уникальный, не показывается)

```
stocksi-ultimate-001
```

### Primary Language

```
Russian
```

### Category

- **Primary**: `News`
- **Secondary**: `Finance`

⚠️ **Не выбирать** Trading / Investment — попадёт под Apple Financial Services policy и потребует лицензию ЦБ или брокера.

---

## Pricing and Availability

- **Price**: Free
- **Availability**: All countries / regions (либо ограничь до Russia + СНГ, если хочешь не светиться в US моментально)
- **Pre-orders**: No

---

## App Privacy

⚠️ **Самый важный раздел Apple-модерации**. Заполняется отдельно от listing. Подробные ответы — см. `APPSTORE_PRIVACY_ANSWERS.md`.

Краткий итог: **Data Not Collected** (не собираем никакие данные). Кратко — потому что:
- токен, настройки, кэш — всё локально
- никакой аналитики, никаких трекеров
- crash reports (GlitchTip) — обезличенные, опциональные

---

## Localizable (RU)

### Promotional Text (макс 170 символов, можно менять без нового билда)

```
Лента новостей с тикерами Мосбиржи, СПБ, NYSE и NASDAQ. Подсветка ключевых слов, фильтры, push-уведомления, тёмная тема.
```
*(125 символов)*

### Description (макс 4000 символов)

```
Stocksi Ultimate — новостной агрегатор для активных российских инвесторов. Поток биржевых новостей в реальном времени с моментальной доставкой через защищённый WebSocket-канал.

ВОЗМОЖНОСТИ

• Лента новостей по российским и зарубежным эмитентам — котирующимся на Мосбирже, СПБ Бирже, NYSE, NASDAQ.
• Десятки источников — информационные агентства, корпоративные пресс-релизы, макроэкономические индикаторы. Любые группы можно включить или выключить в настройках.
• Гибкие фильтры — чёрные и белые списки тикеров, хэштегов, ключевых фраз. Хотите видеть только дивиденды? Только санкции? Настраивается в одно касание.
• Подсветка текста — собственный DSL: задаёте правила вида «дивиденды@green» и слово автоматически выделяется в каждой новости. Поддержка цвета, фона, размера и веса шрифта.
• Звуковые алерты — отдельные звуки для разных категорий новостей. Например, отчётность играет одним звуком, санкции — другим.
• Уведомления — приходят даже когда экран заблокирован, через системный центр уведомлений iOS.
• Тёмная и светлая темы — переключаются одной кнопкой.
• Свайп-жесты — поделиться, скопировать, открыть оригинал, вернуться назад.

КОНФИДЕНЦИАЛЬНОСТЬ

Приложение не собирает персональные данные. Все настройки и токен авторизации хранятся локально на устройстве в защищённом хранилище iOS Keychain. Ни аналитики, ни трекеров, ни рекламных SDK.

ВАЖНО

Приложение не оказывает финансовых услуг, не выполняет торговых операций и не даёт инвестиционных рекомендаций. Это исключительно средство просмотра новостной ленты для информированных решений. Все инвестиционные решения вы принимаете самостоятельно.

ДОСТУП

Лента доступна по токену, который выдаётся через Telegram-бот @StocksiUltimate_bot. Подписка приобретается там же.

КОНТАКТЫ

Сайт: stocksi-ultimate.ru
Поддержка: @StocksiUltimate_bot
```

### Keywords (макс 100 символов, через запятую, **БЕЗ пробелов** после запятых)

```
биржа,новости,акции,тикер,торги,мосбиржа,инвестор,рынок,дивиденды,nyse,nasdaq,финансы
```
*(86 символов)*

### Support URL (обязательно)

```
https://stocksi-ultimate.ru
```

### Marketing URL (опционально)

```
https://stocksi-ultimate.ru
```

### Privacy Policy URL (обязательно)

```
https://stocksi-ultimate.ru/privacy
```

### Copyright

```
© 2026 Stocksi
```

---

## Localizable (EN — для Apple Review reviewer)

### Promotional Text (170)

```
Live news feed for Moscow Exchange, SPB Exchange, NYSE, NASDAQ tickers. Custom highlighting, filters, push notifications, dark theme. Token-based access.
```
*(155 символов)*

### Description (4000)

```
Stocksi Ultimate is a real-time news aggregator for active investors trading on Russian and foreign exchanges. The app delivers stock market news as it happens via a secure WebSocket channel.

FEATURES

• Live feed of news on companies listed on the Moscow Exchange (MOEX), SPB Exchange, NYSE, and NASDAQ.
• Dozens of sources — news agencies, corporate press releases, macroeconomic indicators. Toggle any group on or off in settings.
• Flexible filters — black and white lists for tickers, hashtags, keywords. Only want dividends? Only sanctions? One tap.
• Text highlighting — a custom DSL: define rules like "dividends@green" and the word is automatically highlighted in every news item. Full CSS color, background, font-size, and font-weight support.
• Sound alerts — different sounds for different news categories. Earnings reports play one sound, sanctions play another.
• Notifications — delivered to iOS notification center even when the screen is locked.
• Light and dark themes — toggle with one tap.
• Swipe gestures — share, copy, open source, navigate back.

PRIVACY

The app does not collect personal data. All settings and the authorization token are stored locally on your device in iOS Keychain. No analytics, no trackers, no advertising SDKs.

IMPORTANT

This app does not provide financial services, does not execute trades, and does not offer investment recommendations. It is solely a news feed reader for informed decision-making. All investment decisions are made by the user independently.

ACCESS

The feed is accessed via a token issued through the Telegram bot @StocksiUltimate_bot. Subscriptions are also purchased there.

CONTACT

Website: stocksi-ultimate.ru
Support: @StocksiUltimate_bot
```

### Keywords (100)

```
stocks,news,market,ticker,trading,moex,investor,finance,nyse,nasdaq,dividends,stockmarket
```
*(89 символов)*

### Support / Marketing / Privacy URL

Те же, что и в RU.

### Copyright

```
© 2026 Stocksi
```

---

## Version Information (для каждой новой версии)

### What's New (макс 4000)

**Для версии 1.0.1 (первый релиз в App Store):**

**RU:**
```
Первый релиз Stocksi Ultimate в App Store.

Что внутри:
• Живая лента биржевых новостей по тикерам Мосбиржи, СПБ Биржи, NYSE и NASDAQ
• Подсветка ключевых слов с собственным DSL
• Звуковые алерты для разных категорий новостей
• Push-уведомления с iOS
• Тёмная и светлая темы
• Свайп-жесты для share / copy / open

Доступ — по токену из Telegram-бота @StocksiUltimate_bot.
```

**EN:**
```
First release of Stocksi Ultimate on the App Store.

What's inside:
• Live stock market news feed covering MOEX, SPB Exchange, NYSE, NASDAQ
• Keyword highlighting with a custom DSL
• Sound alerts for different news categories
• iOS push notifications
• Light and dark themes
• Swipe gestures for share / copy / open

Access via token from Telegram bot @StocksiUltimate_bot.
```

---

## App Review Information

### Sign-In Information

⚠️ Apple Reviewer **обязательно** попросит способ протестировать приложение — без токена он увидит только экран ввода токена.

- **Sign-in required**: ✅ Yes
- **Username**: (оставь пустым, у нас нет username)
- **Password**: (одноразовый токен из Telegram-бота, **создать перед отправкой**)

```
Reviewer Token: [ВСТАВИТЬ ОДНОРАЗОВЫЙ ТОКЕН ИЗ TELEGRAM-БОТА]
```

### Contact Information

- First Name: твоё имя латиницей
- Last Name: твоя фамилия латиницей
- Phone Number: твой номер
- Email: es.krastle@gmail.com

### Notes (для App Reviewer'а — на английском)

```
Stocksi Ultimate is a stock market news aggregator for the Russian-speaking investor audience. The app does NOT provide:
- Financial advisory services
- Trading or order execution
- Brokerage services
- Investment recommendations

It only displays a curated news feed delivered via a private WebSocket. Access requires a token, which users obtain via the Telegram bot @StocksiUltimate_bot.

For testing:
1. Launch the app — you will see a token entry screen.
2. Enter the reviewer token below.
3. The news feed will load automatically.
4. Try swiping news items, opening Settings (gear icon, top-right), and toggling sources/filters/highlights.

Reviewer test token (one-time use):
[INSERT TOKEN]

This token is dedicated to App Review. We will revoke it after approval. To request a new test token at any time, contact us via the Telegram bot above.

Privacy: The app stores all data locally (iOS Keychain for the token, app sandbox for settings/cache). No analytics, no trackers, no third-party SDKs aside from a crash reporter (GlitchTip) that sends anonymized error reports without any user data.

Encryption: The app uses standard HTTPS/WSS for the news WebSocket. We declared `ITSAppUsesNonExemptEncryption = false` in Info.plist (only standard cryptography).
```

### Attachment

Не нужен.

---

## Build (загружается из CI)

После запуска `git tag v1.0.1 && git push --tags`:
1. Workflow `ios-release.yml` собирает подписанный IPA.
2. Заливает в App Store Connect.
3. Билд появляется в **TestFlight → Builds**, статус Processing → Ready.
4. В App Store Connect → твоё приложение → **App Store** → текущая версия → **Build** → выбери только что загруженный.

---

## Age Rating Questionnaire

Все ответы — **None / No**, кроме:
- **Frequent/Intense Mature/Suggestive Themes**: None
- **Unrestricted Web Access**: **Yes** (новости содержат ссылки на источники, открываются во встроенном браузере / Safari)

Финальный рейтинг будет **4+** или **9+**. Для финансового приложения этого достаточно — Apple НЕ требует лицензии на чтение биржевых новостей.

---

## Encryption Compliance

Apple спрашивает при первой загрузке билда:

- **Does your app use encryption?** → **Yes** (TLS WebSocket)
- **Is your app's encryption exempt?** → **Yes — only standard encryption (HTTPS/TLS)**

⚠️ В `Info.plist` уже выставлено `ITSAppUsesNonExemptEncryption = false`, и Apple больше не будет спрашивать это для каждого нового билда.

---

## Скриншоты — что нужно

Apple **требует** скриншоты для как минимум одного размера экрана:

| Устройство | Размер | Обязательно? |
|---|---|---|
| **iPhone 6.9"** (15/16 Pro Max) | 1320×2868 | **Да**, главный |
| **iPhone 6.5"** (11 Pro Max / XS Max) | 1242×2688 или 1284×2778 | Желательно (старые устройства) |
| **iPad 13"** (Pro M4) | 2064×2752 | Только если включишь iPad-секцию |

**Сколько**: минимум **2**, максимум **10**. На 3-5 кадрах легче пройти модерацию (показать что приложение реально функциональное).

**Контент скриншотов** (рекомендация):
1. Лента новостей в тёмной теме с подсветкой ключевых слов и разноцветными чипами тикеров
2. Настройки → Фильтры (черно-белые списки)
3. Настройки → Подсветка (DSL с примерами правил)
4. Детальный просмотр новости + tab-переключение на оригинал
5. Светлая тема (для контраста)

**Как сделать без устройства**: я подготовлю отдельный workflow `screenshots.yml`, который запускает iOS Simulator на macos-runner, прогоняет integration_test и сохраняет PNG-скриншоты как артефакты. Сделаем после первого билда.

Если есть iPhone — проще: открыть приложение, **Power + Volume Up** одновременно, перенести через AirDrop / iCloud / e-mail.

---

## Чек-лист перед Submit for Review

- [ ] App Store listing заполнен полностью (RU + EN)
- [ ] App Privacy questions отвечены (см. APPSTORE_PRIVACY_ANSWERS.md)
- [ ] Скриншоты загружены (минимум 6.9" / 6.5")
- [ ] Build загружен через CI и выбран в Version
- [ ] Age Rating пройден
- [ ] Encryption Compliance — exempt
- [ ] Reviewer Token сгенерирован через @StocksiUltimate_bot и вставлен в Notes
- [ ] Privacy Policy URL открывается (https://stocksi-ultimate.ru/privacy)
- [ ] Support URL открывается (https://stocksi-ultimate.ru)

→ Submit for Review. Срок рассмотрения **24–48 часов** обычно.

---

## После одобрения

- Apple автоматически публикует, либо ждёт ручного релиза (опция в App Store Connect: **Manually release this version**).
- Если выберешь Manual — после approve ты сам жмёшь **Release** когда готов.
- **Phased Release** (раскатка процентами 1%/2%/5%/10%/20%/50%/100% за 7 дней) включается там же — рекомендую для первого релиза, чтобы при крашах остановить раскатку.
