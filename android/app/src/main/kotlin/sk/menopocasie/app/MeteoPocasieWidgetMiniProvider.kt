package sk.menopocasie.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class MeteoPocasieWidgetMiniProvider : HomeWidgetProvider() {

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
        Log.e("MeteoWidgetMini", "onUpdate", e)
        try {
          val fallback = RemoteViews(context.packageName, R.layout.meteo_weather_widget_mini)
          setSafeClick(context, fallback)
          MeteoWidgetPlaceholder.applyMini(context, fallback)
          appWidgetManager.updateAppWidget(id, fallback)
        } catch (e2: Exception) {
          Log.e("MeteoWidgetMini", "fallback", e2)
        }
      }
    }
  }

  private fun setSafeClick(context: Context, views: RemoteViews) {
    val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
    views.setOnClickPendingIntent(R.id.meteo_widget_mini_root, launch)
  }

  private fun buildViews(context: Context, widgetData: SharedPreferences): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.meteo_weather_widget_mini)
    setSafeClick(context, views)

    if (!MeteoWidgetIconHelper.isReady(widgetData)) {
      MeteoWidgetPlaceholder.applyMini(context, views)
      return views
    }

    val city = widgetData.getString("widget_city", "—") ?: "—"
    val temp = widgetData.getString("widget_temp", "—") ?: "—"
    val timeJe = widgetData.getString("widget_time_je", "") ?: ""
    val codeStr = widgetData.getString("widget_code", "0")
    val code = codeStr?.toIntOrNull() ?: 0
    val isDay = (widgetData.getString("widget_is_day", "1") == "1")

    views.setTextViewText(R.id.meteo_widget_mini_city, city)
    views.setTextViewText(R.id.meteo_widget_mini_time, timeJe)
    views.setTextViewText(R.id.meteo_widget_mini_temp, temp)

    MeteoWidgetIconHelper.applyIcon(
      context,
      views,
      R.id.meteo_widget_mini_icon,
      R.id.meteo_widget_mini_icon_dash,
      widgetData,
      code,
      isDay,
    )
    return views
  }
}
