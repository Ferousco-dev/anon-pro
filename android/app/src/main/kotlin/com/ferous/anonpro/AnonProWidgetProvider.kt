package com.ferous.anonpro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.*

class AnonProWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_RELOAD = "com.ferous.anonpro.WIDGET_RELOAD"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Handle explicit reload broadcast
        if (intent.action == ACTION_RELOAD) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, AnonProWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)

            // ── Read data ────────────────────────────────────────────────────
            val newPosts           = widgetData.getInt("new_posts_count", 0)
            val newAnon            = widgetData.getInt("anon_confessions_count", 0)
            val newInbox           = widgetData.getInt("unread_messages_count", 0)
            val latestAnonPreview  = widgetData.getString(
                "latest_anon_preview",
                "No recent confessions — be the first to share anonymously."
            ) ?: "No recent confessions — be the first to share anonymously."
            val rawName            = widgetData.getString("user_display_name", "AnonPro") ?: "AnonPro"
            val profileInitial     = rawName.take(1).uppercase()
            val lastUpdatedRaw     = widgetData.getString("last_updated", "") ?: ""
            val lastUpdatedLabel   = formatUpdatedTime(lastUpdatedRaw)

            // ── Try to figure out widget size via AppWidgetOptions ───────────
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)

            // Determine layout file
            val layoutRes = when {
                minWidth >= 300 -> R.layout.anonpro_widget_large
                minWidth >= 200 -> R.layout.anonpro_widget_medium
                else            -> R.layout.anonpro_widget_small
            }

            val views = RemoteViews(context.packageName, layoutRes)

            // ── Common: populate counts ─────────────────────────────────────
            fun safeSet(id: Int, text: String) {
                try { views.setTextViewText(id, text) } catch (_: Exception) {}
            }
            fun safeIntent(id: Int, url: String, requestCode: Int) {
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        setPackage(context.packageName)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    val pi = PendingIntent.getActivity(
                        context, requestCode, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(id, pi)
                } catch (_: Exception) {}
            }

            // Text fields present across layouts
            safeSet(R.id.tv_profile_initial, profileInitial)
            safeSet(R.id.tv_latest_anon_preview, latestAnonPreview)
            safeSet(R.id.tv_last_updated, lastUpdatedLabel)

            // Stats - small widget uses different IDs
            if (layoutRes == R.layout.anonpro_widget_small) {
                safeSet(R.id.tv_posts_count, newPosts.toString())
                safeSet(R.id.tv_anon_count, newAnon.toString())
                safeSet(R.id.tv_messages_count, newInbox.toString())
            } else {
                safeSet(R.id.tv_stat_posts, newPosts.toString())
                safeSet(R.id.tv_stat_anon, newAnon.toString())
                safeSet(R.id.tv_stat_inbox, newInbox.toString())
            }

            // ── Deep links ─────────────────────────────────────────────────
            safeIntent(R.id.btn_home,    "anonpro://home",      0)
            safeIntent(R.id.btn_anon,    "anonpro://anonymous", 1)
            safeIntent(R.id.btn_inbox,   "anonpro://inbox",     2)
            safeIntent(R.id.btn_profile, "anonpro://profile",   3)

            // Large layout quick dock buttons
            try { safeIntent(R.id.dock_home,    "anonpro://home",      10) } catch (_: Exception) {}
            try { safeIntent(R.id.dock_anon,    "anonpro://anonymous", 11) } catch (_: Exception) {}
            try { safeIntent(R.id.dock_inbox,   "anonpro://inbox",     12) } catch (_: Exception) {}
            try { safeIntent(R.id.dock_profile, "anonpro://profile",   13) } catch (_: Exception) {}

            // Confession card deep link
            try { safeIntent(R.id.card_latest_anon, "anonpro://anonymous", 5) } catch (_: Exception) {}

            // Root widget tap → open app
            val mainIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val mainPending = PendingIntent.getActivity(
                context, 4, mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, mainPending)

            // ── Reload button -----------------------------------------------
            // Tapping reload broadcasts ACTION_RELOAD which re-runs onUpdate
            // to refresh data from the shared HomeWidget store.
            val reloadIntent = Intent(context, AnonProWidgetProvider::class.java).apply {
                action = ACTION_RELOAD
            }
            val reloadPending = PendingIntent.getBroadcast(
                context, 99, reloadIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            try { views.setOnClickPendingIntent(R.id.btn_reload, reloadPending) } catch (_: Exception) {}

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        // Re-draw when widget is resized
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun formatUpdatedTime(iso: String): String {
        if (iso.isEmpty()) return "Just now"
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            val date = fmt.parse(iso) ?: return "Just now"
            val diff = (Date().time - date.time) / 60000  // minutes
            when {
                diff < 1  -> "Just now"
                diff == 1L -> "1 min ago"
                diff < 60 -> "$diff min ago"
                else      -> "${diff / 60}h ago"
            }
        } catch (_: Exception) {
            "Just now"
        }
    }
}
