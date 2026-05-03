# Play Console — Data Safety form

В Play Console → App content → Data safety. Заполнять следующее.

## Data collection and security

**Does your app collect or share any of the required user data types?**
→ **No** (приложение не передаёт данные на серверы)

**Is all of the user data collected by your app encrypted in transit?**
→ **Yes** (всё через TLS/WSS)

**Do you provide a way for users to request that their data be deleted?**
→ **Yes** — пользователь может удалить данные через системное меню
«Settings → Apps → Stocksi Ultimate → Storage → Clear data», либо удалить
приложение целиком. Данные хранятся только на устройстве.

## Data types

Если Google всё же требует пометить хоть что-то — отметь:

### App activity → App interactions
- **Collected**: No
- **Shared**: No

### App info and performance → Crash logs / Diagnostics
- **Collected**: No

### Device or other IDs
- **Collected**: No (мы не используем Advertising ID, Android ID, и т. п.)

### Personal info / Contacts / Location / Files / Audio / Camera / Health
- Все — **No**

### Financial info
- **Collected**: No (мы НЕ собираем платежи, банковские реквизиты, данные
  о сделках, портфолио). Подписка покупается в Telegram-боте — это вне
  Приложения.

### Messages
- **Collected**: No

## Security practices

- **Data is encrypted in transit**: Yes
- **Users can request data deletion**: Yes (через clear app data)
- **App follows Play Families Policy**: N/A (не для детей)
- **Independent security review**: No (если есть бюджет — можно потом
  заказать аудит, для текущего этапа не критично)
