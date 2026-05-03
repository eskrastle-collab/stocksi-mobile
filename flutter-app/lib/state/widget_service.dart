import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../src/rust/api/simple.dart';

/// Обновляет Android home screen widget «Последние новости».
/// На других платформах — no-op.
class WidgetService {
  static const _androidName = 'NewsWidgetProvider';
  static const _qualifiedAndroidName = 'ru.stocksi.ultimate.NewsWidgetProvider';
  static const _slots = 7;

  Timer? _debounce;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Записывает топ-7 новостей в одну JSON-строку и обновляет виджет.
  /// Debounce 500мс — если новости летят пачкой, шлём один update в конце.
  void updateNews(List<StoringNews> news) {
    if (!isSupported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _flush(news));
  }

  Future<void> _flush(List<StoringNews> news) async {
    try {
      final top = news.take(_slots).map((n) => {
            'id': n.id.toString(),
            'ticker': n.tickers.isNotEmpty ? n.tickers.first : '',
            'title': _stripHtml(n.title),
            'time': n.timestamp != null ? _formatTime(n.timestamp!) : '',
          }).toList();
      // Сохраняем одной JSON-строкой — провайдер парсит. Это убирает
      // 28 отдельных prefs-операций и race-condition с broadcast'ом.
      await HomeWidget.saveWidgetData('news_json', jsonEncode(top));
      final res = await HomeWidget.updateWidget(
        name: _androidName,
        androidName: _androidName,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
      debugPrint('[widget] update -> $res, news=${top.length}');
    } catch (e) {
      debugPrint('[widget] update failed: $e');
    }
  }

  static String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 10);
    return DateFormat('HH:mm').format(dt);
  }

  static String _stripHtml(String s) {
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
}

final widgetService = WidgetService();
