package com.revenuecat.client.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import android.widget.RemoteViews
import com.revenuecat.client.R
import org.json.JSONObject

class RevenueTabWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val TAG = "RevenueTabWidget"

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
                    maxHeight >= 200 -> R.layout.revenue_tab_widget_large
                    maxWidth >= 200 -> R.layout.revenue_tab_widget_medium
                    else -> R.layout.revenue_tab_widget_small
                }

                val payload = WidgetDataHelper.loadPayload(context)
                val tab = payload?.optJSONObject("revenueTab")
                val insights = payload?.optJSONObject("revenueInsights")
                val lastUpdated = payload?.optString("lastUpdated")

                val views = RemoteViews(context.packageName, layoutRes)

                if (tab != null) {
                    val mtdRevenue = tab.optDouble("mtdRevenue", 0.0)
                    val mtdLabel = tab.optString("mtdLabel", "")
                    val todayRevenue = tab.optDouble("todayRevenue", 0.0)
                    val yesterdayRevenue = tab.optDouble("yesterdayRevenue", 0.0)
                    val last7Revenue = tab.optDouble("last7DaysRevenue", 0.0)
                    val last30Revenue = tab.optDouble("last30DaysRevenue", 0.0)

                    views.setTextViewText(R.id.tvMtdRevenue, WidgetDataHelper.formatCurrency(context, mtdRevenue))
                    views.setTextViewText(R.id.tvMtdLabel, mtdLabel)
                    views.setTextViewText(R.id.tvToday, WidgetDataHelper.formatCompactCurrency(context, todayRevenue))
                    views.setTextViewText(R.id.tvYesterday, WidgetDataHelper.formatCompactCurrency(context, yesterdayRevenue))

                    when (layoutRes) {
                        R.layout.revenue_tab_widget_medium -> {
                            views.setTextViewText(R.id.tvLast7, WidgetDataHelper.formatCompactCurrency(context, last7Revenue))
                            views.setTextViewText(R.id.tvLast30, WidgetDataHelper.formatCompactCurrency(context, last30Revenue))
                            views.setTextViewText(R.id.tvLastUpdated, WidgetDataHelper.lastUpdatedLabel(lastUpdated))
                        }
                        R.layout.revenue_tab_widget_large -> {
                            views.setTextViewText(R.id.tvLast7, WidgetDataHelper.formatCompactCurrency(context, last7Revenue))
                            views.setTextViewText(R.id.tvLast30, WidgetDataHelper.formatCompactCurrency(context, last30Revenue))
                            views.setTextViewText(R.id.tvLastUpdated, WidgetDataHelper.lastUpdatedLabel(lastUpdated))

                            if (insights != null) {
                                val applePct = insights.optDouble("applePct", 0.0)
                                val googlePct = insights.optDouble("googlePct", 0.0)
                                val newPct = insights.optDouble("newPct", 0.0)
                                val renewalPct = insights.optDouble("renewalPct", 0.0)

                                val barHeight = 12
                                val barWidth = (maxWidth * 2).coerceAtLeast(1)

                                val platformBar = createStackedBarBitmap(barWidth, barHeight, applePct, googlePct,
                                    0xFF007AFF.toInt(), 0xFF34A853.toInt())
                                views.setImageViewBitmap(R.id.imgPlatformBar, platformBar)

                                val newRenewalBar = createStackedBarBitmap(barWidth, barHeight, newPct, renewalPct,
                                    0xFF33C7C7.toInt(), 0xFF9463E0.toInt())
                                views.setImageViewBitmap(R.id.imgNewRenewalBar, newRenewalBar)

                                views.setTextViewText(R.id.tvAppleLabel, "Apple ${applePct.toInt()}%")
                                views.setTextViewText(R.id.tvGoogleLabel, "Google ${googlePct.toInt()}%")
                                views.setTextViewText(R.id.tvNewLabel, "New ${newPct.toInt()}%")
                                views.setTextViewText(R.id.tvRenewLabel, "Renew ${renewalPct.toInt()}%")
                            }
                        }
                    }
                } else {
                    val emptyViews = RemoteViews(context.packageName, R.layout.widget_empty_state)
                    appWidgetManager.updateAppWidget(appWidgetId, emptyViews)
                    return
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Error updating widget $appWidgetId", e)
                try {
                    val emptyViews = RemoteViews(context.packageName, R.layout.widget_empty_state)
                    appWidgetManager.updateAppWidget(appWidgetId, emptyViews)
                } catch (_: Exception) {
                    // Nothing more we can do
                }
            }
        }

        private fun createStackedBarBitmap(width: Int, height: Int, pct1: Double, pct2: Double, color1: Int, color2: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val radius = (height / 2).toFloat()
            val spacing = 2f

            val totalPct = pct1 + pct2
            val w1 = if (totalPct > 0) ((width * (pct1 / 100.0)).toFloat() - spacing).coerceAtLeast(4f) else 0f
            val w2 = if (totalPct > 0) ((width * (pct2 / 100.0)).toFloat() - spacing).coerceAtLeast(4f) else 0f
            val remainder = width - w1 - w2 - spacing * 2

            var x = 0f
            if (w1 > 0) {
                paint.color = color1
                canvas.drawRoundRect(RectF(x, 0f, x + w1, height.toFloat()), radius, radius, paint)
                x += w1 + spacing
            }
            if (w2 > 0) {
                paint.color = color2
                canvas.drawRoundRect(RectF(x, 0f, x + w2, height.toFloat()), radius, radius, paint)
                x += w2 + spacing
            }
            if (remainder > 0 && totalPct < 99.5) {
                paint.color = 0x33FFFFFF
                canvas.drawRoundRect(RectF(x, 0f, x + remainder.coerceAtLeast(4f), height.toFloat()), radius, radius, paint)
            }
            return bitmap
        }
    }
}
