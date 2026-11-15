package it.stardustxyz.cns

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget "Prossimo da recuperare": the next release of the bookmark, written by the app. */
class ProssimoWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val artistId = widgetData.getString("prossimo_id", null)
        val link = if (artistId.isNullOrEmpty()) "cns://recuperando" else "cns://artista/$artistId"
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_prossimo).apply {
                setTextViewText(R.id.widget_titolo_uscita, widgetData.getString("prossimo_titolo", null) ?: "Apri CNS")
                setTextViewText(
                    R.id.widget_dettaglio,
                    widgetData.getString("prossimo_dettaglio", null) ?: "per vedere cosa ascoltare dopo.",
                )
                setOnClickPendingIntent(
                    R.id.widget_radice,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link)),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
