import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/rust/api/simple.dart';
import '../util/share_signature.dart';

/// Экран с полным текстом новости. Загружает HTML по `news.fullTextLink`.
class NewsDetailScreen extends StatefulWidget {
  final StoringNews news;
  const NewsDetailScreen({super.key, required this.news});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Future<String>? _loadingFuture;

  @override
  void initState() {
    super.initState();
    final url = widget.news.fullTextLink;
    if (url != null && url.isNotEmpty) {
      _loadingFuture = _fetchFullText(url);
    }
  }

  String _buildShareText() {
    final n = widget.news;
    final parts = <String>[];
    if (n.tickers.isNotEmpty) parts.add(n.tickers.join(' '));
    parts.add(n.title);
    if (n.short != null && n.short!.trim().isNotEmpty) parts.add(n.short!);
    if (n.fullTextLink != null && n.fullTextLink!.isNotEmpty) {
      parts.add(n.fullTextLink!);
    }
    parts.add(kShareSignature);
    return parts.join('\n\n');
  }

  Future<String> _fetchFullText(String url) async {
    // Браузерные заголовки чтобы сайты-источники не блочили нас как бота
    final resp = await http.get(
      Uri.parse(url),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ru,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    // Сервер обычно отдаёт UTF-8, но на всякий случай пробуем bodyBytes
    try {
      return utf8.decode(resp.bodyBytes);
    } catch (_) {
      return resp.body;
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.news;
    final ts = n.timestamp;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          n.source ?? 'Новость',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Скопировать',
            onPressed: () async {
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
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            tooltip: 'Поделиться',
            onPressed: () => Share.share(_buildShareText()),
          ),
          if (n.fullTextLink != null && n.fullTextLink!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              tooltip: 'Открыть в браузере',
              onPressed: () async {
                final uri = Uri.tryParse(n.fullTextLink!);
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.tickers.isNotEmpty || n.tags.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...n.tickers.map(
                      (t) => _MiniChip(text: t, color: const Color(0xFF679CF6)),
                    ),
                    ...n.tags.map(
                      (t) =>
                          _MiniChip(text: '#$t', color: _tagColor(t)),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                _cleanHtml(n.title),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
              ),
              if (n.short != null) ...[
                const SizedBox(height: 8),
                Text(
                  _cleanHtml(n.short!),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 8),
              if (ts != null)
                Text(
                  DateFormat('d MMMM, HH:mm', 'ru_RU').format(
                    DateTime.fromMillisecondsSinceEpoch(ts * 10),
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                ),
              const Divider(height: 32),
              _FullTextBody(
                future: _loadingFuture,
                sourceUrl: widget.news.fullTextLink,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static Color _tagColor(String tag) {
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
}

class _FullTextBody extends StatelessWidget {
  final Future<String>? future;
  final String? sourceUrl;
  const _FullTextBody({required this.future, this.sourceUrl});

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const Text(
        'Для этой новости нет дополнительного текста',
        style: TextStyle(fontStyle: FontStyle.italic),
      );
    }
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Не удалось загрузить полный текст',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${snap.error}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.error.withOpacity(0.8),
                ),
              ),
              if (sourceUrl != null && sourceUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(sourceUrl!);
                    if (uri == null) return;
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Открыть в браузере'),
                ),
              ],
            ],
          );
        }
        final html = snap.data ?? '';
        if (html.trim().isEmpty) {
          return const Text(
            'Пусто',
            style: TextStyle(fontStyle: FontStyle.italic),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return Html(
          data: html,
          style: {
            // Как в расширении: --pro-text-02 (muted), 13px базовый размер,
            // line-height ~1.5 для читаемости длинных текстов.
            'body': Style(
              fontSize: FontSize(13),
              lineHeight: LineHeight.number(1.5),
              color: scheme.onSurfaceVariant,
              margin: Margins.zero,
            ),
            'p': Style(margin: Margins.only(bottom: 8)),
            'a': Style(
              color: scheme.primary,
              textDecoration: TextDecoration.underline,
            ),
          },
        );
      },
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniChip({required this.text, required this.color});

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
            color: color,
          ),
        ),
      );
}
