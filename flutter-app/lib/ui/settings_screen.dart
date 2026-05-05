import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:swipeable_page_route/swipeable_page_route.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/rust/api/simple.dart';
import '../state/auth_provider.dart';
import '../state/background_service.dart';
import '../state/news_provider.dart';
import '../state/notification_service.dart';
import '../state/sound_service.dart';
import '../state/text_highlight.dart';
import '../state/updater_service.dart';
import 'widgets/compact_switch.dart';

/// Основной экран настроек с 4 табами (как в расширении).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  // Копим суммарный overscroll вправо на первом табе. По достижению
  // порога — pop страницы (возврат к ленте).
  double _overscrollBudget = 0;
  static const _overscrollPopThreshold = 60.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // SwipeablePageRoute внутри Settings не используем — arena-конфликт с
    // TabBarView даёт срабатывание "через раз". Вместо этого ловим overscroll.
    final route = ModalRoute.of(context);
    if (route is SwipeablePageRoute) {
      route.canSwipe = false;
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    // Игнорируем вертикальные скроллы внутри вкладки (ListView в «Источниках»).
    if (n.metrics.axis != Axis.horizontal) return false;
    if (_tabs.index != 0) {
      _overscrollBudget = 0;
      return false;
    }
    if (n is OverscrollNotification && n.overscroll < 0) {
      // overscroll < 0 = потянуть ещё правее когда уже на первой странице
      _overscrollBudget += n.overscroll.abs();
      if (_overscrollBudget >= _overscrollPopThreshold) {
        _overscrollBudget = 0;
        Navigator.of(context).maybePop();
        return true;
      }
    } else if (n is ScrollEndNotification) {
      _overscrollBudget = 0;
    }
    return false;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    // В ленте `bodyMedium` = muted (короткий текст). В настройках же хочется
    // чтобы подписи полей были такими же контрастными как заголовок новости.
    // Локально переопределяем дефолтный цвет текста на `onSurface`.
    final settingsTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        bodyColor: baseTheme.colorScheme.onSurface,
        displayColor: baseTheme.colorScheme.onSurface,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Настройки',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Источники'),
            Tab(text: 'Фильтры'),
            Tab(text: 'Уведомления'),
            Tab(text: 'Прочее'),
          ],
        ),
      ),
      body: Theme(
        data: settingsTheme,
        // ScrollConfiguration включает drag мышью/тачпадом/стилусом
        // (по умолчанию во Flutter на desktop это отключено).
        // NotificationListener на overscroll: на первом табе попытка
        // потянуть ленту ещё правее — возвращает на экран новостей.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: TabBarView(
              controller: _tabs,
              // ClampingScrollPhysics важна: она блокирует pixels на границе
              // И эмитит OverscrollNotification (в отличие от Bouncing, которая
              // просто даёт уйти за край без notification).
              physics: const ClampingScrollPhysics(),
              children: const [
                _SourcesTab(),
                _FiltersTab(),
                _NotificationsTab(),
                _AboutTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Источники
// ══════════════════════════════════════════════════════════════════════════

final _sourceOverridesProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  final list = await getSourceSettings();
  return {for (final s in list) s.$1: s.$2};
});

class _SourcesTab extends ConsumerWidget {
  const _SourcesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(sourceGroupsProvider);
    final overridesAsync = ref.watch(_sourceOverridesProvider);

    if (groups.isEmpty) {
      return const Center(
        child: Text(
          'Источники придут после подключения',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    return overridesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (overrides) {
        // Поднимаем «Базовые» (group_name == null) наверх
        final sortedGroups = [...groups]..sort((a, b) {
            final aBasic = a.groupName == null;
            final bBasic = b.groupName == null;
            if (aBasic && !bBasic) return -1;
            if (!aBasic && bBasic) return 1;
            return 0;
          });
        return ListView(
          children: [
            for (final g in sortedGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  g.groupName ?? 'Базовые',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              for (final src in g.sources)
                _SourceRow(
                  source: src,
                  enabled: overrides[src.sourceName] ?? src.defaultEnabled,
                  onChanged: (v) async {
                    await setSourceEnabled(
                      sourceName: src.sourceName,
                      enabled: v,
                    );
                    ref.invalidate(_sourceOverridesProvider);
                    // Пересчитываем ленту под новые настройки
                    await ref.read(newsControllerProvider.notifier).refilter();
                  },
                ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _SourceRow extends StatelessWidget {
  final SourceItem source;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SourceRow({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                source.sourceName,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            CompactSwitch(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Фильтры
// ══════════════════════════════════════════════════════════════════════════

class _FiltersTab extends StatelessWidget {
  const _FiltersTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        _HighlightSection(),
        SizedBox(height: 16),
        _FilterSection(
          title: 'Чёрный список тикеров',
          placeholder: '\$AFKS, \$GAZP, \$SBER',
          type: 'tickers_black',
          separator: ',',
        ),
        _FilterSection(
          title: 'Белый список тикеров',
          placeholder: '\$AFKS, \$GAZP, \$SBER',
          type: 'tickers_white',
          separator: ',',
        ),
        _FilterSection(
          title: 'Чёрный список хэштегов',
          placeholder: '#дивиденды, #buyback',
          type: 'hashtags_black',
          separator: ',',
        ),
        _FilterSection(
          title: 'Белый список хэштегов',
          placeholder: '#дивиденды, #buyback',
          type: 'hashtags_white',
          separator: ',',
        ),
        _FilterSection(
          title: 'Чёрный список фраз',
          placeholder: 'фраза на каждой строке',
          type: 'phrases_black',
          separator: '\n',
        ),
        _FilterSection(
          title: 'Белый список фраз',
          placeholder: 'фраза на каждой строке',
          type: 'phrases_white',
          separator: '\n',
        ),
      ],
    );
  }
}

/// Редактор DSL подсветки текста. Использует highlightDslProvider.
class _HighlightSection extends ConsumerStatefulWidget {
  const _HighlightSection();

  @override
  ConsumerState<_HighlightSection> createState() => _HighlightSectionState();
}

class _HighlightSectionState extends ConsumerState<_HighlightSection> {
  final TextEditingController _ctrl = TextEditingController();
  List<String> _errors = const [];
  bool _loadedFromProvider = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final parsed = parseHighlightDsl(_ctrl.text);
    setState(() => _errors = parsed.errors);
    await ref.read(highlightDslProvider.notifier).save(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    // Один раз подхватываем сохранённый DSL из провайдера
    final savedDsl = ref.watch(highlightDslProvider);
    if (!_loadedFromProvider && savedDsl.isNotEmpty) {
      _ctrl.text = savedDsl;
      _loadedFromProvider = true;
    }
    final enabled = ref.watch(highlightEnabledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Подсветка слов и фраз',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            IconButton(
              icon: const Icon(Icons.help_outline, size: 18),
              onPressed: () => _showHelp(context),
              tooltip: 'Подсказка по формату',
            ),
            CompactSwitch(
              value: enabled,
              onChanged: (v) =>
                  ref.read(highlightEnabledProvider.notifier).save(v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ctrl,
                  maxLines: 5,
                  style:
                      const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText:
                        'прибыль@green\nвыручка@#ff9800\n{\nобыск\nарест\n}@red',
                    hintStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.35),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_errors.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final e in _errors)
                    Text('• $e',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Применить',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Формат подсветки'),
        content: const SingleChildScrollView(
          child: Text(
            'Простой пример:\n'
            '  прибыль@green\n'
            '  выручка@#ff9800\n\n'
            'Стили (CSS-подобно):\n'
            '  победа@color: #79f51b; background-color: #356675ad\n\n'
            'Группа фраз с общим стилем:\n'
            '  {\n'
            '  обыск\n'
            '  арест\n'
            '  }@red\n\n'
            'Регулярные выражения работают прямо как фразы.\n'
            'Фразы регистро-независимы.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends ConsumerStatefulWidget {
  final String title;
  final String placeholder;
  final String type;
  final String separator;
  const _FilterSection({
    required this.title,
    required this.placeholder,
    required this.type,
    required this.separator,
  });

  @override
  ConsumerState<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends ConsumerState<_FilterSection> {
  final TextEditingController _controller = TextEditingController();
  bool _enabled = false;
  bool _loaded = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await getFilter(filterType: widget.type);
    if (!mounted) return;
    setState(() {
      _enabled = result.$1;
      _controller.text = result.$2.join(
        widget.separator == '\n' ? '\n' : ', ',
      );
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final values = _controller.text
        .split(widget.separator == ',' ? RegExp(r'[,\s]+') : RegExp(r'\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await setFilter(
      filterType: widget.type,
      enabled: _enabled,
      values: values,
    );
    // Обновить ленту с новыми фильтрами
    await ref.read(newsControllerProvider.notifier).refilter();
    if (!mounted) return;
    setState(() => _saved = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              CompactSwitch(
                value: _enabled,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  _save();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            maxLines: widget.separator == '\n' ? 4 : 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                fontSize: 13,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
              contentPadding: const EdgeInsets.all(10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF4C9EFF),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _save,
              icon: Icon(
                _saved ? Icons.check : Icons.save_outlined,
                size: 16,
              ),
              label: Text(_saved ? 'Сохранено' : 'Сохранить',
                  style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                foregroundColor: _saved
                    ? const Color(0xFF2EA44F)
                    : Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                  color: _saved
                      ? const Color(0xFF2EA44F)
                      : Theme.of(context)
                          .colorScheme
                          .outline
                          .withOpacity(0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Уведомления (звук)
// ══════════════════════════════════════════════════════════════════════════

class _NotificationsTab extends ConsumerStatefulWidget {
  const _NotificationsTab();

  @override
  ConsumerState<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<_NotificationsTab> {
  late String _sound = soundService.currentSound;
  late double _volume = soundService.volume;

  bool _bgEnabled = false;
  bool _bgLoaded = false;

  @override
  void initState() {
    super.initState();
    backgroundService.isEnabledByUser().then((v) {
      if (!mounted) return;
      setState(() {
        _bgEnabled = v;
        _bgLoaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(_alertsProvider);
    // Единый источник истины для on/off — тот же провайдер, что и у
    // кнопки mute в нижней панели.
    final soundEnabled = ref.watch(soundEnabledProvider);
    void toggleSound(bool v) {
      ref.read(soundEnabledProvider.notifier).state = v;
      soundService.enabled = v;
    }

    final pushEnabled = ref.watch(pushEnabledProvider);
    Future<void> togglePush(bool v) async {
      if (v) {
        // Спрашиваем разрешение на показ уведомлений.
        // На Android 13+ покажет runtime-диалог permission_handler.
        // На iOS — нативный системный диалог через DarwinPlugin.
        // Если пользователь ранее отказал — диалог НЕ показывается
        // повторно (iOS политика), нужно вести его в Settings вручную.
        final granted = await notificationService.requestPermission();
        if (!granted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Разрешение на уведомления не выдано. '
                'Включите его в настройках системы.',
              ),
              action: SnackBarAction(
                label: 'Открыть',
                onPressed: () => openAppSettings(),
              ),
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        }
      }
      await ref.read(pushEnabledProvider.notifier).save(v);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        InkWell(
          onTap: () => togglePush(!pushEnabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Push-уведомления'),
                      SizedBox(height: 2),
                      Text(
                        'Системные нотификации о новых новостях',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                CompactSwitch(
                  value: pushEnabled,
                  onChanged: togglePush,
                ),
              ],
            ),
          ),
        ),
        if (backgroundService.isSupported && _bgLoaded) ...[
          const Divider(height: 20),
          InkWell(
            onTap: () async {
              final v = !_bgEnabled;
              setState(() => _bgEnabled = v);
              await backgroundService.setEnabled(v);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Получать новости в фоне'),
                        SizedBox(height: 2),
                        Text(
                          'Не давать Android выгружать приложение когда экран '
                          'заблокирован — иначе пуши перестают приходить',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  CompactSwitch(
                    value: _bgEnabled,
                    onChanged: (v) async {
                      setState(() => _bgEnabled = v);
                      await backgroundService.setEnabled(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 20),
        InkWell(
          onTap: () => toggleSound(!soundEnabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                const Expanded(child: Text('Звук уведомлений')),
                CompactSwitch(
                  value: soundEnabled,
                  onChanged: toggleSound,
                ),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: soundEnabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !soundEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.volume_down, size: 18),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        onChanged: (v) async {
                          setState(() => _volume = v);
                          await soundService.setVolume(v);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up, size: 18),
                  ],
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Звук', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kAvailableSounds.map((name) {
                    final selected = name == _sound;
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) async {
                        setState(() => _sound = name);
                        await soundService.setSoundName(name);
                        await soundService.play();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Тест звука'),
                  onPressed: () => soundService.play(),
                ),
              ],
            ),
          ),
        ),
        // ──────────────────────────────────────────────────────────────
        // Алерты по хэштегам (специальные звуки для определённых тэгов)
        // ──────────────────────────────────────────────────────────────
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Алерты по хэштегам',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Каждое правило: хэштеги → звук. Срабатывает если новость содержит ВСЕ указанные хэштеги.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 10),
        alertsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text('Ошибка: $e'),
          data: (alerts) => Column(
            children: [
              if (alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Алерты не настроены.\nДобавьте правило кнопкой ниже.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              for (int i = 0; i < alerts.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _AlertRow(
                    index: i,
                    hashtags: alerts[i].$1,
                    sound: alerts[i].$2,
                    onChanged: (updated) async {
                      final newAlerts = [...alerts]..[i] = updated;
                      await setHashtagAlerts(alerts: newAlerts);
                      ref.invalidate(_alertsProvider);
                    },
                    onDelete: () async {
                      final newAlerts = [...alerts]..removeAt(i);
                      await setHashtagAlerts(alerts: newAlerts);
                      ref.invalidate(_alertsProvider);
                    },
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить правило'),
                  onPressed: () async {
                    final newAlerts = [
                      ...alerts,
                      (<String>[], kAvailableSounds.first),
                    ];
                    await setHashtagAlerts(alerts: newAlerts);
                    ref.invalidate(_alertsProvider);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Хэштег-алерты (встроены во вкладку «Уведомления»)
// ══════════════════════════════════════════════════════════════════════════

final _alertsProvider =
    FutureProvider<List<(List<String>, String)>>((ref) => getHashtagAlerts());

class _AlertRow extends StatefulWidget {
  final int index;
  final List<String> hashtags;
  final String sound;
  final ValueChanged<(List<String>, String)> onChanged;
  final VoidCallback onDelete;
  const _AlertRow({
    required this.index,
    required this.hashtags,
    required this.sound,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_AlertRow> createState() => _AlertRowState();
}

class _AlertRowState extends State<_AlertRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.hashtags.join(', '));
  late String _sound = widget.sound;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'дивиденды, buyback',
                labelText: 'Хэштеги (через запятую)',
                isDense: true,
              ),
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Звук: ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: DropdownButton<String>(
                    value: _sound,
                    isExpanded: true,
                    items: kAvailableSounds
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sound = v);
                      _apply();
                      soundService.playOnce(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.save, size: 18),
                  tooltip: 'Сохранить хэштеги',
                  onPressed: _apply,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Удалить',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _apply() {
    final tags = _ctrl.text
        .split(RegExp(r'[,\s#]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    widget.onChanged((tags, _sound));
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Прочее (смена токена, ссылки)
// ══════════════════════════════════════════════════════════════════════════

class _AboutTab extends ConsumerWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.logout, size: 20),
          title: const Text('Сменить токен'),
          subtitle: const Text(
            'Выйти и ввести другой токен',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () async {
            Navigator.of(context).pop();
            await ref.read(authProvider.notifier).resetToken();
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language, size: 20),
          title: const Text('Сайт stocksi-ultimate.ru'),
          subtitle: const Text(
            'Открыть в браузере',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () async {
            await launchUrl(
              Uri.parse('https://stocksi-ultimate.ru'),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.telegram, size: 20),
          title: const Text('Подписка в Telegram'),
          subtitle: const Text(
            't.me/StocksiUltimate_bot',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () async {
            await launchUrl(
              Uri.parse('https://t.me/StocksiUltimate_bot?start=r61558uapp'),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        if (updaterService.isSupported) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update, size: 20),
            title: const Text('Проверить обновления'),
            subtitle: const Text(
              'Проверить наличие новой версии сейчас',
              style: TextStyle(fontSize: 12),
            ),
            onTap: () async {
              await updaterService.checkNow();
            },
          ),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.refresh, size: 20),
          title: const Text('Обновить сессию'),
          subtitle: const Text(
            'Сделать эту сессию главной (другая будет отключена)',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () async {
            await ref.read(newsControllerProvider.notifier).forceReconnect();
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.power_settings_new,
              size: 20, color: Theme.of(context).colorScheme.error),
          title: Text(
            'Завершить работу',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text(
            'Полностью выйти и остановить WS-подключение',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () async {
            try {
              await SystemNavigator.pop();
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 200));
            exit(0);
          },
        ),
      ],
    );
  }
}
