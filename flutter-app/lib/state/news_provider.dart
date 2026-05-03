import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/simple.dart';
import 'auth_provider.dart';
import 'notification_service.dart';
import 'sound_service.dart';
import 'text_highlight.dart';
import 'widget_service.dart';

/// Состояние подключения к серверу.
enum ConnectionStatus { idle, connecting, connected, disconnected, error }

class WsConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;
  const WsConnectionState({required this.status, this.errorMessage});
  static const initial = WsConnectionState(status: ConnectionStatus.idle);
}

final connectionStatusProvider =
    StateProvider<WsConnectionState>((ref) => WsConnectionState.initial);

/// Текст баннера «сессия перехвачена другим устройством». null — всё в порядке.
/// Сервер шлёт TokenResultInvalid(TooManyConnections) когда тот же токен уже
/// используется где-то ещё. UI показывает баннер в ленте.
final sessionTakenOverProvider = StateProvider<String?>((ref) => null);

/// Каталог источников от сервера (группы + источники в них).
/// Обновляется на каждом TokenResultOk.
final sourceGroupsProvider =
    StateProvider<List<SourceGroup>>((ref) => const []);

/// ID новостей, появившихся недавно (для fade-in анимации 3.5 сек).
/// При добавлении новости — ID попадает сюда и удаляется через 3.5 сек.
final recentNewsIdsProvider = StateProvider<Set<int>>((ref) => <int>{});

/// DSL правил подсветки. Источник истины — SQLite (KV key `text_highlight_dsl`).
/// Провайдер держит кэш в памяти. Запись — через [saveHighlightDsl].
class HighlightDslNotifier extends StateNotifier<String> {
  HighlightDslNotifier() : super('') {
    _load();
  }

  Future<void> _load() async {
    try {
      final dsl = await getTextHighlightDsl();
      state = dsl;
    } catch (_) {
      // Core ещё не инициализирован — повторяем попытку через 200мс
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        state = await getTextHighlightDsl();
      } catch (_) {}
    }
  }

  Future<void> save(String dsl) async {
    state = dsl;
    try {
      await setTextHighlightDsl(dsl: dsl);
    } catch (e) {
      // Logging only — не показываем ошибку в UI
    }
  }
}

final highlightDslProvider =
    StateNotifierProvider<HighlightDslNotifier, String>(
  (ref) => HighlightDslNotifier(),
);

/// Тумблер «Подсветка слов и фраз». Источник истины — SQLite KV
/// (`text_highlight_enabled`). Дефолт — true (как и на Rust-стороне).
class HighlightEnabledNotifier extends StateNotifier<bool> {
  HighlightEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await getTextHighlightEnabled();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        state = await getTextHighlightEnabled();
      } catch (_) {}
    }
  }

  Future<void> save(bool enabled) async {
    state = enabled;
    try {
      await setTextHighlightEnabled(enabled: enabled);
    } catch (_) {
      // Logging only — не показываем ошибку в UI
    }
  }
}

final highlightEnabledProvider =
    StateNotifierProvider<HighlightEnabledNotifier, bool>(
  (ref) => HighlightEnabledNotifier(),
);

/// Разобранные правила подсветки. Пустой список если тумблер выключен —
/// тогда `applyHighlight` не находит матчей, текст рендерится без подсветки.
final highlightRulesProvider = Provider<List<HighlightRule>>((ref) {
  final enabled = ref.watch(highlightEnabledProvider);
  if (!enabled) return const [];
  final dsl = ref.watch(highlightDslProvider);
  if (dsl.isEmpty) return const [];
  return parseHighlightDsl(dsl).rules;
});

/// Подписывается на Rust-стрим WebSocket событий и обновляет список новостей
/// + connectionStatusProvider. Стартует автоматически когда authProvider в ready.
class NewsStreamController extends StateNotifier<List<StoringNews>> {
  final Ref ref;
  StreamSubscription<NewsStreamEvent>? _sub;
  bool _historyLoaded = false;

  /// Дебаунс показа баннера «перехвачено». TokenInvalid при reconnect-е
  /// часто приходит кратковременно — если за 15 сек успеем подключиться
  /// и сервер нас примет primary, баннер вообще не показываем.
  Timer? _takeoverDebounce;

  void _cancelTakeoverDebounce() {
    _takeoverDebounce?.cancel();
    _takeoverDebounce = null;
  }

  /// Исходный список новостей (до применения фильтров настроек).
  /// `state` содержит уже отфильтрованный список — то что видит UI.
  List<StoringNews> _rawList = const [];

  NewsStreamController(this.ref) : super(const []) {
    // Стартуем / останавливаем стрим вслед за состоянием авторизации
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.stage == AuthStage.ready &&
          prev?.stage != AuthStage.ready) {
        _startFromStorage();
      } else if (next.stage != AuthStage.ready &&
          prev?.stage == AuthStage.ready) {
        _stop();
      }
    });
    if (ref.read(authProvider).stage == AuthStage.ready) {
      _startFromStorage();
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _historyLoaded = false;
    _rawList = const [];
    state = const [];
    _cancelTakeoverDebounce();
    ref.read(connectionStatusProvider.notifier).state =
        WsConnectionState.initial;
    ref.read(tickerFilterProvider.notifier).state = null;
    ref.read(sessionTakenOverProvider.notifier).state = null;
  }

  /// Принудительно пересоздать WS-подключение — для кнопки «Обновить сессию».
  /// Сервер увидит разрыв и новое подключение; если старый клиент уже отошёл,
  /// мы станем primary. Иначе снова прилетит SessionTakenOver.
  Future<void> forceReconnect() async {
    _sub?.cancel();
    _sub = null;
    _historyLoaded = false;
    _rawList = const [];
    state = const [];
    _cancelTakeoverDebounce();
    ref.read(sessionTakenOverProvider.notifier).state = null;
    ref.read(connectionStatusProvider.notifier).state =
        const WsConnectionState(status: ConnectionStatus.connecting);
    // 3 секунды — эмпирически достаточно чтобы сервер засчитал TCP-разрыв
    // предыдущего соединения и освободил слот токена.
    await Future.delayed(const Duration(seconds: 3));
    await _startFromStorage();
  }

  /// Повторно применить фильтры к уже полученным новостям.
  /// Вызывается из SettingsScreen когда пользователь меняет фильтры/источники.
  Future<void> refilter() => _applyFilters();

  Future<void> _applyFilters() async {
    final kept = <StoringNews>[];
    for (final n in _rawList) {
      final drop = await newsIsFiltered(news: n);
      if (!drop) kept.add(n);
    }
    state = kept;
    // Обновляем home screen widget — топ-3 видимых новостей.
    // No-op на платформах кроме Android.
    widgetService.updateNews(kept);
  }

  Future<void> _startFromStorage() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    _start(token);
  }

  void _start(String token) {
    _sub?.cancel();
    ref.read(connectionStatusProvider.notifier).state =
        const WsConnectionState(status: ConnectionStatus.connecting);
    _sub = startNewsStream(token: token).listen(
      _onEvent,
      onError: (e) {
        ref.read(connectionStatusProvider.notifier).state =
            WsConnectionState(status: ConnectionStatus.error, errorMessage: '$e');
      },
    );
  }

  void _onEvent(NewsStreamEvent event) {
    event.when(
      connecting: () {
        ref.read(connectionStatusProvider.notifier).state =
            const WsConnectionState(status: ConnectionStatus.connecting);
      },
      connected: () {
        ref.read(connectionStatusProvider.notifier).state =
            const WsConnectionState(status: ConnectionStatus.connected);
        // Соединение установлено — но ещё нет подтверждения что мы primary.
        // Финальное снятие баннера и отмена дебаунса — в newsReset/newsAdded
        // (когда сервер реально начал слать новости именно нам).
      },
      disconnected: () {
        ref.read(connectionStatusProvider.notifier).state =
            const WsConnectionState(status: ConnectionStatus.disconnected);
      },
      error: (msg) {
        ref.read(connectionStatusProvider.notifier).state =
            WsConnectionState(status: ConnectionStatus.error, errorMessage: msg);
      },
      newsReset: (list) async {
        // Храним сырое + применяем фильтры
        final sorted = [...list]..sort((a, b) {
            final at = a.timestamp ?? 0;
            final bt = b.timestamp ?? 0;
            return bt.compareTo(at);
          });
        _rawList = sorted;
        await _applyFilters();
        _historyLoaded = true;
        // Сервер дал полную историю → мы primary. Отменяем дебаунс и
        // снимаем баннер если он был виден.
        _cancelTakeoverDebounce();
        ref.read(sessionTakenOverProvider.notifier).state = null;
      },
      newsAdded: (n) async {
        // Пришла новая новость → мы primary. Отменяем дебаунс и снимаем
        // баннер если он был показан.
        _cancelTakeoverDebounce();
        if (ref.read(sessionTakenOverProvider) != null) {
          ref.read(sessionTakenOverProvider.notifier).state = null;
        }
        if (_rawList.any((x) => x.id == n.id)) return;
        _rawList = [n, ..._rawList];
        final drop = await newsIsFiltered(news: n);
        if (drop) return;
        if (state.any((x) => x.id == n.id)) return;

        // КРИТИЧНО: сначала помечаем ID как "recent", потом обновляем state.
        // Иначе на первом рендере карточки isRecent=false, и fade-out анимация
        // не запустится (виджет инициализируется как обычная карточка).
        if (_historyLoaded) {
          final recent = ref.read(recentNewsIdsProvider);
          ref.read(recentNewsIdsProvider.notifier).state = {...recent, n.id};
        }
        state = [n, ...state];
        // Обновляем home widget сразу — пользователь увидит свежий заголовок
        // на главном экране без открытия приложения.
        widgetService.updateNews(state);

        if (_historyLoaded) {
          // Звук — после рендера, не блокируем UI
          final alertSound = await matchingAlertSound(newsTags: n.tags);
          if (alertSound != null) {
            await soundService.playOnce(alertSound);
          } else {
            soundService.play();
          }
          // Системное push-уведомление (если включено пользователем).
          // showNews сам проверяет флаг `push_enabled` в SQLite.
          final body = (n.short != null && n.short!.trim().isNotEmpty)
              ? _stripHtmlShort(n.short!)
              : null;
          notificationService.showNews(
            title: _stripHtmlShort(n.title),
            body: body,
            tickers: n.tickers,
          );
          // Чистим из recent через 3.5 сек — анимация в виджете уже прошла
          Future.delayed(const Duration(milliseconds: 3500), () {
            try {
              final current = ref.read(recentNewsIdsProvider);
              if (current.contains(n.id)) {
                ref.read(recentNewsIdsProvider.notifier).state =
                    current.difference({n.id});
              }
            } catch (_) {
              // Провайдер уже уничтожен — игнорируем
            }
          });
        }
      },
      newsDeleted: (ids) {
        final set = ids.toSet();
        _rawList = _rawList.where((n) => !set.contains(n.id)).toList();
        state = state.where((n) => !set.contains(n.id)).toList();
        widgetService.updateNews(state);
      },
      newsUpdated: (n) {
        // Заменяем в raw и в видимом state одноимённую запись
        _rawList = _rawList.map((x) => x.id == n.id ? n : x).toList();
        state = state.map((x) => x.id == n.id ? n : x).toList();
        widgetService.updateNews(state);
      },
      sourceListUpdated: (groups) {
        // Rust автосохраняет в NewsSettings.source_list.
        // UI подхватывает через sourceGroupsProvider.
        ref.read(sourceGroupsProvider.notifier).state = groups;
      },
      sessionTakenOver: (text) {
        // Дебаунс 15 сек: если reconnect успеет пройти и придёт NewsReset —
        // баннер не показываем (отменяется в newsReset/newsAdded).
        // 15 сек выбрано эмпирически: сервер обычно освобождает слот
        // токена за 5-60 сек после отхода второго клиента (TCP timeout).
        if (ref.read(sessionTakenOverProvider) != null) return;
        if (_takeoverDebounce?.isActive ?? false) return;
        _takeoverDebounce = Timer(const Duration(seconds: 15), () {
          _takeoverDebounce = null;
          ref.read(sessionTakenOverProvider.notifier).state = text;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelTakeoverDebounce();
    super.dispose();
  }
}

final newsControllerProvider =
    StateNotifierProvider<NewsStreamController, List<StoringNews>>(
  NewsStreamController.new,
);

/// Тумблер звука уведомлений. Источник истины — [soundService.enabled],
/// провайдер — reactive-обёртка. При изменении нужно обновить и то, и другое.
final soundEnabledProvider =
    StateProvider<bool>((ref) => soundService.enabled);

/// Выбранная тема оформления. Источник — SQLite KV (`theme_mode`).
/// Значения в БД: "dark" / "light" / "system".
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = _parse(await getThemeMode());
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        state = _parse(await getThemeMode());
      } catch (_) {}
    }
  }

  Future<void> save(ThemeMode mode) async {
    state = mode;
    try {
      await setThemeMode(mode: _toStr(mode));
    } catch (_) {}
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static String _toStr(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

/// Включены ли push-уведомления (системные notifications о новых новостях).
/// Источник истины — SQLite KV (`push_enabled`). Дефолт — false.
class PushEnabledNotifier extends StateNotifier<bool> {
  PushEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await getPushEnabled();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        state = await getPushEnabled();
      } catch (_) {}
    }
  }

  Future<void> save(bool enabled) async {
    state = enabled;
    try {
      await setPushEnabled(enabled: enabled);
    } catch (_) {}
  }
}

final pushEnabledProvider =
    StateNotifierProvider<PushEnabledNotifier, bool>(
  (ref) => PushEnabledNotifier(),
);

/// Быстрый фильтр по тикеру (клик на чип).
final tickerFilterProvider = StateProvider<String?>((ref) => null);

/// Быстрый фильтр по хэштегу (клик на чип). Без '#'.
final hashtagFilterProvider = StateProvider<String?>((ref) => null);

/// Отфильтрованный список новостей — то что видит UI.
final newsListProvider = Provider<List<StoringNews>>((ref) {
  final all = ref.watch(newsControllerProvider);
  final tickerFilter = ref.watch(tickerFilterProvider);
  final hashtagFilter = ref.watch(hashtagFilterProvider);

  var result = all;
  if (tickerFilter != null) {
    final normalized = _normalize(tickerFilter);
    result = result
        .where((n) => n.tickers.any((t) => _normalize(t) == normalized))
        .toList();
  }
  if (hashtagFilter != null) {
    result = result.where((n) => n.tags.contains(hashtagFilter)).toList();
  }
  return result;
});

String _normalize(String ticker) {
  var t = ticker.trim().toUpperCase();
  if (t.startsWith('\$')) t = t.substring(1);
  return t;
}

/// Минимальная очистка HTML-тегов для плейн-текста в notification body.
String _stripHtmlShort(String s) {
  return s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
