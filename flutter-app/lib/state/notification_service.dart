import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../src/rust/api/simple.dart';

/// Показ системных Android-уведомлений о новостях.
/// Инициализируется один раз при старте приложения.
class NotificationService {
  static const _channelId = 'stocksi_news';
  static const _channelName = 'Новости Stocksi';
  static const _channelDesc = 'Уведомления о новых новостях';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;
  // Если приложение на экране — не дублируем уведомлением, пользователь и так
  // видит новость в ленте + слышит звук.
  bool _appInForeground = true;

  /// Обновляется из _LifecycleObserver в main.dart по AppLifecycleState.
  set appInForeground(bool v) => _appInForeground = v;

  /// Вызывается один раз в main() до runApp().
  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Создаём канал явно (на Android 8+ без этого звук/приоритет не применятся).
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: false, // Звук играет наш SoundService, не нотификация
        enableVibration: true,
      ),
    );
    _initialized = true;
  }

  /// Попросить пользователя разрешить уведомления (Android 13+).
  /// Возвращает true если разрешение дано.
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Проверить не отказал ли пользователь ранее.
  Future<bool> hasPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Показать уведомление о новости. Тихое — звук играет SoundService.
  Future<void> showNews({
    required String title,
    String? body,
    List<String> tickers = const [],
  }) async {
    if (!_initialized) return;
    // Не дублируем когда приложение активно на экране
    if (_appInForeground) return;
    // Проверяем флаг — вдруг пользователь только что выключил
    bool enabled;
    try {
      enabled = await getPushEnabled();
    } catch (_) {
      enabled = false;
    }
    if (!enabled) return;

    // Префикс с тикерами в title для быстрого сканирования
    final fullTitle =
        tickers.isNotEmpty ? '${tickers.join(' ')} · $title' : title;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: true,
        ticker: 'Новая новость',
        styleInformation: BigTextStyleInformation(''),
      ),
    );

    try {
      await _plugin.show(_nextId++, fullTitle, body, details);
      // Не копим notifications в UI — оставляем последние 20
      if (_nextId > 100) _nextId = 0;
    } catch (e) {
      debugPrint('[notifications] show failed: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

final notificationService = NotificationService();
