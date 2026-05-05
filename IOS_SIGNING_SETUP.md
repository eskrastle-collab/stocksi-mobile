# iOS Signing Setup — TestFlight + App Store

Инструкция, как настроить подписанную сборку iOS в GitHub Actions без необходимости иметь Mac. Делается **один раз** после одобрения Apple Developer Program. Дальше каждый релиз — просто `git tag v1.0.x && git push --tags`, дальше CI сам соберёт подписанный IPA и зальёт в TestFlight.

---

## Что нам нужно создать

| # | Файл/значение | Где создаётся | Куда кладётся |
|---|---|---|---|
| 1 | Distribution Certificate (`.p12`) | developer.apple.com → Certificates | GitHub Secret `APPLE_CERTIFICATE_BASE64` |
| 2 | Пароль от .p12 | мы придумываем сами | GitHub Secret `APPLE_CERTIFICATE_PASSWORD` |
| 3 | App ID `ru.stocksi.ultimate` | developer.apple.com → Identifiers | (ничего, просто должен существовать) |
| 4 | Provisioning Profile (`.mobileprovision`) | developer.apple.com → Profiles | GitHub Secret `APPLE_PROVISIONING_PROFILE_BASE64` |
| 5 | Team ID | developer.apple.com → Membership | GitHub Secret `APPLE_TEAM_ID` |
| 6 | App в App Store Connect | appstoreconnect.apple.com → My Apps | (ничего, просто должно существовать) |
| 7 | App Store Connect API Key (`.p8`) | appstoreconnect.apple.com → Users → Keys | GitHub Secret `APP_STORE_CONNECT_API_KEY_BASE64` |
| 8 | Key ID + Issuer ID | там же | Secrets `APP_STORE_CONNECT_API_KEY_ID` + `APP_STORE_CONNECT_API_ISSUER_ID` |

---

## Шаг 1. CSR (Certificate Signing Request) на Windows

Apple генерит сертификат не сама, а на основе CSR, который мы создаём у себя. На Mac это делается через Keychain Access. Мы — через `openssl` на Windows.

```powershell
# В PowerShell, в любой пустой папке (например, C:\Users\eskra\Downloads\apple-signing):
mkdir C:\Users\eskra\Downloads\apple-signing
cd C:\Users\eskra\Downloads\apple-signing

# 1. Генерируем приватный ключ.
openssl genrsa -out stocksi-ios.key 2048

# 2. Генерируем CSR. На вопросы можно отвечать что угодно, кроме Common Name и Email.
openssl req -new -key stocksi-ios.key -out stocksi-ios.csr `
  -subj "/emailAddress=es.krastle@gmail.com/CN=Evgenii Krasilnikov/C=RU"
```

На выходе у тебя в папке два файла:
- `stocksi-ios.key` — приватный ключ, **никому не показываем**.
- `stocksi-ios.csr` — этот загружаем в Apple на следующем шаге.

---

## Шаг 2. Distribution Certificate в Apple Developer

1. Открываем https://developer.apple.com/account/resources/certificates/list
2. Жмём `+` (новый сертификат).
3. В разделе **Software** выбираем **Apple Distribution** (один сертификат на iOS+macOS, рекомендованный путь).
4. Continue.
5. **Choose File** → выбираем `stocksi-ios.csr` из шага 1.
6. Continue → Download. Получаешь файл `distribution.cer`.

Кладём его рядом с `stocksi-ios.key` в `apple-signing/`.

---

## Шаг 3. Конвертация .cer + .key → .p12

`.cer` — это публичная часть. Чтобы Xcode/CI мог подписывать, нужно склеить публичную часть с приватным ключом в формат `.p12` (он же PKCS#12).

```powershell
# В той же папке apple-signing:

# 1. Конвертируем .cer (DER) в PEM
openssl x509 -inform DER -in distribution.cer -out distribution.pem

# 2. Объединяем сертификат + ключ в .p12
# Когда спросит Export Password — придумай и запомни (это будет APPLE_CERTIFICATE_PASSWORD)
openssl pkcs12 -export `
  -inkey stocksi-ios.key `
  -in distribution.pem `
  -out stocksi-ios.p12 `
  -name "Apple Distribution: Evgenii Krasilnikov"
```

Готово, есть `stocksi-ios.p12`.

⚠️ **Если openssl попросит** `legacy provider` (некоторые версии openssl 3.x по умолчанию не делают p12 совместимым с macOS), используй:
```powershell
openssl pkcs12 -export -legacy `
  -inkey stocksi-ios.key `
  -in distribution.pem `
  -out stocksi-ios.p12 `
  -name "Apple Distribution: Evgenii Krasilnikov"
```

---

## Шаг 4. App ID

1. https://developer.apple.com/account/resources/identifiers/list
2. `+` → **App IDs** → Continue → **App** → Continue.
3. Description: `Stocksi Ultimate`
4. Bundle ID: **Explicit** → `ru.stocksi.ultimate`
5. Capabilities: ничего не отмечать (нам не нужен Push, Background и т. д. — у нас всё локальное).
6. Continue → Register.

---

## Шаг 5. Provisioning Profile

1. https://developer.apple.com/account/resources/profiles/list
2. `+` → **App Store** (под Distribution) → Continue.
3. App ID: выбираем `ru.stocksi.ultimate`.
4. Certificates: выбираем тот distribution-сертификат, который создали на шаге 2.
5. Provisioning Profile Name: `Stocksi Ultimate AppStore`
6. Continue → Download. Получаешь `Stocksi_Ultimate_AppStore.mobileprovision`.

Кладём в `apple-signing/`.

---

## Шаг 6. Team ID

1. https://developer.apple.com/account/#MembershipDetailsCard
2. Скопировать **Team ID** (10-символьный код, например `ABCDE12345`).

---

## Шаг 7. App в App Store Connect

1. https://appstoreconnect.apple.com/apps
2. `+` → New App.
3. Platforms: **iOS**.
4. Name: `Stocksi Ultimate` (или просто `Ultimate`, до 30 символов).
5. Primary Language: Russian (Russia).
6. Bundle ID: выбираем `ru.stocksi.ultimate` (тот, что создали в шаге 4).
7. SKU: `stocksi-ultimate-001` (любая уникальная строка).
8. User Access: Full Access.
9. Create.

---

## Шаг 8. App Store Connect API Key

Это нужно для автозаливки билда из CI в TestFlight.

1. https://appstoreconnect.apple.com/access/integrations/api
2. Если первый раз — жмём **Request Access** → подтверждаем по почте.
3. После активации: `+` → New Key.
4. Name: `GitHub Actions CI`.
5. Access: **Admin** (нужно для upload).
6. Generate.
7. **Сразу скачиваем** `.p8` файл (`AuthKey_XXXXXXXXXX.p8`) — повторно скачать нельзя.
8. Запоминаем:
   - **Key ID** (10-символьный код, например `2X9Y8Z7A6B`) — будет в столбце "Key ID".
   - **Issuer ID** (UUID, в самом верху страницы под "Issuer ID") — например `12345678-1234-1234-1234-123456789012`.

---

## Шаг 9. Конвертация в base64

В PowerShell:

```powershell
cd C:\Users\eskra\Downloads\apple-signing

# 1. .p12 → base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("stocksi-ios.p12")) | Set-Clipboard
# Вставь в Notepad или сразу в GitHub Secret APPLE_CERTIFICATE_BASE64

# 2. .mobileprovision → base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Stocksi_Ultimate_AppStore.mobileprovision")) | Set-Clipboard
# → APPLE_PROVISIONING_PROFILE_BASE64

# 3. .p8 → base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard
# → APP_STORE_CONNECT_API_KEY_BASE64
```

Каждая команда копирует результат в буфер обмена — сразу вставляй в GitHub.

---

## Шаг 10. GitHub Secrets

https://github.com/Aksiomatik/stocksi-mobile/settings/secrets/actions

Жмём **New repository secret** для каждого:

| Name | Value |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | base64 от `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | пароль, который придумал на шаге 3 |
| `APPLE_PROVISIONING_PROFILE_BASE64` | base64 от `.mobileprovision` |
| `APPLE_TEAM_ID` | 10-символьный код из шага 6 |
| `APP_STORE_CONNECT_API_KEY_BASE64` | base64 от `.p8` |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID из шага 8 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID из шага 8 |

---

## Шаг 11. Запуск

```bash
git tag v1.0.1
git push origin v1.0.1
```

Открой Actions → iOS Release (TestFlight) — увидишь прогресс. Если всё ок:
- ~25 минут на сборку
- IPA попадёт в артефакты workflow
- IPA автоматом загрузится в App Store Connect
- Через 10-30 минут билд появится в **TestFlight → Builds**, статус сначала "Processing", потом "Ready to Test"
- Установишь TestFlight на iPhone, добавишь себя как Internal Tester — установишь на устройство

---

## Если что-то пошло не так

| Ошибка | Причина | Что делать |
|---|---|---|
| `No signing certificate "iOS Distribution" found` | .p12 не импортировался | Проверь APPLE_CERTIFICATE_PASSWORD, попробуй `-legacy` при создании .p12 |
| `Provisioning profile doesn't include the currently selected device` | wrong profile | Убедись что профайл — App Store, не Ad Hoc |
| `Invalid Team ID` | опечатка | Скопируй Team ID ещё раз с developer.apple.com |
| `Authentication failed` (TestFlight upload) | API key плохой | Перезалей `.p8` в base64 без `\n` |
| `Bundle identifier doesn't match` | App ID не создан или другой | Проверь шаг 4 |
| `Asset validation failed: invalid icons` | иконки имеют alpha-канал | Уже исправлено в `pubspec.yaml` (`remove_alpha_ios: true`) |

---

## Срок жизни

- **Distribution Certificate**: 1 год — потом продлить (создать новый и заменить .p12).
- **Provisioning Profile**: 1 год.
- **App Store Connect API Key**: бессрочный, можно отозвать.
- **Apple Developer membership**: 1 год — продлевается ежегодно за $99.
