package com.noobclaw.daycount

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/**
 * Home-screen widget showing the featured countdown. Data is written by the
 * Flutter side through the `home_widget` plugin, which stores it in the shared
 * preferences file named "HomeWidgetPreferences" — we read it directly here so
 * this provider has no compile dependency on the plugin's Kotlin classes.
 */
class CountdownWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val title = prefs.getString("dc_title", null) ?: "倒数日"
        val emoji = prefs.getString("dc_emoji", "") ?: ""
        val num = prefs.getString("dc_num", "—") ?: "—"
        val label = prefs.getString("dc_label", "") ?: ""
        val date = prefs.getString("dc_date", "") ?: ""

        val heading = if (emoji.isEmpty()) title else "$emoji $title"

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.countdown_widget)
            views.setTextViewText(R.id.dc_widget_title, heading)
            views.setTextViewText(R.id.dc_widget_num, num)
            views.setTextViewText(R.id.dc_widget_label, label)
            views.setTextViewText(R.id.dc_widget_date, date)

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pending = PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.dc_widget_root, pending)
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
