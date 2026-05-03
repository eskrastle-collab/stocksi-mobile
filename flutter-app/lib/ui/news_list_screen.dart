import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:swipeable_page_route/swipeable_page_route.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/rust/api/simple.dart';
import '../state/auth_provider.dart';
import '../state/news_provider.dart';
import '../state/sound_service.dart';
import '../state/text_highlight.dart';
import '../util/share_signature.dart';
import 'news_detail_screen.dart';
import 'settings_screen.dart';

class NewsListScreen extends ConsumerStatefulWidget {
  const NewsListScreen({super.key});

  @override
  ConsumerState<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends ConsumerState<NewsListScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _scrollCtrl.offset > 120;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    // forceReconnect рвёт WS, ждёт 3 сек чтобы сервер увидел разрыв,
    // потом подключается заново. По возвращении приходит NewsHistory →
    // лента обновится. Pull-индикатор сбрасывается когда future завершён.
    await ref.read(newsControllerProvider.notifier).forceReconnect();
  }

  void _scrollToTop() {
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(newsListProvider);
    final connection = ref.watch(connectionStatusProvider);

    final tickerFilter = ref.watch(tickerFilterProvider);
    final hashtagFilter = ref.watch(hashtagFilterProvider);
    final takeoverText = ref.watch(sessionTakenOverProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (takeoverText != null)
              _SessionTakenOverBanner(
                text: takeoverText,
                onRefresh: () =>
                    ref.read(newsControllerProvider.notifier).forceReconnect(),
              ),
            if (tickerFilter != null)
              _FilterBanner(
                label: tickerFilter,
                icon: Icons.sell_outlined,
                onClose: () =>
                    ref.read(tickerFilterProvider.notifier).state = null,
              ),
            if (hashtagFilter != null)
              _FilterBanner(
                label: '#$hashtagFilter',
                icon: Icons.tag_outlined,
                color: _tagColor(hashtagFilter),
                onClose: () =>
                    ref.read(hashtagFilterProvider.notifier).state = null,
              ),
            Expanded(
              child: Stack(
                children: [
                  items.isEmpty
                      ? _EmptyState(connection: connection)
                      : RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: const Color(0xFF4C9EFF),
                          child: SlidableAutoCloseBehavior(
                            child: ListView.separated(
                              controller: _scrollCtrl,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 12),
                              itemBuilder: (context, i) => _SwipeableNewsCard(
                                key: ValueKey(items[i].id),
                                news: items[i],
                              ),
                            ),
                          ),
                        ),
                  // Плавающая кнопка «Наверх»
                  Positioned(
                    top: 8,
                    right: 10,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _showScrollTop ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_showScrollTop,
                        child: _ScrollTopButton(onPressed: _scrollToTop),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(status: connection.status),
    );
  }
}

/// Баннер поверх ленты когда сервер прислал TokenResultInvalid(TooManyConnections).
/// Показывает полный текст сообщения + кнопку «Обновить сессию».
class _SessionTakenOverBanner extends StatelessWidget {
  final String text;
  final VoidCallback onRefresh;
  const _SessionTakenOverBanner({required this.text, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const warnColor = Color(0xFFFFC773);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: warnColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warnColor.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: warnColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Обновить сессию'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBanner extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback onClose;
  const _FilterBanner({
    required this.label,
    required this.icon,
    required this.onClose,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF679CF6);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Text(
            'Фильтр: ',
            style: TextStyle(fontSize: 13, color: c),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollTopButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ScrollTopButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.keyboard_arrow_up, size: 20),
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  final ConnectionStatus status;
  const _BottomBar({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 14),
          const Text(
            'STOCKSI ULTIMATE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.2,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          _ConnectionDot(status: status),
          // Кнопка-дубликат «Обновить сессию» рядом со статусом — для быстрого
          // ручного reconnect без захода в настройки.
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            tooltip: 'Обновить сессию',
            onPressed: () =>
                ref.read(newsControllerProvider.notifier).forceReconnect(),
          ),
          const Spacer(),
          // Быстрый переключатель темы (тёмная ↔ светлая).
          Builder(builder: (_) {
            final mode = ref.watch(themeModeProvider);
            final isDark = mode == ThemeMode.dark ||
                (mode == ThemeMode.system &&
                    MediaQuery.platformBrightnessOf(context) ==
                        Brightness.dark);
            return IconButton(
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 18,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              tooltip: isDark ? 'Светлая тема' : 'Тёмная тема',
              onPressed: () {
                ref.read(themeModeProvider.notifier).save(
                      isDark ? ThemeMode.light : ThemeMode.dark,
                    );
              },
            );
          }),
          // Быстрый mute/unmute. Обновляет и провайдер, и soundService,
          // чтобы тумблер в настройках подхватил новое значение.
          Builder(builder: (_) {
            final enabled = ref.watch(soundEnabledProvider);
            return IconButton(
              icon: Icon(
                enabled ? Icons.volume_up : Icons.volume_off,
                size: 18,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              tooltip: enabled ? 'Выключить звук' : 'Включить звук',
              onPressed: () {
                final v = !enabled;
                ref.read(soundEnabledProvider.notifier).state = v;
                soundService.enabled = v;
              },
            );
          }),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            tooltip: 'Настройки',
            onPressed: () => _openSettings(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      SwipeablePageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}

/// [Удалено — настройки теперь в полноэкранном SettingsScreen]
class _SettingsSheet_Legacy extends StatelessWidget {
  const _SettingsSheet_Legacy();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ConnectionDot extends StatefulWidget {
  final ConnectionStatus status;
  const _ConnectionDot({required this.status});

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.status) {
      ConnectionStatus.connected => const Color(0xFF2EA44F),
      ConnectionStatus.connecting => const Color(0xFFFFC773),
      ConnectionStatus.disconnected => const Color(0xFF8CA7BE),
      ConnectionStatus.error => const Color(0xFFE85454),
      ConnectionStatus.idle => const Color(0xFF8CA7BE),
    };
    final shouldPulse = widget.status == ConnectionStatus.connecting;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final double extra = shouldPulse ? _pulse.value * 4.0 : 0.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 4.0 + extra,
                spreadRadius: 1.0 + extra / 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final WsConnectionState connection;
  const _EmptyState({required this.connection});

  @override
  Widget build(BuildContext context) {
    final text = switch (connection.status) {
      ConnectionStatus.connecting => 'Подключение к серверу...',
      ConnectionStatus.connected => 'Ожидаем новости...',
      ConnectionStatus.disconnected => 'Соединение потеряно',
      ConnectionStatus.error =>
        connection.errorMessage ?? 'Ошибка подключения',
      ConnectionStatus.idle => 'Загрузка...',
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (connection.status == ConnectionStatus.connecting)
            const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
        ],
      ),
    );
  }
}

/// Карточка с возможностью свайпа влево для быстрых действий.
class _SwipeableNewsCard extends StatelessWidget {
  final StoringNews news;
  const _SwipeableNewsCard({super.key, required this.news});

  String _buildShareText() {
    final parts = <String>[];
    if (news.tickers.isNotEmpty) {
      parts.add(news.tickers.join(' '));
    }
    parts.add(news.title);
    if (news.short != null && news.short!.trim().isNotEmpty) {
      parts.add(news.short!);
    }
    if (news.fullTextLink != null && news.fullTextLink!.isNotEmpty) {
      parts.add(news.fullTextLink!);
    }
    parts.add(kShareSignature);
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = news.fullTextLink != null && news.fullTextLink!.isNotEmpty;
    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: hasLink ? 0.48 : 0.32,
        children: [
          _StocksiAction(
            icon: Icons.copy_outlined,
            label: 'Копия',
            color: const Color(0xFF4C9EFF),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _buildShareText()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Скопировано'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          _StocksiAction(
            icon: Icons.share_outlined,
            label: 'Поделиться',
            color: const Color(0xFF7A5CFA),
            onTap: () => Share.share(_buildShareText()),
          ),
          if (hasLink)
            _StocksiAction(
              icon: Icons.open_in_new,
              label: 'Открыть',
              color: const Color(0xFF2EA44F),
              onTap: () async {
                final uri = Uri.tryParse(news.fullTextLink!);
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
      child: NewsCard(news: news),
    );
  }
}

/// Стилизованный swipe-action: маленькая тёмная кнопка с цветной иконкой.
class _StocksiAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StocksiAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Material(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              Slidable.of(context)?.close();
              onTap();
            },
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NewsCard extends ConsumerWidget {
  final StoringNews news;
  const NewsCard({super.key, required this.news});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightRules = ref.watch(highlightRulesProvider);
    // Чистим short заранее — чтобы не рендерить пустой Text + SizedBox
    final cleanedShort = (news.short != null && news.short!.isNotEmpty)
        ? _cleanHtml(news.short!)
        : '';
    final hasShort = cleanedShort.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (news.tickers.isNotEmpty || news.tags.isNotEmpty) ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...news.tickers.map((t) => _TickerChip(ticker: t)),
              ...news.tags.map((t) => _HashtagChip(tag: t)),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Text.rich(
          TextSpan(
            children: applyHighlight(
              _cleanHtml(news.title),
              highlightRules,
              baseStyle: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        if (hasShort) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: applyHighlight(
                cleanedShort,
                highlightRules,
                baseStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
        if (news.files.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: news.files.map((url) => _FileChip(url: url)).toList(),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (news.source != null)
              Text(
                news.source!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.55),
                    ),
              ),
            if (news.timestamp != null)
              Text(
                _formatTime(news.timestamp!),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.55),
                    ),
              ),
          ],
        ),
      ],
    );

    // Fade-out подсветка новых новостей. _FadeHighlight сам проверяет
    // recentNewsIdsProvider в initState и запускает анимацию ровно один раз.
    // Не слушает провайдер в build — чтобы rebuild не сбрасывал анимацию.
    final highlightedContent = _FadeHighlight(
      newsId: news.id,
      child: content,
    );

    // Tap → детальный просмотр, только если есть ссылка на полный текст
    final canExpand = news.fullTextLink != null && news.fullTextLink!.isNotEmpty;
    if (!canExpand) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: highlightedContent,
      );
    }
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          // SwipeablePageRoute: свайп назад работает с любой точки страницы,
          // не только с 20px-зоны у края (как в стандартном CupertinoPageRoute).
          SwipeablePageRoute(builder: (_) => NewsDetailScreen(news: news)),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: highlightedContent,
      ),
    );
  }

  static String _formatTime(int ts) {
    // timestamp в формате extension: миллисекунды × 10
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 10);
    return DateFormat('HH:mm').format(dt);
  }

  /// Минималистичный парсер HTML-тегов в тексте новости:
  /// `<br>` → перенос строки, всё остальное — вырезаем.
  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;
  const _Chip({required this.text, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      );
}

/// Чип хэштега — цветной, кликабельный (фильтрует ленту).
class _HashtagChip extends ConsumerWidget {
  final String tag;
  const _HashtagChip({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _tagColor(tag);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        ref.read(hashtagFilterProvider.notifier).state = tag;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '#$tag',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

Color _tagColor(String tag) {
  switch (tag) {
    case 'дивиденды':
      return const Color(0xFF8BFFB2);
    case 'buyback':
      return const Color(0xFF9E3EFF);
    case 'отчётность':
      return const Color(0xFFFFC773);
    case 'санкции':
      return const Color(0xFFFF4C00);
    case 'редомициляция':
      return const Color(0xFF58A4FB);
    default:
      return Colors.grey.shade700;
  }
}

/// Чип файла — PDF / xls / doc / html, прикреплённый к новости.
/// Клик открывает в системном браузере (на мобиле — нативный просмотрщик PDF).
class _FileChip extends StatelessWidget {
  final String url;
  const _FileChip({required this.url});

  String get _filename {
    final path = url.split('?').first;
    final raw = path.split('/').last;
    if (raw.isEmpty) return url;
    // Percent-decoding может падать на битых URL → fallback на raw
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  IconData get _icon {
    final lower = url.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return Icons.table_chart_outlined;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return Icons.html_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurface.withOpacity(0.85);
    return Material(
      color: scheme.onSurface.withOpacity(0.07),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: scheme.outline.withOpacity(0.5),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 14, color: color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  _filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade-out подсветка новой новости: фиолетовая заливка → прозрачность
/// за 3.5 сек. Проверяет `recentNewsIdsProvider` один раз в initState —
/// это гарантирует что анимация запускается именно при первом появлении
/// карточки, а rebuild списка (например, из-за прилёта новой новости
/// следом) не сбрасывает прогресс.
class _FadeHighlight extends ConsumerStatefulWidget {
  final int newsId;
  final Widget child;
  const _FadeHighlight({required this.newsId, required this.child});

  @override
  ConsumerState<_FadeHighlight> createState() => _FadeHighlightState();
}

class _FadeHighlightState extends ConsumerState<_FadeHighlight>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    // Читаем recent один раз — если ID там, запускаем затухание.
    // Для "старых" новостей (пришедших из history) _ctrl остаётся null,
    // карточка рендерится без декорации.
    final recent = ref.read(recentNewsIdsProvider);
    if (recent.contains(widget.newsId)) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3500),
        value: 1.0, // полная подсветка на старте
      );
      _ctrl!.reverse(); // → 0.0 за 3.5с с дефолтной кривой
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, child) {
        final t = Curves.easeOut.transform(ctrl.value);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF8069FF).withOpacity(0.55 * t),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(4),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Чип тикера с логотипом компании (если известен) из Tinkoff Invest.
/// Клик — включает фильтр ленты по этому тикеру.
class _TickerChip extends ConsumerWidget {
  final String ticker;
  const _TickerChip({required this.ticker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = tickerIconUrl(ticker: ticker);
    const chipColor = Color(0xFF679CF6);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        ref.read(tickerFilterProvider.notifier).state = ticker;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: chipColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (url != null) ...[
              ClipOval(
                child: Image.network(
                  url,
                  width: 16,
                  height: 16,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              ticker,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: chipColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
