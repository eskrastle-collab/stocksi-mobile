import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';

import 'src/rust/frb_generated.dart';
import 'state/auth_provider.dart';
import 'state/news_provider.dart';
import 'state/notification_service.dart';
import 'state/sound_service.dart';
import 'state/tray_service.dart';
import 'state/updater_service.dart';
import 'ui/news_list_screen.dart';
import 'ui/token_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop-специфика: инициализируем window_manager до Rust/UI чтобы окно
  // настроилось корректно (preventClose — для сворачивания в трей).
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (isDesktop) {
    try {
      await windowManager.ensureInitialized();
      const opts = WindowOptions(
        size: Size(520, 820),
        minimumSize: Size(400, 600),
        center: true,
        title: 'Stocksi Ultimate',
        skipTaskbar: false,
      );
      await windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('[init] window_manager failed: $e');
    }
  }
  // Каждый шаг инициализации в try-catch — иначе любой сбой даёт чёрный экран
  try {
    await RustLib.init();
  } catch (e, st) {
    debugPrint('[init] RustLib.init failed: $e\n$st');
  }
  try {
    await initializeDateFormatting('ru_RU', null);
  } catch (e) {
    debugPrint('[init] date formatting failed: $e');
  }
  try {
    await soundService.init();
  } catch (e) {
    debugPrint('[init] sound init failed: $e');
  }
  try {
    await notificationService.init();
  } catch (e) {
    debugPrint('[init] notifications init failed: $e');
  }
  if (isDesktop) {
    try {
      await trayService.init();
    } catch (e) {
      debugPrint('[init] tray init failed: $e');
    }
    try {
      await updaterService.init();
    } catch (e) {
      debugPrint('[init] updater init failed: $e');
    }
  }
  runApp(const ProviderScope(child: StocksiApp()));
}

/// Цвета из расширения (stocksi.ru/ultimate) — «пастельный» графит вместо
/// чисто чёрного. Тёмная и светлая темы идут парой.
class _StocksiPalette {
  // dark (--pro-* night)
  static const darkBg = Color(0xFF1E2C39); // body
  static const darkSurface = Color(0xFF243442); // карточка / панель
  static const darkSurfaceHigh = Color(0xFF2C3C4B); // дивайдер / граница
  // Title. В CSS расширения = #B3C7DB, но Roboto Flex + subpixel-AA в
  // Chromium делает его визуально значительно ярче чем Flutter рендерит
  // тот же hex. Компенсируем яркостью.
  static const darkText = Color(0xFFE0E9F2);
  // short / fulltext / footer — CSS расширения #A6BDD5; чуть поднимаем яркость
  // чтобы компенсировать тот же font-rendering разрыв что и у title.
  static const darkTextMuted = Color(0xFFC0D3E4);
  static const accentLight = Color(0xFF62A1FF); // ссылки в dark
  static const accent = Color(0xFF336FEE); // кнопки / акцент

  // light (--pro-* day)
  static const lightBg = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF6F7F9);
  static const lightBorder = Color(0xFFDFE4ED);
  // Title в light: CSS = #334657, но визуально в Chromium темнее. Усиливаем.
  static const lightText = Color(0xFF1A2635);
  // CSS #3C5469; темнее для лучшей читаемости на светлом фоне.
  static const lightTextMuted = Color(0xFF27384A);
}

/// Типографика как в расширении stocksi.ru/ultimate:
/// база 13px, Roboto, компактные line-height.
/// - titleMedium  — заголовок новости (1.15em × 13 ≈ 15px, w500, lh 1.34)
/// - bodyMedium   — short-текст (13px, w400, lh 1.23)
/// - labelSmall   — source / timestamp (12px, w400, lh 1.23)
/// - labelMedium  — чипы тикера / хэштега (12px, w500, lh 1.54)
TextTheme _stocksiTextTheme(Color onSurface, Color onSurfaceMuted) {
  TextStyle s(double size, FontWeight w, double h, Color color) => TextStyle(
        fontSize: size,
        fontWeight: w,
        height: h,
        color: color,
        letterSpacing: 0,
      );
  // Как в расширении:
  // .stocksiNewsTitle → --pro-text-01 (primary)
  // .stocksiNewsShort / .NewsFooter → --pro-text-02 (muted)
  return TextTheme(
    titleLarge: s(17, FontWeight.w600, 1.3, onSurface),
    // CSS расширения: w500. В Flutter Roboto w500 рендерится тоньше чем
    // Roboto Flex 500 в Chromium — используем w600 для визуального паритета.
    titleMedium: s(15, FontWeight.w600, 1.34, onSurface),
    titleSmall: s(14, FontWeight.w600, 1.3, onSurface),
    bodyLarge: s(13, FontWeight.w400, 1.23, onSurfaceMuted),
    bodyMedium: s(13, FontWeight.w400, 1.23, onSurfaceMuted),
    bodySmall: s(12, FontWeight.w400, 1.23, onSurfaceMuted),
    labelLarge: s(13, FontWeight.w500, 1.23, onSurface),
    labelMedium: s(12, FontWeight.w500, 1.54, onSurface),
    labelSmall: s(12, FontWeight.w400, 1.23, onSurfaceMuted),
  );
}

ThemeData _buildStocksiTheme({required bool dark}) {
  final scheme = dark
      ? ColorScheme(
          brightness: Brightness.dark,
          primary: _StocksiPalette.accentLight,
          onPrimary: Colors.white,
          secondary: _StocksiPalette.accent,
          onSecondary: Colors.white,
          surface: _StocksiPalette.darkSurface,
          onSurface: _StocksiPalette.darkText,
          surfaceContainerLowest: _StocksiPalette.darkBg,
          surfaceContainerLow: _StocksiPalette.darkBg,
          surfaceContainer: _StocksiPalette.darkSurface,
          surfaceContainerHigh: _StocksiPalette.darkSurfaceHigh,
          surfaceContainerHighest: _StocksiPalette.darkSurfaceHigh,
          onSurfaceVariant: _StocksiPalette.darkTextMuted,
          outline: _StocksiPalette.darkSurfaceHigh,
          outlineVariant: _StocksiPalette.darkSurfaceHigh,
          error: const Color(0xFFE85454),
          onError: Colors.white,
        )
      : ColorScheme(
          brightness: Brightness.light,
          primary: _StocksiPalette.accent,
          onPrimary: Colors.white,
          secondary: _StocksiPalette.accent,
          onSecondary: Colors.white,
          surface: _StocksiPalette.lightSurface,
          onSurface: _StocksiPalette.lightText,
          surfaceContainerLowest: _StocksiPalette.lightBg,
          surfaceContainerLow: _StocksiPalette.lightBg,
          surfaceContainer: _StocksiPalette.lightSurface,
          surfaceContainerHigh: _StocksiPalette.lightBorder,
          surfaceContainerHighest: _StocksiPalette.lightBorder,
          onSurfaceVariant: _StocksiPalette.lightTextMuted,
          outline: _StocksiPalette.lightBorder,
          outlineVariant: _StocksiPalette.lightBorder,
          error: const Color(0xFFD03A3A),
          onError: Colors.white,
        );
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    // Шрифт как в расширении: Roboto Flex → встроенный Roboto fallback.
    // Явное указание заставляет движок выбрать стандартный Material-стек,
    // а не системный (не плыть между платформами).
    fontFamily: 'Roboto',
    textTheme: _stocksiTextTheme(
      scheme.onSurface,
      scheme.onSurfaceVariant,
    ),
    scaffoldBackgroundColor:
        dark ? _StocksiPalette.darkBg : _StocksiPalette.lightBg,
    canvasColor: dark ? _StocksiPalette.darkBg : _StocksiPalette.lightBg,
    dividerColor:
        dark ? _StocksiPalette.darkSurfaceHigh : _StocksiPalette.lightBorder,
    appBarTheme: AppBarTheme(
      backgroundColor:
          dark ? _StocksiPalette.darkBg : _StocksiPalette.lightBg,
      foregroundColor:
          dark ? _StocksiPalette.darkText : _StocksiPalette.lightText,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: dark ? _StocksiPalette.darkText : _StocksiPalette.lightText,
      ),
    ),
  );
}

class StocksiApp extends ConsumerStatefulWidget {
  const StocksiApp({super.key});

  @override
  ConsumerState<StocksiApp> createState() => _StocksiAppState();
}

class _StocksiAppState extends ConsumerState<StocksiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Стартуем как foreground (сразу после runApp приложение видно).
    notificationService.appInForeground = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Push-уведомления показываем только когда приложение НЕ активно.
    // resumed = видно на экране (не дублируем).
    notificationService.appInForeground = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Stocksi Ultimate',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _buildStocksiTheme(dark: false),
      darkTheme: _buildStocksiTheme(dark: true),
      home: const _RootRouter(),
    );
  }
}

/// Корневой роутер: показывает splash во время init, TokenScreen или NewsListScreen
/// в зависимости от `AuthStage`. Переходы — плавный fade + slide.
class _RootRouter extends ConsumerWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(authProvider).stage;

    Widget screen;
    switch (stage) {
      case AuthStage.initializing:
        screen = const _SplashScreen(key: ValueKey('splash'));
        break;
      case AuthStage.ready:
        screen = const NewsListScreen(key: ValueKey('news'));
        break;
      default:
        // awaitingToken / applying / success / error — всё в TokenScreen
        screen = const TokenScreen(key: ValueKey('token'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        // Новый экран: fade + лёгкий slide снизу
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: screen,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}
