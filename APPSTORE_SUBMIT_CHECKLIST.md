# App Store Connect — пошаговое заполнение

Этот чек-лист используется ПОСЛЕ:
1. Apple Developer Program одобрен (`Welcome to the Apple Developer Program`).
2. Сертификаты + provisioning profile + secrets настроены по `IOS_SIGNING_SETUP.md`.
3. Первый билд успешно собран через `git tag v1.0.1 && git push --tags` и обработан в App Store Connect (Processing → Ready to Submit).

Идём по разделам слева направо в App Store Connect → My Apps → Stocksi Ultimate.

---

## 1. Создание App в App Store Connect

→ https://appstoreconnect.apple.com/apps → **+** → **New App**

| Поле | Значение |
|---|---|
| Platforms | ☑ iOS |
| Name | `Stocksi Ultimate` |
| Primary Language | `Russian (Russia)` |
| Bundle ID | `ru.stocksi.ultimate` (выбираешь из списка — должен появиться, если App ID создан в Developer Portal) |
| SKU | `stocksi-ultimate-001` |
| User Access | `Full Access` |

→ **Create**.

---

## 2. App Information (левая колонка)

### Localizable Information (язык — Russian)

| Поле | Значение | Источник |
|---|---|---|
| Name | `Stocksi Ultimate` | STORE_LISTING_APPSTORE.md |
| Subtitle | `Биржевые новости в реальном` | STORE_LISTING_APPSTORE.md |
| Privacy Policy URL | `https://stocksi-ultimate.ru/privacy` | проверь что URL открывается |

### General Information

| Поле | Значение |
|---|---|
| Bundle ID | `ru.stocksi.ultimate` (read-only после создания) |
| SKU | `stocksi-ultimate-001` (read-only) |
| Apple ID | сгенерится автоматом |
| Primary Category | `News` |
| Secondary Category | `Finance` |
| Content Rights | ☑ Does **NOT** contain third-party content (мы пишем тексты сами в виде новостных заголовков, не реплицируем чужие медиа) |

**Age Rating** → Edit:
- Все вопросы **None** кроме:
  - **Unrestricted Web Access**: **Yes** (новости содержат ссылки на источники)
- → Save → получишь **4+** или **9+**.

→ **Save** (правый верх).

---

## 3. Localizations (добавить English)

Левая колонка → Localizations → **+** → **English (U.S.)** → Add.

В разделах ниже (Version, Description) появится секция English. Заполнишь параллельно с RU. Тексты в `STORE_LISTING_APPSTORE.md`.

---

## 4. Pricing and Availability

| Поле | Значение |
|---|---|
| Price Schedule | Free |
| Availability | All Countries / Regions (или ограничь, если хочешь стартовать только с RU+СНГ) |
| Pre-Orders | No |
| Distribution Methods | ☑ Public on the App Store |

→ **Save**.

---

## 5. App Privacy

⚠️ **Самый важный раздел**. Подробные ответы — `APPSTORE_PRIVACY_ANSWERS.md`.

Краткая последовательность:

1. **Get Started** (если первый раз).
2. Question: *Do you or your third-party partners collect data from this app?* → **Yes**.
3. Save → Apple покажет матрицу категорий.
4. **Data Types** (отметить только эти три):
   - ☑ **Diagnostics → Crash Data**
   - ☑ **Diagnostics → Performance Data**
   - ☑ **Diagnostics → Other Diagnostic Data**
5. Для каждой:
   - Purpose: ☑ **App Functionality**
   - Linked to user identity: **No**
   - Used for tracking: **No**
6. Все остальные категории — **без галочки**.
7. → **Publish** (после того как заполнено всё).

Пользователь увидит: `Data Not Linked to You: Diagnostics`.

---

## 6. Prepare for Submission (правая колонка → ваша 1.0)

Слева под Version 1.0 → **Prepare for Submission**.

### App Preview and Screenshots

| Размер | Resolution | Обязательно |
|---|---|---|
| **iPhone 6.9"** | 1320×2868 | **Да** |
| **iPhone 6.5"** | 1242×2688 или 1284×2778 | Желательно |
| **iPad 13"** | 2064×2752 | Только если iPad-секция |

Минимум 2, рекомендую 5. Что снимать — см. STORE_LISTING_APPSTORE.md секция «Скриншоты».

⚠️ Apple ругается, если на скриншотах:
- есть статусбар с реальным временем не 9:41 (пуристы)
- есть «уведомления» от других приложений
- есть разрешения (просьба о доступе к камере и т. п.)

### Promotional Text

```
Лента новостей с тикерами Мосбиржи, СПБ, NYSE и NASDAQ. Подсветка ключевых слов, фильтры, push-уведомления, тёмная тема.
```

(EN — см. STORE_LISTING_APPSTORE.md)

### Description

Скопируй из STORE_LISTING_APPSTORE.md секция «Description».

### Keywords

```
биржа,новости,акции,тикер,торги,мосбиржа,инвестор,рынок,дивиденды,nyse,nasdaq,финансы
```

(86/100 символов. **Без пробелов** после запятых — экономия символов.)

### Support URL / Marketing URL

```
https://stocksi-ultimate.ru
```

### Build

→ **Select a build before you submit your app** → выбери только что загруженный из CI билд `1.0.1 (2)`.

### General App Information

| Поле | Значение |
|---|---|
| App Icon | подгрузится из IPA автоматически (1024×1024 без alpha) |
| Copyright | `© 2026 Stocksi` |
| Routing App Coverage File | (пусто — не Maps app) |

### App Review Information

| Поле | Значение |
|---|---|
| Sign-In Required | ☑ Yes |
| Username | (оставь пустым) |
| Password | reviewer-токен из @StocksiUltimate_bot, **создай одноразовый** |
| Contact Information First Name | твоё имя латиницей |
| Last Name | твоя фамилия латиницей |
| Phone Number | твой |
| Email | es.krastle@gmail.com |
| Notes | скопируй из STORE_LISTING_APPSTORE.md секция «Notes» (на английском) |

### Version Release

Выбираешь один из вариантов:
- ⚪ **Automatically release this version** — после approve моментально публикуется (НЕ рекомендую для первого релиза).
- 🔘 **Manually release this version** — после approve ты сам жмёшь Release когда готов (**рекомендую**).
- ⚪ **Automatically release this version after App Review** with phased release for automatic updates — раскатка процентами 7 дней.

→ Save.

---

## 7. Final Check — Submit for Review

Перед нажатием Submit:

- [ ] Все поля App Information заполнены (RU + EN)
- [ ] Скриншоты загружены (минимум 6.9")
- [ ] App Privacy заполнен и опубликован
- [ ] Build выбран
- [ ] Reviewer token действителен (открыт в боте, не использован для другого)
- [ ] Privacy Policy URL открывается
- [ ] Support URL открывается
- [ ] Notes для ревьюера на английском с инструкциями

→ **Add for Review** (вверху справа) → **Submit to App Review**.

---

## 8. Что происходит дальше

| Этап | Срок | Что делать |
|---|---|---|
| **Waiting for Review** | до 24 часов | ничего, ждать |
| **In Review** | 1-48 часов | ничего |
| **Pending Developer Release** (если Manual) | сразу после approve | жмёшь Release Now |
| **Ready for Sale** | 0-2 часа | приложение появляется в App Store во всех странах |

Иногда Apple заходит на этапе In Review с вопросом — приходит письмо в Resolution Center. Отвечаешь там же, обычно в течение часа.

---

## 9. После публикации

### Обновления

1. Поднимаешь `version` в `pubspec.yaml`: `1.0.1+2 → 1.0.2+3` (build number ОБЯЗАТЕЛЬНО уникальный, иначе Apple не примет).
2. Коммитишь, тэгаешь: `git tag v1.0.2 && git push --tags`.
3. CI собирает билд, заливает в TestFlight автоматически.
4. В App Store Connect → твоё приложение → **+ Version or Platform** → новая версия.
5. Заполняешь только **What's New in This Version** (текст изменений).
6. Выбираешь Build, Submit for Review.
7. Срок review для обновлений обычно быстрее (12-24 часа).

### TestFlight

Параллельно с App Store у тебя есть TestFlight для бета-тестирования.

- **Internal Testing** — до 100 человек (которым ты дашь Apple ID-приглашение). Не требует Review.
- **External Testing** — до 10,000 человек по публичной ссылке. Требует мини-Review (быстрее App Store Review, 24 часа).

Бета-билды живут 90 дней. После — нужен новый билд.

### Phased Release

Apple умеет автоматически раскатывать обновление процентами:
- День 1: 1%
- День 2: 2%
- День 3: 5%
- День 4: 10%
- День 5: 20%
- День 6: 50%
- День 7: 100%

Включается в App Store Connect → твоя версия → **Version Release → Phased Release**. Можно остановить раскатку в любой момент, если в продакшене обнаружится баг.

---

## 10. Если получил Rejection

Самые частые причины и быстрые ответы в Resolution Center:

| Reject reason | Что отвечать |
|---|---|
| 2.1 App Completeness — App requires sign-in | "Reviewer token has been provided in the App Review Information section. Please use it to log in." |
| 2.3.10 Inaccurate Metadata | Поправить subtitle / keywords / описание |
| 5.1.1 Privacy — Data Collection | Сверить App Privacy с реальным поведением приложения, добавить недостающие категории |
| 5.1.2 Privacy — Data Use and Sharing | Привязать Privacy Policy URL к актуальной странице |
| 4.0 Design — Beta-quality content | Добавить детали в скриншоты, проверить что приложение запускается без багов |
| ITMS-91056 Privacy Manifest | Проверить наличие `PrivacyInfo.xcprivacy` (у нас есть, см. `flutter-app/ios/Runner/PrivacyInfo.xcprivacy`) |
| Guideline 4.3 Spam | "This is a niche app for a Russian-speaking financial news audience. We have no other apps." |

Apple не банит за reject — поправил, нажал Resubmit, опять в очередь.
