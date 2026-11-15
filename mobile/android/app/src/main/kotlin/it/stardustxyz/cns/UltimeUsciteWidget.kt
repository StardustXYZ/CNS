package it.stardustxyz.cns

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget "Ultime uscite": the last Novità, written by the app (lib/data/home_widget_sync.dart). */
class UltimeUsciteWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_ultime_uscite).apply {
                setTextViewText(R.id.widget_righe, widgetData.getString("novita_testo", null) ?: "Apri CNS per vedere le novità.")
                setOnClickPendingIntent(
                    R.id.widget_radice,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("cns://novita")),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
