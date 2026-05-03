import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../src/rust/api/simple.dart';

/// Обновляет Android home screen widget «Последние новости».
/// На других платформах — no-op.
class WidgetService {
  static const _androidName = 'NewsWidgetProvider';
  // 7 слотов — провайдер сам решает сколько показать в зависимости от
  // высоты виджета, выбранной пользователем при ресайзе.
  static const _slots = 7;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Записывает топ-3 новости в SharedPreferences и просит Android
  /// перерисовать виджет. Безопасно вызывать часто (на каждое newsAdded
  /// или newsReset) — операция дешёвая.
  Future<void> updateNews(List<StoringNews> news) async {
    if (!isSupported) return;
    final top = news.take(_slots).toList();
    try {
      for (var i = 0; i < _slots; i++) {
        if (i < top.length) {
          final n = top[i];
          await HomeWidget.saveWidgetData('news_${i}_id', n.id.toString());
          await HomeWidget.saveWidgetData(
            'news_${i}_ticker',
            n.tickers.isNotEmpty ? n.tickers.first : '',
          );
          await HomeWidget.saveWidgetData(
            'news_${i}_title',
            _stripHtml(n.title),
          );
          await HomeWidget.saveWidgetData(
            'news_${i}_time',
            n.timestamp != null ? _formatTime(n.timestamp!) : '',
          );
        } else {
          await HomeWidget.saveWidgetData('news_${i}_id', '');
          await HomeWidget.saveWidgetData('news_${i}_ticker', '');
          await HomeWidget.saveWidgetData('news_${i}_title', '');
          await HomeWidget.saveWidgetData('news_${i}_time', '');
        }
      }
      await HomeWidget.updateWidget(
        name: _androidName,
        androidName: _androidName,
      );
    } catch (e) {
      debugPrint('[widget] update failed: $e');
    }
  }

  static String _formatTime(int ts) {
    // timestamp у нас в формате «миллисекунды × 10» (как в расширении)
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
