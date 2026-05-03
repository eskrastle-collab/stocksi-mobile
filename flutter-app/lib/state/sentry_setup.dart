import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN GlitchTip-проекта. По умолчанию используется наш production-эндпоинт.
/// При желании можно переопределить через --dart-define=SENTRY_DSN=... при
/// сборке (например, использовать отдельный dev-проект для тест-событий).
///
/// DSN не является секретом: SDK шлёт на host из этого URL, "слив" даёт
/// максимум возможность отправлять поддельные события — управляется через
/// rate-limit в GlitchTip project settings.
const _dsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://b832a578b54c47d69a2bf4264af9385a@app.glitchtip.com/22962',
);

/// Инициализирует Sentry если задан DSN, и запускает [appRunner].
/// Если DSN пуст — просто запускает [appRunner] напрямую.
///
/// Sentry ловит:
///   • необработанные исключения Flutter (`FlutterError.onError`)
///   • необработанные ошибки в `runZonedGuarded`-зоне
///   • native crashes (Android NDK + iOS)
///
/// Что НЕ ловит:
///   • Rust panics через flutter_rust_bridge — для этого нужна отдельная
///     интеграция с `sentry-rust` (на будущее).
Future<void> runWithSentry(Future<void> Function() appRunner) async {
  if (_dsn.isEmpty) {
    if (kDebugMode) {
      debugPrint('[sentry] SENTRY_DSN not set — error reporting disabled');
    }
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _dsn;
      // Релиз-метка чтобы события группировались по версиям приложения.
      // Подтянется автоматически из pubspec через CI или Flutter SDK.
      options.environment = kDebugMode ? 'debug' : 'release';
      // Performance traces 10% — достаточно для общей картины,
      // не выжирает квоту бесплатного тира (5k events/месяц).
      options.tracesSampleRate = 0.1;
      // Чтобы PII (личные данные) не попадали в события — Sentry SDK
      // по дефолту снимает IP, user-agent и т.п. Для нас это лишнее.
      options.sendDefaultPii = false;
      // Логи stdout/print не отправляем — их в release нет всё равно.
      options.attachStacktrace = true;
      options.debug = kDebugMode;
    },
    appRunner: appRunner,
  );
}
