package sk.menopocasie.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class MeteoPocasieWidgetProvider : HomeWidgetProvider() {

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
        Log.e("MeteoWidget", "onUpdate", e)
        try {
          val fallback = RemoteViews(context.packageName, R.layout.meteo_weather_widget)
          setSafeClick(context, fallback)
          MeteoWidgetPlaceholder.applyStandard(context, fallback)
          appWidgetManager.updateAppWidget(id, fallback)
        } catch (e2: Exception) {
          Log.e("MeteoWidget", "fallback", e2)
        }
      }
    }
  }

  private fun setSafeClick(context: Context, views: RemoteViews) {
    val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, null)
    views.setOnClickPendingIntent(R.id.meteo_widget_root, launch)
  }

  private fun buildViews(context: Context, widgetData: SharedPreferences): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.meteo_weather_widget)
    setSafeClick(context, views)

    if (!MeteoWidgetIconHelper.isReady(widgetData)) {
      MeteoWidgetPlaceholder.applyStandard(context, views)
      return views
    }

    val city = widgetData.getString("widget_city", "—") ?: "—"
    val description = widgetData.getString("widget_description", "") ?: ""
    val temp = widgetData.getString("widget_temp", "—") ?: "—"
    val timeJe = widgetData.getString("widget_time_je", "") ?: ""
    val codeStr = widgetData.getString("widget_code", "0")
    val code = codeStr?.toIntOrNull() ?: 0
    val isDay = (widgetData.getString("widget_is_day", "1") == "1")
    val apparent = widgetData.getString("widget_apparent", "") ?: ""
    val offline = (widgetData.getString("widget_offline", "0") == "1")

    views.setTextViewText(R.id.meteo_widget_city, city)
    views.setTextViewText(R.id.meteo_widget_desc, if (offline) "Offline" else description)
    views.setTextViewText(R.id.meteo_widget_temp, temp)
    views.setTextViewText(R.id.meteo_widget_time, timeJe)
    views.setTextViewText(R.id.meteo_widget_apparent, apparent)

    MeteoWidgetIconHelper.applyIcon(
      context,
      views,
      R.id.meteo_widget_icon,
      R.id.meteo_widget_icon_dash,
      widgetData,
      code,
      isDay,
    )
    return views
  }
}
