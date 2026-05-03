package ru.stocksi.ultimate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * AppWidgetProvider для виджета «Последние новости Stocksi» 4×2.
 *
 * Получает данные из SharedPreferences (записанные Flutter-стороной через
 * пакет `home_widget`). Tap по новости запускает приложение с deep link
 * `stocksi://news/<id>`. Tap по кнопке refresh — `stocksi://refresh`.
 */
class NewsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.news_widget)

            // Заполняем 3 слота новостей. Если данных нет — показываем заглушку.
            for (i in 0 until 3) {
                val slotTitleId = when (i) {
                    0 -> R.id.news_1_title
                    1 -> R.id.news_2_title
                    else -> R.id.news_3_title
                }
                val slotTickerId = when (i) {
                    0 -> R.id.news_1_ticker
                    1 -> R.id.news_2_ticker
                    else -> R.id.news_3_ticker
                }
                val slotTimeId = when (i) {
                    0 -> R.id.news_1_time
                    1 -> R.id.news_2_time
                    else -> R.id.news_3_time
                }
                val slotContainerId = when (i) {
                    0 -> R.id.news_slot_1
                    1 -> R.id.news_slot_2
                    else -> R.id.news_slot_3
                }

                val title = widgetData.getString("news_${i}_title", null)
                val ticker = widgetData.getString("news_${i}_ticker", "") ?: ""
                val time = widgetData.getString("news_${i}_time", "") ?: ""
                val newsId = widgetData.getString("news_${i}_id", null)

                if (title.isNullOrEmpty()) {
                    views.setTextViewText(slotTitleId, if (i == 0) "Откройте приложение, чтобы загрузить новости" else "")
                    views.setTextViewText(slotTickerId, "")
                    views.setTextViewText(slotTimeId, "")
                } else {
                    views.setTextViewText(slotTitleId, title)
                    views.setTextViewText(slotTickerId, ticker)
                    views.setTextViewText(slotTimeId, time)

                    // Tap по новости — запуск app с deep link.
                    if (!newsId.isNullOrEmpty()) {
                        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                            context,
                            MainActivity::class.java,
                            Uri.parse("stocksi://news/$newsId")
                        )
                        views.setOnClickPendingIntent(slotContainerId, pendingIntent)
                    }
                }
            }

            // Tap по кнопке refresh — отправка broadcast через
            // home_widget BackgroundIntent. Flutter-сторона перехватит
            // это в callbackDispatcher и вызовет forceReconnect.
            val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("stocksi://refresh")
            )
            views.setOnClickPendingIntent(R.id.widget_refresh, refreshIntent)

            // Tap по шапке (заголовку «STOCKSI ULTIMATE») — открыть app.
            val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("stocksi://open")
            )
            views.setOnClickPendingIntent(R.id.widget_title, openAppIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
