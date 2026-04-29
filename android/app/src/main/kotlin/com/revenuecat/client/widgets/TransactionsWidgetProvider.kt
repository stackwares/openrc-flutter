package com.revenuecat.client.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews
import com.revenuecat.client.R
import org.json.JSONObject

class TransactionsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val TAG = "TransactionsWidget"

        fun updateWidgets(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
            for (appWidgetId in appWidgetIds) {
                updateWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
                val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)

                val layoutRes = when {
                    maxHeight >= 200 -> R.layout.transactions_widget_large
                    maxWidth >= 200 -> R.layout.transactions_widget_medium
                    else -> R.layout.transactions_widget_small
                }

                val payload = WidgetDataHelper.loadPayload(context)
                val summary = payload?.optJSONObject("transactionsSummary")
                val lastUpdated = payload?.optString("lastUpdated")

                val views = RemoteViews(context.packageName, layoutRes)

                if (summary != null) {
                    val totalRevenue = summary.optDouble("totalRevenue", 0.0)
                    val yesterdayRevenue = summary.optDouble("yesterdayRevenue", 0.0)
                    val trials = summary.optInt("trials", 0)
                    val conversions = summary.optInt("conversions", 0)
                    val renewals = summary.optInt("renewals", 0)
                    val purchases = summary.optInt("purchases", 0)
                    val refunds = summary.optInt("refunds", 0)
                    val cancellations = summary.optInt("cancellations", 0)

                    views.setTextViewText(R.id.tvRevenue, WidgetDataHelper.formatCurrency(context, totalRevenue))
                    views.setTextViewText(R.id.tvYesterday, WidgetDataHelper.formatCompactCurrency(context, yesterdayRevenue))

                    when (layoutRes) {
                        R.layout.transactions_widget_small -> {
                            views.setTextViewText(R.id.tvPillTrials, "TRL $trials")
                            views.setTextViewText(R.id.tvPillRenewals, "RNW $renewals")
                            views.setTextViewText(R.id.tvPillRefunds, "REF $refunds")
                            views.setTextViewText(R.id.tvLastUpdated, WidgetDataHelper.lastUpdatedLabel(lastUpdated))
                        }
                        R.layout.transactions_widget_medium -> {
                            views.setTextViewText(R.id.tvTrials, trials.toString())
                            views.setTextViewText(R.id.tvConversions, conversions.toString())
                            views.setTextViewText(R.id.tvRenewals, renewals.toString())
                            views.setTextViewText(R.id.tvPurchases, purchases.toString())
                            views.setTextViewText(R.id.tvRefunds, refunds.toString())
                            views.setTextViewText(R.id.tvCancellations, cancellations.toString())
                        }
                        R.layout.transactions_widget_large -> {
                            views.setTextViewText(R.id.tvTrials, trials.toString())
                            views.setTextViewText(R.id.tvConversions, conversions.toString())
                            views.setTextViewText(R.id.tvRenewals, renewals.toString())
                            views.setTextViewText(R.id.tvPurchases, purchases.toString())
                            views.setTextViewText(R.id.tvRefunds, refunds.toString())
                            views.setTextViewText(R.id.tvCancellations, cancellations.toString())
                            views.setTextViewText(R.id.tvLastUpdated, WidgetDataHelper.lastUpdatedLabel(lastUpdated))
                        }
                    }
                } else {
                    val emptyViews = RemoteViews(context.packageName, R.layout.widget_empty_state)
                    WidgetDataHelper.addOpenAppClick(context, emptyViews)
                    appWidgetManager.updateAppWidget(appWidgetId, emptyViews)
                    return
                }

                WidgetDataHelper.addOpenAppClick(context, views)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Error updating widget $appWidgetId", e)
                try {
                    val emptyViews = RemoteViews(context.packageName, R.layout.widget_empty_state)
                    WidgetDataHelper.addOpenAppClick(context, emptyViews)
                    appWidgetManager.updateAppWidget(appWidgetId, emptyViews)
                } catch (_: Exception) {
                    // Last resort: nothing more we can do
                }
            }
        }
    }
}
