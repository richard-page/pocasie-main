package sk.menopocasie.app

import android.content.Context
import android.util.TypedValue
import android.widget.RemoteViews

object MeteoWidgetPlaceholder {
  const val DASH = "—"
  const val DASH_TEXT_COLOR = 0xCCFFFFFF.toInt()

  fun dashTextSizeSp(context: Context): Float {
    val px = context.resources.getDimension(R.dimen.meteo_widget_placeholder_dash_text_size)
    return px / context.resources.displayMetrics.scaledDensity
  }

  private fun setDashField(views: RemoteViews, viewId: Int, sp: Float) {
    views.setTextViewText(viewId, DASH)
    views.setTextViewTextSize(viewId, TypedValue.COMPLEX_UNIT_SP, sp)
    views.setTextColor(viewId, DASH_TEXT_COLOR)
  }

  fun applyStandard(context: Context, views: RemoteViews) {
    val sp = dashTextSizeSp(context)
    setDashField(views, R.id.meteo_widget_city, sp)
    setDashField(views, R.id.meteo_widget_temp, sp)
    views.setTextViewText(R.id.meteo_widget_time, "")
    views.setTextViewText(R.id.meteo_widget_apparent, "")
    views.setTextViewText(R.id.meteo_widget_desc, "")
    MeteoWidgetIconHelper.showDash(
      views,
      R.id.meteo_widget_icon,
      R.id.meteo_widget_icon_dash,
      sp,
    )
  }

  fun applyMini(context: Context, views: RemoteViews) {
    val sp = dashTextSizeSp(context)
    setDashField(views, R.id.meteo_widget_mini_city, sp)
    setDashField(views, R.id.meteo_widget_mini_temp, sp)
    views.setTextViewText(R.id.meteo_widget_mini_time, "")
    MeteoWidgetIconHelper.showDash(
      views,
      R.id.meteo_widget_mini_icon,
      R.id.meteo_widget_mini_icon_dash,
      sp,
    )
  }

  fun applyPlus(context: Context, views: RemoteViews) {
    val sp = dashTextSizeSp(context)
    setDashField(views, R.id.meteo_widget_plus_city, sp)
    setDashField(views, R.id.meteo_widget_plus_temp, sp)
    views.setTextViewText(R.id.meteo_widget_plus_time, "")
    views.setTextViewText(R.id.meteo_widget_plus_apparent, "")
    views.setTextViewText(R.id.meteo_widget_plus_desc, "")
    setDashField(views, R.id.meteo_widget_plus_wind, sp)
    setDashField(views, R.id.meteo_widget_plus_sun, sp)
    setDashField(views, R.id.meteo_widget_plus_humidity, sp)
    MeteoWidgetIconHelper.showDash(
      views,
      R.id.meteo_widget_plus_icon,
      R.id.meteo_widget_plus_icon_dash,
      sp,
    )
  }
}
