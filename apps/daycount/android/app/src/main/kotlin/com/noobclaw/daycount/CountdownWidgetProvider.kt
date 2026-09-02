package com.noobclaw.daycount

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Home-screen widget showing the featured countdown.
 *
 * The Flutter side writes only the *data* (target date, yearly flag, label
 * templates) through the `home_widget` plugin's shared preferences; this
 * provider computes "how many days" from the device clock each time it
 * renders, so the number is right at 00:00 whether or not the app is ever
 * opened again. It re-renders itself just after local midnight via an
 * inexact alarm, on the system's time / zone / date broadcasts, and every
 * 30 minutes through `updatePeriodMillis` as a backstop.
 */
class CountdownWidgetProvider : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            ACTION_MIDNIGHT -> refreshAll(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val hasEvent = prefs.getString("dc_has_event", "false") == "true"
        val appName = context.getString(R.string.app_name)
        val title = prefs.getString("dc_title", null) ?: appName
        val emoji = prefs.getString("dc_emoji", "") ?: ""

        val num: String
        val label: String
        val date: String
        if (!hasEvent) {
            num = "—"
            label = prefs.getString("dc_empty_label", "") ?: ""
            date = prefs.getString("dc_empty_date", "") ?: ""
        } else {
            val today = LocalDate.now()
            val anchor = runCatching { LocalDate.parse(prefs.getString("dc_date_iso", "") ?: "") }
                .getOrNull()
            if (anchor == null) {
                num = "—"; label = ""; date = ""
            } else {
                val yearly = prefs.getString("dc_yearly", "false") == "true"
                val target = if (yearly) nextYearly(anchor, today) else anchor
                val days = ChronoUnit.DAYS.between(today, target).toInt()
                num = if (days == 0) "🎉" else Math.abs(days).toString()
                label = when {
                    days == 0 -> prefs.getString("dc_label_today", "") ?: ""
                    days == 1 -> prefs.getString("dc_label_future_1", "") ?: ""
                    days == -1 -> prefs.getString("dc_label_past_1", "") ?: ""
                    days > 0 -> (prefs.getString("dc_label_future", "{n}") ?: "{n}")
                        .replace("{n}", days.toString())
                    else -> (prefs.getString("dc_label_past", "{n}") ?: "{n}")
                        .replace("{n}", (-days).toString())
                }
                date = target.toString()
            }
        }

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

        scheduleMidnight(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .cancel(midnightIntent(context))
    }

    /** The next occurrence of [anchor]'s month/day on or after [today], clamped
     *  to the month's length (29 Feb → 28 Feb in a common year) — the same rule
     *  as the Dart model's `nextYearlyOccurrence`. */
    private fun nextYearly(anchor: LocalDate, today: LocalDate): LocalDate {
        fun clamp(year: Int): LocalDate {
            val ym = YearMonth.of(year, anchor.monthValue)
            return ym.atDay(minOf(anchor.dayOfMonth, ym.lengthOfMonth()))
        }
        val thisYear = clamp(today.year)
        return if (thisYear.isBefore(today)) clamp(today.year + 1) else thisYear
    }

    private fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, CountdownWidgetProvider::class.java))
        if (ids.isNotEmpty()) onUpdate(context, mgr, ids)
    }

    private fun midnightIntent(context: Context): PendingIntent {
        val intent = Intent(context, CountdownWidgetProvider::class.java).setAction(ACTION_MIDNIGHT)
        return PendingIntent.getBroadcast(
            context, 1, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** One inexact alarm just after local midnight. Inexact alarms need no
     *  special permission; Doze may hold it back a few minutes, which the
     *  30-minute periodic update also covers. Re-armed on every render. */
    private fun scheduleMidnight(context: Context) {
        val next = LocalDateTime.of(LocalDate.now().plusDays(1), LocalTime.MIDNIGHT)
            .plusSeconds(5)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC, next, midnightIntent(context))
    }

    companion object {
        const val ACTION_MIDNIGHT = "com.noobclaw.daycount.WIDGET_MIDNIGHT"
    }
}
