package com.openrc.app.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews
import com.openrc.app.R

class TransactionsSmallWidgetProvider : TransactionsWidgetProviderBase(WidgetDataHelper.WidgetFamily.SMALL, "TransactionsSmallWidget")
class TransactionsWidgetProvider : TransactionsWidgetProviderBase(WidgetDataHelper.WidgetFamily.MEDIUM, "TransactionsWidget")
class TransactionsLargeWidgetProvider : TransactionsWidgetProviderBase(WidgetDataHelper.WidgetFamily.LARGE, "TransactionsLargeWidget")

abstract class TransactionsWidgetProviderBase(
    private val family: WidgetDataHelper.WidgetFamily,
    private val tag: String,
) : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        TransactionsWidgetUpdater.updateWidgets(context, appWidgetManager, appWidgetIds, family, tag)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        TransactionsWidgetUpdater.updateWidgets(context, appWidgetManager, intArrayOf(appWidgetId), family, tag)
    }
}

object TransactionsWidgetUpdater {
    fun updateWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        family: WidgetDataHelper.WidgetFamily = WidgetDataHelper.WidgetFamily.MEDIUM,
        tag: String = "TransactionsWidget",
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, family, tag)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        family: WidgetDataHelper.WidgetFamily,
        tag: String,
    ) {
        try {
            val layoutRes = when (family) {
                WidgetDataHelper.WidgetFamily.LARGE -> R.layout.transactions_widget_large
                WidgetDataHelper.WidgetFamily.MEDIUM -> R.layout.transactions_widget_medium
                WidgetDataHelper.WidgetFamily.SMALL -> R.layout.transactions_widget_small
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
            Log.e(tag, "Error updating widget $appWidgetId", e)
            try {
                val emptyViews = RemoteViews(context.packageName, R.layout.widget_empty_state)
                WidgetDataHelper.addOpenAppClick(context, emptyViews)
                appWidgetManager.updateAppWidget(appWidgetId, emptyViews)
            } catch (_: Exception) {
                // Last resort: nothing more we can do.
            }
        }
    }
}
