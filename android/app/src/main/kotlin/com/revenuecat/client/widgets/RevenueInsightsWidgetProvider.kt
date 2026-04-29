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
import org.json.JSONArray
import org.json.JSONObject

class RevenueInsightsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val TAG = "RevenueInsightsWidget"

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

                val layoutRes = when (WidgetDataHelper.widgetFamily(maxWidth, maxHeight)) {
                    WidgetDataHelper.WidgetFamily.LARGE -> R.layout.revenue_insights_widget_large
                    WidgetDataHelper.WidgetFamily.MEDIUM -> R.layout.revenue_insights_widget_medium
                    WidgetDataHelper.WidgetFamily.SMALL -> R.layout.revenue_insights_widget_small
                }

                val payload = WidgetDataHelper.loadPayload(context)
                val insights = payload?.optJSONObject("revenueInsights")
                val lastUpdated = payload?.optString("lastUpdated")

                val views = RemoteViews(context.packageName, layoutRes)

                if (insights != null) {
                    val applePct = insights.optDouble("applePct", 0.0)
                    val googlePct = insights.optDouble("googlePct", 0.0)
                    val appleRevenue = insights.optDouble("appleRevenue", 0.0)
                    val googleRevenue = insights.optDouble("googleRevenue", 0.0)
                    val newPct = insights.optDouble("newPct", 0.0)
                    val renewalPct = insights.optDouble("renewalPct", 0.0)
                    val newRevenue = insights.optDouble("newRevenue", 0.0)
                    val renewalRevenue = insights.optDouble("renewalRevenue", 0.0)

                    val barHeight = if (layoutRes == R.layout.revenue_insights_widget_large) 12 else 8
                    val barWidth = (maxWidth * 2).coerceAtLeast(1)

                    // Platform bar
                    val platformBar = createStackedBarBitmap(barWidth, barHeight, applePct, googlePct,
                        0xFF007AFF.toInt(), 0xFF34A853.toInt())
                    views.setImageViewBitmap(R.id.imgPlatformBar, platformBar)

                    // New vs Renewal bar
                    val newRenewalBar = createStackedBarBitmap(barWidth, barHeight, newPct, renewalPct,
                        0xFF33C7C7.toInt(), 0xFF9463E0.toInt())
                    views.setImageViewBitmap(R.id.imgNewRenewalBar, newRenewalBar)

                    // Labels
                    views.setTextViewText(R.id.tvAppleLabel, "Apple ${applePct.toInt()}%")
                    views.setTextViewText(R.id.tvGoogleLabel, "Google ${googlePct.toInt()}%")
                    views.setTextViewText(R.id.tvNewLabel, "New ${newPct.toInt()}%")
                    views.setTextViewText(R.id.tvRenewLabel, "Renew ${renewalPct.toInt()}%")

                    when (layoutRes) {
                        R.layout.revenue_insights_widget_medium,
                        R.layout.revenue_insights_widget_large -> {
                            views.setTextViewText(R.id.tvAppleRevenue, WidgetDataHelper.formatCompactCurrency(context, appleRevenue))
                            views.setTextViewText(R.id.tvGoogleRevenue, WidgetDataHelper.formatCompactCurrency(context, googleRevenue))
                            views.setTextViewText(R.id.tvNewRevenue, WidgetDataHelper.formatCompactCurrency(context, newRevenue))
                            views.setTextViewText(R.id.tvRenewalRevenue, WidgetDataHelper.formatCompactCurrency(context, renewalRevenue))
                            views.setTextViewText(R.id.tvApplePct, "${applePct.toInt()}%")
                            views.setTextViewText(R.id.tvGooglePct, "${googlePct.toInt()}%")
                            views.setTextViewText(R.id.tvNewPct, "${newPct.toInt()}%")
                            views.setTextViewText(R.id.tvRenewalPct, "${renewalPct.toInt()}%")
                            views.setTextViewText(R.id.tvLastUpdated, WidgetDataHelper.lastUpdatedLabel(lastUpdated))
                        }
                    }

                    // Large: Top Apps and Top Countries
                    if (layoutRes == R.layout.revenue_insights_widget_large) {
                        val topApps = insights.optJSONArray("topApps") ?: JSONArray()
                        val topCountries = insights.optJSONArray("topCountries") ?: JSONArray()

                        views.setViewVisibility(
                            R.id.tvTopAppsEmpty,
                            if (topApps.length() == 0) android.view.View.VISIBLE else android.view.View.GONE,
                        )
                        views.setViewVisibility(
                            R.id.tvTopCountriesEmpty,
                            if (topCountries.length() == 0) android.view.View.VISIBLE else android.view.View.GONE,
                        )

                        for (i in 0 until 5) {
                            val appRow = topApps.optJSONObject(i)
                            val countryRow = topCountries.optJSONObject(i)

                            val appRankId = context.resources.getIdentifier("tvAppRank${i+1}", "id", context.packageName)
                            val appNameId = context.resources.getIdentifier("tvAppName${i+1}", "id", context.packageName)
                            val appRevenueId = context.resources.getIdentifier("tvAppRevenue${i+1}", "id", context.packageName)
                            val appPctId = context.resources.getIdentifier("tvAppPct${i+1}", "id", context.packageName)
                            val appRowId = context.resources.getIdentifier("rowApp${i+1}", "id", context.packageName)

                            if (appRow != null && appRankId != 0) {
                                views.setViewVisibility(appRowId, android.view.View.VISIBLE)
                                views.setTextViewText(appRankId, "${i+1}")
                                views.setTextViewText(appNameId, appRow.optString("label", ""))
                                views.setTextViewText(appRevenueId, WidgetDataHelper.formatCompactCurrency(context, appRow.optDouble("revenue", 0.0)))
                                views.setTextViewText(appPctId, "${appRow.optDouble("pct", 0.0).toInt()}%")
                            } else if (appRowId != 0) {
                                views.setViewVisibility(appRowId, android.view.View.GONE)
                            }

                            val countryRankId = context.resources.getIdentifier("tvCountryRank${i+1}", "id", context.packageName)
                            val countryNameId = context.resources.getIdentifier("tvCountryName${i+1}", "id", context.packageName)
                            val countryRevenueId = context.resources.getIdentifier("tvCountryRevenue${i+1}", "id", context.packageName)
                            val countryPctId = context.resources.getIdentifier("tvCountryPct${i+1}", "id", context.packageName)
                            val countryRowId = context.resources.getIdentifier("rowCountry${i+1}", "id", context.packageName)

                            if (countryRow != null && countryRankId != 0) {
                                views.setViewVisibility(countryRowId, android.view.View.VISIBLE)
                                views.setTextViewText(countryRankId, "${i+1}")
                                val flag = WidgetDataHelper.flagForCountryCode(countryRow.optString("code", ""))
                                val name = countryRow.optString("name", "")
                                views.setTextViewText(countryNameId, "$flag $name")
                                views.setTextViewText(countryRevenueId, WidgetDataHelper.formatCompactCurrency(context, countryRow.optDouble("revenue", 0.0)))
                                views.setTextViewText(countryPctId, "${countryRow.optDouble("pct", 0.0).toInt()}%")
                            } else if (countryRowId != 0) {
                                views.setViewVisibility(countryRowId, android.view.View.GONE)
                            }
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
