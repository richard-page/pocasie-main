package sk.menopocasie.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class MeteoVystrahyWidgetProvider : HomeWidgetProvider() {

  companion object {
    /** Deep link — Flutter otvorí MeteoVystrahyPage. */
    val OPEN_VYSTRAHY_URI: Uri = Uri.parse("menopocasie://open/vystrahy")
  }

  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      try {
        val views = buildViews(context, widgetData)
        appWidgetManager.updateAppWidget(id, views)
      } catch (e: Exception) {
        Log.e("MeteoVystrahyWidget", "onUpdate", e)
        try {
          val fallback = RemoteViews(context.packageName, R.layout.meteo_vystrahy_widget)
          setSafeClick(context, fallback)
          applyEmpty(fallback)
          appWidgetManager.updateAppWidget(id, fallback)
        } catch (e2: Exception) {
          Log.e("MeteoVystrahyWidget", "fallback", e2)
        }
      }
    }
  }

  private fun setSafeClick(context: Context, views: RemoteViews) {
    val launch = HomeWidgetLaunchIntent.getActivity(
      context,
      MainActivity::class.java,
      OPEN_VYSTRAHY_URI,
    )
    views.setOnClickPendingIntent(R.id.meteo_vystrahy_widget_root, launch)
    views.setOnClickPendingIntent(R.id.meteo_vystrahy_widget_card, launch)
  }

  private fun applyEmpty(views: RemoteViews) {
    views.setInt(
      R.id.meteo_vystrahy_widget_card,
      "setBackgroundResource",
      R.drawable.meteo_vystrahy_widget_bg,
    )
    views.setInt(
      R.id.meteo_vystrahy_widget_icon_wrap,
      "setBackgroundResource",
      R.drawable.meteo_vystrahy_icon_circle_none,
    )
    views.setTextViewText(R.id.meteo_vystrahy_widget_icon_glyph, "✓")
    views.setTextViewText(R.id.meteo_vystrahy_widget_title, "Bez výstrahy")
    views.setTextViewText(R.id.meteo_vystrahy_widget_level, "Žiadna aktívna výstraha")
    views.setTextColor(R.id.meteo_vystrahy_widget_level, Color.parseColor("#94A3B8"))
    views.setViewVisibility(R.id.meteo_vystrahy_widget_types, View.GONE)
    views.setTextViewText(R.id.meteo_vystrahy_widget_timing, "")
    views.setViewVisibility(R.id.meteo_vystrahy_widget_timing, View.GONE)
    views.setTextColor(R.id.meteo_vystrahy_widget_chevron, Color.parseColor("#94A3B8"))
  }

  private fun accentColor(rank: Int): Int {
    return when (rank) {
      1 -> Color.parseColor("#FACC15")
      2 -> Color.parseColor("#F97316")
      3, 4 -> Color.parseColor("#EF4444")
      else -> Color.parseColor("#94A3B8")
    }
  }

  private fun bgForRank(rank: Int): Int {
    return when (rank) {
      1 -> R.drawable.meteo_vystrahy_widget_bg_l1
      2 -> R.drawable.meteo_vystrahy_widget_bg_l2
      3, 4 -> R.drawable.meteo_vystrahy_widget_bg_l3
      else -> R.drawable.meteo_vystrahy_widget_bg
    }
  }

  private fun circleForRank(rank: Int): Int {
    return when (rank) {
      1 -> R.drawable.meteo_vystrahy_icon_circle_l1
      2 -> R.drawable.meteo_vystrahy_icon_circle_l2
      3, 4 -> R.drawable.meteo_vystrahy_icon_circle_l3
      else -> R.drawable.meteo_vystrahy_icon_circle_none
    }
  }

  private fun glyphForJav(javId: String, hasWarning: Boolean): String {
    if (!hasWarning) return "✓"
    val key = javId.lowercase()
    return when {
      key.contains("búrk") || key.contains("burk") -> "⚡"
      key.contains("dáž") || key.contains("daz") -> "🌧"
      key.contains("vietor") -> "💨"
      key.contains("poľad") || key.contains("polad") -> "❄"
      key.contains("vysok") -> "🌡"
      key.contains("nízk") || key.contains("nizk") -> "❄"
      key.contains("hmla") -> "🌫"
      key.contains("sneh") -> "❄"
      else -> "⚠"
    }
  }

  private fun buildViews(context: Context, widgetData: SharedPreferences): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.meteo_vystrahy_widget)
    setSafeClick(context, views)

    val ready = widgetData.getString("vystrahy_widget_ready", "0") == "1"
    if (!ready) {
      applyEmpty(views)
      return views
    }

    val hasWarning = widgetData.getString("vystrahy_widget_has_warning", "0") == "1"
    val title = widgetData.getString("vystrahy_widget_title", "Bez výstrahy") ?: "Bez výstrahy"
    val level = widgetData.getString("vystrahy_widget_level", "Žiadna aktívna výstraha")
      ?: "Žiadna aktívna výstraha"
    val types = widgetData.getString("vystrahy_widget_types", "") ?: ""
    val timing = widgetData.getString("vystrahy_widget_timing", "") ?: ""
    val rank = widgetData.getString("vystrahy_widget_rank", "0")?.toIntOrNull() ?: 0
    val javId = widgetData.getString("vystrahy_widget_jav_id", "") ?: ""

    if (!hasWarning) {
      applyEmpty(views)
      views.setTextViewText(R.id.meteo_vystrahy_widget_title, title)
      views.setTextViewText(R.id.meteo_vystrahy_widget_level, level)
      if (timing.isNotEmpty()) {
        views.setViewVisibility(R.id.meteo_vystrahy_widget_timing, View.VISIBLE)
        views.setTextViewText(R.id.meteo_vystrahy_widget_timing, timing)
      } else {
        views.setViewVisibility(R.id.meteo_vystrahy_widget_timing, View.GONE)
      }
      return views
    }

    val accent = accentColor(rank)
    views.setInt(R.id.meteo_vystrahy_widget_card, "setBackgroundResource", bgForRank(rank))
    views.setInt(R.id.meteo_vystrahy_widget_icon_wrap, "setBackgroundResource", circleForRank(rank))
    views.setTextViewText(R.id.meteo_vystrahy_widget_icon_glyph, glyphForJav(javId, true))
    views.setTextViewText(R.id.meteo_vystrahy_widget_title, title)
    views.setTextViewText(R.id.meteo_vystrahy_widget_level, level)
    views.setTextColor(R.id.meteo_vystrahy_widget_level, accent)
    views.setTextColor(R.id.meteo_vystrahy_widget_chevron, accent)

    if (types.isNotBlank()) {
      views.setViewVisibility(R.id.meteo_vystrahy_widget_types, View.VISIBLE)
      views.setTextViewText(R.id.meteo_vystrahy_widget_types, types)
    } else {
      views.setViewVisibility(R.id.meteo_vystrahy_widget_types, View.GONE)
    }

    views.setViewVisibility(R.id.meteo_vystrahy_widget_timing, View.VISIBLE)
    views.setTextViewText(
      R.id.meteo_vystrahy_widget_timing,
      if (timing.isNotBlank()) timing else "Ťuknite pre mapu výstrah",
    )
    return views
  }
}
