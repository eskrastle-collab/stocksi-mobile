import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN читается из --dart-define=SENTRY_DSN=... при сборке.
/// Если не задан — Sentry не инициализируется (no-op), приложение работает
/// как обычно. Так удобно: дев-сборки не шлют события в production-проект.
const _dsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

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
