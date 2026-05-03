import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ForegroundService на Android: показывает persistent notification и
/// удерживает Dart-isolate приложения «живым», когда экран заблокирован
/// или приложение свёрнуто. Это нужно чтобы WS-подключение не рвалось,
/// и push-уведомления о новых новостях продолжали приходить.
///
/// На iOS / Windows / Linux / macOS — no-op (там либо запрещено, либо
/// не нужно — desktop-приложения не убиваются автоматически).
class BackgroundService {
  static const _kEnabledKey = 'background_enabled';

  bool _running = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  bool get isRunning => _running;

  /// Загружено ли разрешение пользователя на фоновую работу из prefs.
  Future<bool> isEnabledByUser() async {
    if (!isSupported) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Сохранить выбор пользователя + (де)активировать сервис.
  Future<void> setEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, v);
    } catch (_) {}
    if (v) {
      await start();
    } else {
      await stop();
    }
  }

  /// Инициализация конфига сервиса (один раз при старте app).
  /// Реальный сервис запускается отдельным `start()` вызовом.
  Future<void> init() async {
    if (!isSupported) return;
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'stocksi_background',
          channelName: 'Stocksi фоновый режим',
          channelDescription:
              'Поддерживает подключение к серверу когда приложение в фоне',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          showWhen: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e) {
      debugPrint('[bg] init failed: $e');
    }
  }

  /// Стартует ForegroundService — Android покажет persistent notification
  /// «Stocksi Ultimate активен», и не будет убивать процесс.
  Future<void> start() async {
    if (!isSupported || _running) return;
    try {
      final isAlreadyRunning =
          await FlutterForegroundTask.isRunningService;
      if (isAlreadyRunning) {
        _running = true;
        return;
      }
      final res = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Stocksi Ultimate',
        notificationText: 'Получает новости в фоне',
        notificationIcon: null, // дефолтная app иконка
        callback: _backgroundCallback,
      );
      if (res is ServiceRequestSuccess) {
        _running = true;
      } else {
        debugPrint('[bg] startService rejected: $res');
      }
    } catch (e) {
      debugPrint('[bg] start failed: $e');
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[bg] stop failed: $e');
    }
    _running = false;
  }
}

final backgroundService = BackgroundService();

/// Callback запускается в отдельном isolate когда сервис стартует.
/// Нам нужен только keepalive — главный isolate с WS клиентом не убивается
/// пока ForegroundService жив. Поэтому handler — пустой stub.
@pragma('vm:entry-point')
void _backgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
