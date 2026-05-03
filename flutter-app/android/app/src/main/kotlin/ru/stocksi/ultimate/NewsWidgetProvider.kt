package ru.stocksi.ultimate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * AppWidgetProvider для виджета «Последние новости Stocksi».
 *
 * Адаптивный — показывает от 1 до 7 новостей в зависимости от высоты,
 * выбранной пользователем при ресайзе. Данные приходят от Flutter в виде
 * JSON-строки в SharedPreferences ключе "news_json" (массив объектов с
 * полями id, ticker, title, time).
 */
class NewsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { appWidgetId ->
            renderWidget(context, appWidgetManager, appWidgetId, widgetData)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val widgetData =
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        renderWidget(context, appWidgetManager, appWidgetId, widgetData)
    }

    private fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.news_widget)

        val opts = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minHeightDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val visibleSlots = computeVisibleSlots(minHeightDp)

        // Парсим JSON-массив новостей; если пусто или ошибка — показываем заглушку.
        val newsArr = try {
            val raw = widgetData.getString("news_json", null)
            if (raw.isNullOrEmpty()) JSONArray() else JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }

        val slotIds = intArrayOf(
            R.id.news_slot_1, R.id.news_slot_2, R.id.news_slot_3,
            R.id.news_slot_4, R.id.news_slot_5, R.id.news_slot_6,
            R.id.news_slot_7
        )
        val titleIds = intArrayOf(
            R.id.news_1_title, R.id.news_2_title, R.id.news_3_title,
            R.id.news_4_title, R.id.news_5_title, R.id.news_6_title,
            R.id.news_7_title
        )
        val tickerIds = intArrayOf(
            R.id.news_1_ticker, R.id.news_2_ticker, R.id.news_3_ticker,
            R.id.news_4_ticker, R.id.news_5_ticker, R.id.news_6_ticker,
            R.id.news_7_ticker
        )
        val timeIds = intArrayOf(
            R.id.news_1_time, R.id.news_2_time, R.id.news_3_time,
            R.id.news_4_time, R.id.news_5_time, R.id.news_6_time,
            R.id.news_7_time
        )

        for (i in 0 until 7) {
            views.setViewVisibility(
                slotIds[i],
                if (i < visibleSlots) View.VISIBLE else View.GONE
            )
        }

        for (i in 0 until visibleSlots) {
            val item = if (i < newsArr.length()) newsArr.optJSONObject(i) else null
            val title = item?.optString("title") ?: ""
            val ticker = item?.optString("ticker") ?: ""
            val time = item?.optString("time") ?: ""
            val newsId = item?.optString("id") ?: ""

            if (title.isEmpty()) {
                views.setTextViewText(
                    titleIds[i],
                    if (i == 0) "Откройте приложение, чтобы загрузить новости" else ""
                )
                views.setTextViewText(tickerIds[i], "")
                views.setTextViewText(timeIds[i], "")
            } else {
                views.setTextViewText(titleIds[i], title)
                views.setTextViewText(tickerIds[i], ticker)
                views.setTextViewText(timeIds[i], time)

                if (newsId.isNotEmpty()) {
                    val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("stocksi://news/$newsId")
                    )
                    views.setOnClickPendingIntent(slotIds[i], pendingIntent)
                }
            }
        }

        val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("stocksi://refresh")
        )
        views.setOnClickPendingIntent(R.id.widget_refresh, refreshIntent)

        val openAppIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("stocksi://open")
        )
        views.setOnClickPendingIntent(R.id.widget_title, openAppIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun computeVisibleSlots(heightDp: Int): Int = when {
        heightDp < 110 -> 1
        heightDp < 160 -> 2
        heightDp < 220 -> 3
        heightDp < 280 -> 4
        heightDp < 340 -> 5
        heightDp < 400 -> 6
        else -> 7
    }
}
