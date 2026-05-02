import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Сервис system tray для desktop-сборок (Windows / macOS / Linux).
/// На мобильных платформах все методы — no-op.
///
/// Поведение:
///   • Клик на иконку в трее → показать/скрыть окно
///   • Меню: «Показать», «Выход»
///   • Закрытие окна крестиком → сворачивается в трей, WS-соединение
///     продолжает жить, уведомления о новостях приходят.
class TrayService with TrayListener, WindowListener {
  // На Windows tray традиционно использует ICO (многоразмерный формат).
  // На macOS/Linux — PNG.
  static String get _iconPath =>
      Platform.isWindows ? 'assets/icon/app_icon.ico' : 'assets/icon/app_icon.png';
  static const _tooltip = 'Stocksi Ultimate';

  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    try {
      // window_manager: перехват close → hide в трей вместо exit
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);

      // tray_manager: иконка + меню + listener кликов
      await trayManager.setIcon(_iconPath);
      await trayManager.setToolTip(_tooltip);
      await trayManager.setContextMenu(
        Menu(items: [
          MenuItem(key: 'show', label: 'Показать'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Выход'),
        ]),
      );
      trayManager.addListener(this);
      _initialized = true;
    } catch (e) {
      debugPrint('[tray] init failed: $e');
    }
  }

  // ── WindowListener ──────────────────────────────────────────────────

  @override
  Future<void> onWindowClose() async {
    // Крестик — не выходим, а прячем в трей. WS продолжает жить.
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  // ── TrayListener ────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    _toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'exit':
        _exit();
        break;
    }
  }

  Future<void> _toggleWindow() async {
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.hide();
    } else {
      await _showWindow();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    // Реально выходим: снимаем preventClose и закрываем.
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> dispose() async {
    if (!isSupported || !_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }
}

final trayService = TrayService();
