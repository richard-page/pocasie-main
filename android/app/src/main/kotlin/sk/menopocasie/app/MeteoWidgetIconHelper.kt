package sk.menopocasie.app

import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

object MeteoWidgetIconHelper {
  const val PREF_READY = "widget_ready"

  fun isReady(widgetData: SharedPreferences): Boolean {
    if (widgetData.getString(PREF_READY, "0") == "1") return true
    // Spätná kompatibilita: staršie dáta bez widget_ready, ale s reálnou predpoveďou.
    val city = widgetData.getString("widget_city", "—") ?: "—"
    val temp = widgetData.getString("widget_temp", "—") ?: "—"
    val desc = widgetData.getString("widget_description", "") ?: ""
    if (city == MeteoWidgetPlaceholder.DASH || temp == MeteoWidgetPlaceholder.DASH) return false
    if (desc.contains("Otvorte aplikáciu", ignoreCase = true)) return false
    if (desc.contains("Otvor aplikáciu", ignoreCase = true)) return false
    return city.isNotBlank() && temp.isNotBlank()
  }

  fun showDash(
    views: RemoteViews,
    iconViewId: Int,
    dashViewId: Int,
    textSizeSp: Float,
  ) {
    views.setViewVisibility(iconViewId, View.GONE)
    views.setViewVisibility(dashViewId, View.VISIBLE)
    views.setTextViewText(dashViewId, MeteoWidgetPlaceholder.DASH)
    views.setTextViewTextSize(
      dashViewId,
      android.util.TypedValue.COMPLEX_UNIT_SP,
      textSizeSp,
    )
    views.setTextColor(dashViewId, MeteoWidgetPlaceholder.DASH_TEXT_COLOR)
  }

  fun applyIcon(
    context: Context,
    views: RemoteViews,
    iconViewId: Int,
    dashViewId: Int,
    widgetData: SharedPreferences,
    code: Int,
    isDay: Boolean,
  ) {
    if (!isReady(widgetData)) {
      showDash(
        views,
        iconViewId,
        dashViewId,
        MeteoWidgetPlaceholder.dashTextSizeSp(context),
      )
      return
    }

    views.setViewVisibility(dashViewId, View.GONE)
    views.setViewVisibility(iconViewId, View.VISIBLE)

    val iconFile = widgetData.getString("widget_icon_file", "") ?: ""
    val iconLoadedFromFile = try {
      if (iconFile.isNotEmpty()) {
        val f = File(iconFile)
        if (f.exists()) {
          val bmp = BitmapFactory.decodeFile(iconFile)
          if (bmp != null) {
            views.setImageViewBitmap(iconViewId, bmp)
            true
          } else {
            false
          }
        } else {
          false
        }
      } else {
        false
      }
    } catch (_: Exception) {
      false
    }

    if (!iconLoadedFromFile) {
      try {
        views.setImageViewResource(iconViewId, wmoToDrawableId(code, isDay))
      } catch (_: Exception) {
        views.setImageViewResource(iconViewId, R.drawable.meteo_w_cloud)
      }
    }
  }

  private fun wmoToDrawableId(code: Int, isDay: Boolean): Int {
    if (code == 0) return if (isDay) R.drawable.meteo_w_sun else R.drawable.meteo_w_moon
    if (code in 1..2) return R.drawable.meteo_w_partly
    if (code in 3..48) return R.drawable.meteo_w_cloud
    if (code in 51..67 || code in 80..82) return R.drawable.meteo_w_rain
    if (code in 71..86) return R.drawable.meteo_w_snow
    if (code >= 95) return R.drawable.meteo_w_thunder
    return R.drawable.meteo_w_cloud
  }
}
