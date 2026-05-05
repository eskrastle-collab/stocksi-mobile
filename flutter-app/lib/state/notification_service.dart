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
    // На iOS системный диалог permission покажется при первом
    // requestPermission(), не при init() — поэтому requestAlertPermission
    // и т. п. оставляем false, иначе приложение запросит разрешение сразу
    // при старте, что плохой UX.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
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

  /// Попросить пользователя разрешить уведомления.
  /// Возвращает true если разрешение дано.
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // На iOS используем нативный API plugin'а — он покажет именно
      // системный диалог "Stocksi Ultimate would like to send you
      // notifications". permission_handler на iOS возвращает denied
      // если приложение никогда его не запрашивало через Darwin API.
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: false, // звук свой
          ) ??
          false;
      return granted;
    }
    // Android 13+ — runtime permission. На <13 status сразу granted.
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Проверить не отказал ли пользователь ранее.
  Future<bool> hasPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      // checkPermissions появился в plugin v17 — возвращает текущий статус
      // без показа диалога. Если приложение никогда не запрашивало —
      // вернёт NotificationsEnabledOptions(isEnabled: false, isAlertEnabled:
      // false, ...). Мы трактуем как "нет permission" → пользователь
      // включит через тумблер, который вызовет requestPermission().
      final opts = await iosImpl?.checkPermissions();
      return opts?.isAlertEnabled ?? false;
    }
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
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false, // звук играет SoundService
        interruptionLevel: InterruptionLevel.timeSensitive,
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
