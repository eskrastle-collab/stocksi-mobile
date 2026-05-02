import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Автообновление desktop-сборок (Windows / macOS) через Sparkle/WinSparkle.
///
/// На сервере (GitLab Pages / GitHub Pages / любой HTTPS) лежит appcast.xml
/// со списком версий. Приложение каждые N часов проверяет его, и если есть
/// новая версия — качает и обновляет.
///
/// Формат appcast.xml: https://sparkle-project.org/documentation/publishing/
/// Пример:
///   <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
///     <channel>
///       <title>Stocksi Ultimate</title>
///       <item>
///         <title>Version 0.2.0</title>
///         <pubDate>Mon, 20 Apr 2026 10:00:00 +0000</pubDate>
///         <enclosure
///           url="https://stocksi-ultimate.ru/releases/stocksi-ultimate-0.2.0.msix"
///           sparkle:version="0.2.0"
///           sparkle:shortVersionString="0.2.0"
///           length="71234567"
///           type="application/octet-stream" />
///       </item>
///     </channel>
///   </rss>
class UpdaterService {
  /// URL до appcast.xml. Переопредели под свой хостинг.
  static const _feedUrl = 'https://stocksi-ultimate.ru/releases/appcast.xml';

  /// Интервал автоматической проверки (сек). 4 часа.
  static const _checkInterval = 60 * 60 * 4;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  Future<void> init() async {
    if (!isSupported) return;
    try {
      await autoUpdater.setFeedURL(_feedUrl);
      await autoUpdater.setScheduledCheckInterval(_checkInterval);
      // Запускаем первую проверку в фоне через ~5 секунд после старта —
      // чтобы не тормозить открытие приложения.
      Future.delayed(const Duration(seconds: 5), () {
        autoUpdater.checkForUpdates();
      });
    } catch (e) {
      debugPrint('[updater] init failed: $e');
    }
  }

  /// Ручная проверка — из кнопки в настройках.
  Future<void> checkNow() async {
    if (!isSupported) return;
    try {
      await autoUpdater.checkForUpdates();
    } catch (e) {
      debugPrint('[updater] check failed: $e');
    }
  }
}

final updaterService = UpdaterService();
