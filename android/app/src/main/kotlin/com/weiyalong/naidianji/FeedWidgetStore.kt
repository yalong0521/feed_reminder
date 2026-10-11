package com.weiyalong.naidianji

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.view.View
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** The Android projection of the Flutter HomeWidgetSnapshot. */
internal object FeedWidgetStore {
    private const val PREFERENCES = "feed_widget_snapshot_v1"
    private const val SCHEMA_VERSION = 1

    private const val GENERATED_AT = "generatedAtMs"
    private const val DATE_KEY = "dateKey"
    private const val ZONE_OFFSET = "zoneOffsetMinutes"
    private const val LATEST_TIME = "latestTimeMs"
    private const val LATEST_TIME_ZONE_OFFSET = "latestTimeZoneOffsetMinutes"
    private const val LATEST_AMOUNT = "latestMilkAmountMl"
    private const val DAY_TOTAL = "dayTotalMl"
    private const val DAY_COUNT = "dayCount"
    private const val NEXT_TIME = "nextFeedTimeMs"
    private const val NEXT_TIME_ZONE_OFFSET = "nextFeedTimeZoneOffsetMinutes"
    private const val REMINDER_ACKNOWLEDGED = "reminderAcknowledged"

    data class Snapshot(
        val generatedAtMs: Long,
        val dateKey: String,
        val zoneOffsetMinutes: Int,
        val latestTimeMs: Long?,
        val latestTimeZoneOffsetMinutes: Int?,
        val latestMilkAmountMl: Int,
        val dayTotalMl: Int,
        val dayCount: Int,
        val nextFeedTimeMs: Long?,
        val nextFeedTimeZoneOffsetMinutes: Int?,
        val reminderAcknowledged: Boolean,
    ) {
        val hasRecords: Boolean get() = latestTimeMs != null

        fun latestTime(): String = latestTimeMs?.let {
            formatTime(it, latestTimeZoneOffsetMinutes ?: zoneOffsetMinutes)
        } ?: "暂无记录"

        fun latestDate(): String = latestTimeMs?.let {
            formatDate(it, latestTimeZoneOffsetMinutes ?: zoneOffsetMinutes)
        } ?: ""

        fun latestClock(): String = latestTimeMs?.let {
            formatClock(it, latestTimeZoneOffsetMinutes ?: zoneOffsetMinutes)
        } ?: "暂无记录"

        fun latestAmount(): String = when {
            !hasRecords -> "记录第一餐"
            latestMilkAmountMl == 0 -> "未记录奶量"
            else -> "$latestMilkAmountMl mL"
        }

        fun nextReminder(): String = when {
            !hasRecords -> "记录后开始下一次提醒"
            reminderAcknowledged -> "本次提醒已停止"
            nextFeedTimeMs == null -> "暂无下次提醒"
            else -> "下次 ${formatTime(nextFeedTimeMs, nextFeedTimeZoneOffsetMinutes ?: zoneOffsetMinutes)}"
        }

        fun compactReminderLabel(): String = when {
            !hasRecords -> "奶点记"
            reminderAcknowledged -> "本次提醒"
            nextFeedTimeMs == null -> "下次喂奶"
            else -> "下次喂奶 · ${formatDate(nextFeedTimeMs, nextFeedTimeZoneOffsetMinutes ?: zoneOffsetMinutes)}"
        }

        fun compactReminderValue(): String = when {
            !hasRecords -> "暂无记录"
            reminderAcknowledged -> "已停止"
            nextFeedTimeMs == null -> "暂无提醒"
            else -> formatClock(nextFeedTimeMs, nextFeedTimeZoneOffsetMinutes ?: zoneOffsetMinutes)
        }

        fun updatedAt(): String = "更新于 ${formatTime(generatedAtMs, zoneOffsetMinutes)} · ${formatOffset(zoneOffsetMinutes)}"
    }

    fun save(context: Context, arguments: Map<*, *>): Boolean {
        val snapshot = parse(arguments) ?: return false
        val values = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putInt("schemaVersion", SCHEMA_VERSION)
            .putLong(GENERATED_AT, snapshot.generatedAtMs)
            .putString(DATE_KEY, snapshot.dateKey)
            .putInt(ZONE_OFFSET, snapshot.zoneOffsetMinutes)
            .putInt(LATEST_AMOUNT, snapshot.latestMilkAmountMl)
            .putInt(DAY_TOTAL, snapshot.dayTotalMl)
            .putInt(DAY_COUNT, snapshot.dayCount)
            .putBoolean(REMINDER_ACKNOWLEDGED, snapshot.reminderAcknowledged)
        putNullableLong(values, LATEST_TIME, snapshot.latestTimeMs)
        putNullableInt(values, LATEST_TIME_ZONE_OFFSET, snapshot.latestTimeZoneOffsetMinutes)
        putNullableLong(values, NEXT_TIME, snapshot.nextFeedTimeMs)
        putNullableInt(values, NEXT_TIME_ZONE_OFFSET, snapshot.nextFeedTimeZoneOffsetMinutes)
        if (!values.commit()) return false
        refreshAll(context)
        return true
    }

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        listOf(
            FeedWideWidgetProvider::class.java,
            FeedSquareWidgetProvider::class.java,
            FeedCompactWidgetProvider::class.java,
        ).forEach { provider ->
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isNotEmpty()) provider.getDeclaredConstructor().newInstance()
                .onUpdate(context, manager, ids)
        }
    }

    fun read(context: Context): Snapshot? {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (prefs.getInt("schemaVersion", 0) != SCHEMA_VERSION) return null
        val generatedAt = prefs.getLong(GENERATED_AT, Long.MIN_VALUE)
        val dateKey = prefs.getString(DATE_KEY, null) ?: return null
        val zoneOffset = prefs.getInt(ZONE_OFFSET, Int.MIN_VALUE)
        val latestAmount = prefs.getInt(LATEST_AMOUNT, -1)
        val dayTotal = prefs.getInt(DAY_TOTAL, -1)
        val dayCount = prefs.getInt(DAY_COUNT, -1)
        if (generatedAt == Long.MIN_VALUE || zoneOffset == Int.MIN_VALUE ||
            latestAmount < 0 || dayTotal < 0 || dayCount < 0
        ) return null
        return Snapshot(
            generatedAt,
            dateKey,
            zoneOffset,
            nullableLong(prefs, LATEST_TIME),
            nullableInt(prefs, LATEST_TIME_ZONE_OFFSET),
            latestAmount,
            dayTotal,
            dayCount,
            nullableLong(prefs, NEXT_TIME),
            nullableInt(prefs, NEXT_TIME_ZONE_OFFSET),
            prefs.getBoolean(REMINDER_ACKNOWLEDGED, false),
        )
    }

    fun launchIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("com.weiyalong.naidianji.FEED_WIDGET_ACTION")
            .putExtra("feedWidgetAction", action)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun parse(arguments: Map<*, *>): Snapshot? {
        fun number(key: String): Long? = (arguments[key] as? Number)?.toLong()
        fun int(key: String): Int? = number(key)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
        val generatedAt = number(GENERATED_AT) ?: return null
        val dateKey = arguments[DATE_KEY] as? String ?: return null
        val zoneOffset = int(ZONE_OFFSET) ?: return null
        val latestAmount = int(LATEST_AMOUNT) ?: return null
        val dayTotal = int(DAY_TOTAL) ?: return null
        val dayCount = int(DAY_COUNT) ?: return null
        val acknowledged = arguments[REMINDER_ACKNOWLEDGED] as? Boolean ?: return null
        if (dateKey.length != 10 || zoneOffset !in -840..840 ||
            latestAmount !in 0..2000 || dayTotal < 0 || dayCount < 0
        ) return null
        return Snapshot(
            generatedAt,
            dateKey,
            zoneOffset,
            number(LATEST_TIME),
            int(LATEST_TIME_ZONE_OFFSET)?.takeIf { it in -840..840 },
            latestAmount,
            dayTotal,
            dayCount,
            number(NEXT_TIME),
            int(NEXT_TIME_ZONE_OFFSET)?.takeIf { it in -840..840 },
            acknowledged,
        )
    }

    private fun putNullableLong(editor: android.content.SharedPreferences.Editor, key: String, value: Long?) {
        if (value == null) editor.remove(key) else editor.putLong(key, value)
    }

    private fun putNullableInt(editor: android.content.SharedPreferences.Editor, key: String, value: Int?) {
        if (value == null) editor.remove(key) else editor.putInt(key, value)
    }

    private fun nullableLong(prefs: android.content.SharedPreferences, key: String): Long? =
        if (prefs.contains(key)) prefs.getLong(key, 0) else null

    private fun nullableInt(prefs: android.content.SharedPreferences, key: String): Int? =
        if (prefs.contains(key)) prefs.getInt(key, 0) else null

    private fun formatTime(epoch: Long, offsetMinutes: Int): String =
        "${formatDate(epoch, offsetMinutes)} ${formatClock(epoch, offsetMinutes)}"

    private fun formatDate(epoch: Long, offsetMinutes: Int): String = format(epoch, offsetMinutes, "MM/dd")

    private fun formatClock(epoch: Long, offsetMinutes: Int): String = format(epoch, offsetMinutes, "HH:mm")

    private fun format(epoch: Long, offsetMinutes: Int, pattern: String): String {
        val formatter = SimpleDateFormat(pattern, Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("GMT${if (offsetMinutes >= 0) "+" else "-"}${String.format(Locale.US, "%02d:%02d", kotlin.math.abs(offsetMinutes) / 60, kotlin.math.abs(offsetMinutes) % 60)}")
        return formatter.format(Date(epoch))
    }

    private fun formatOffset(offsetMinutes: Int): String =
        "UTC${if (offsetMinutes >= 0) "+" else "-"}${String.format(Locale.US, "%02d:%02d", kotlin.math.abs(offsetMinutes) / 60, kotlin.math.abs(offsetMinutes) % 60)}"
}

abstract class FeedWidgetProvider : AppWidgetProvider() {
    protected abstract val layout: Int
    protected abstract val kind: Int

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = FeedWidgetStore.read(context)
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, layout)
            render(context, views, snapshot)
            manager.updateAppWidget(id, views)
        }
    }

    private fun render(context: Context, views: RemoteViews, snapshot: FeedWidgetStore.Snapshot?) {
        val data = snapshot ?: FeedWidgetStore.Snapshot(
            0, "", 0, null, null, 0, 0, 0, null, null, false,
        )
        when (kind) {
            1 -> {
                views.setTextViewText(
                    R.id.widget_compact_label,
                    if (snapshot == null) "奶点记" else data.compactReminderLabel(),
                )
                views.setTextViewText(
                    R.id.widget_compact_value,
                    if (snapshot == null) "打开应用" else data.compactReminderValue(),
                )
                views.setTextViewText(R.id.widget_compact_updated, data.updatedAt())
                views.setOnClickPendingIntent(R.id.widget_compact_root, FeedWidgetStore.launchIntent(context, "open_timer", 1001))
            }
            2 -> {
                views.setTextViewText(R.id.widget_square_title, "奶点记")
                val hasRecords = data.hasRecords
                views.setTextViewText(
                    R.id.widget_square_state,
                    if (hasRecords) "最近一餐 · ${data.latestDate()}"
                    else if (snapshot == null) "喂养记录" else "暂无记录",
                )
                views.setTextViewText(R.id.widget_square_time, data.latestClock())
                views.setTextViewText(R.id.widget_square_amount, data.latestAmount())
                views.setTextViewText(
                    R.id.widget_square_empty_subtitle,
                    if (snapshot == null) "打开应用后显示记录" else "记下宝宝的第一餐",
                )
                views.setTextViewText(
                    R.id.widget_square_next,
                    if (hasRecords) data.nextReminder() else "",
                )
                views.setTextViewText(R.id.widget_square_action, if (hasRecords) "记录喂奶" else "打开奶点记")
                views.setViewVisibility(R.id.widget_square_data, if (hasRecords) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_square_empty_subtitle, if (hasRecords) View.GONE else View.VISIBLE)
                views.setViewVisibility(R.id.widget_square_next, if (hasRecords) View.VISIBLE else View.GONE)
                views.setOnClickPendingIntent(R.id.widget_square_root, FeedWidgetStore.launchIntent(context, "open_timer", 2001))
                views.setOnClickPendingIntent(R.id.widget_square_action, FeedWidgetStore.launchIntent(context, if (hasRecords) "record_feed" else "open_timer", 2002))
            }
            else -> {
                views.setTextViewText(R.id.widget_wide_title, "奶点记")
                views.setTextViewText(R.id.widget_wide_date, if (snapshot == null) "喂养记录" else data.dateKey + " 汇总")
                views.setTextViewText(R.id.widget_wide_latest, if (data.hasRecords) data.latestTime() else "暂无记录")
                views.setTextViewText(R.id.widget_wide_amount, data.latestAmount())
                views.setTextViewText(R.id.widget_wide_total, if (snapshot == null) "—" else "${data.dayTotalMl} mL")
                views.setTextViewText(R.id.widget_wide_count, if (snapshot == null) "—" else "${data.dayCount} 次")
                views.setTextViewText(R.id.widget_wide_next, if (snapshot == null) "打开奶点记后显示记录" else data.nextReminder())
                views.setTextViewText(
                    R.id.widget_wide_updated,
                    snapshot?.updatedAt() ?: "数据仅在本机保存",
                )
                views.setTextViewText(R.id.widget_wide_empty_message, "打开奶点记后显示记录")
                views.setTextViewText(R.id.widget_wide_empty_action, "打开奶点记")
                views.setTextViewText(R.id.widget_wide_action, "记录喂奶")
                views.setViewVisibility(R.id.widget_wide_data, if (snapshot == null) View.GONE else View.VISIBLE)
                views.setViewVisibility(R.id.widget_wide_empty, if (snapshot == null) View.VISIBLE else View.GONE)
                views.setOnClickPendingIntent(R.id.widget_wide_root, FeedWidgetStore.launchIntent(context, "open_timer", 3001))
                views.setOnClickPendingIntent(R.id.widget_wide_action, FeedWidgetStore.launchIntent(context, "record_feed", 3002))
                views.setOnClickPendingIntent(R.id.widget_wide_empty_action, FeedWidgetStore.launchIntent(context, "open_timer", 3003))
            }
        }
    }
}

class FeedWideWidgetProvider : FeedWidgetProvider() {
    override val layout = R.layout.widget_wide
    override val kind = 3
}

class FeedSquareWidgetProvider : FeedWidgetProvider() {
    override val layout = R.layout.widget_square
    override val kind = 2
}

class FeedCompactWidgetProvider : FeedWidgetProvider() {
    override val layout = R.layout.widget_compact
    override val kind = 1
}
