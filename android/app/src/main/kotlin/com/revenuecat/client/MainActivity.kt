package com.revenuecat.client

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.revenuecat.client.widgets.TransactionsWidgetProvider
import com.revenuecat.client.widgets.RevenueInsightsWidgetProvider
import com.revenuecat.client.widgets.RevenueTabWidgetProvider

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.revenuecat.client/widgets"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgetData" -> {
                    try {
                        val args = call.arguments as? Map<String, Any>
                        if (args != null) {
                            val prefs = getSharedPreferences("widget_data", Context.MODE_PRIVATE)
                            val editor = prefs.edit()
                            val jsonData = JSONObject(args).toString()
                            editor.putString("widget_data_json", jsonData)
                            if (args.containsKey("currencyCode")) {
                                editor.putString("widget_currency_code", (args["currencyCode"] as String).uppercase())
                            }
                            editor.apply()
                            updateWidgets()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "Expected map argument", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to update widget data", e)
                        result.error("UPDATE_FAILED", e.message, null)
                    }
                }
                "clearWidgetData" -> {
                    try {
                        val prefs = getSharedPreferences("widget_data", Context.MODE_PRIVATE)
                        prefs.edit().clear().apply()
                        updateWidgets()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to clear widget data", e)
                        result.error("CLEAR_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun updateWidgets() {
        try {
            val appWidgetManager = AppWidgetManager.getInstance(this)

            val txComponent = ComponentName(this, TransactionsWidgetProvider::class.java)
            val txIds = appWidgetManager.getAppWidgetIds(txComponent)
            if (txIds.isNotEmpty()) {
                TransactionsWidgetProvider.updateWidgets(this, appWidgetManager, txIds)
            }

            val insightsComponent = ComponentName(this, RevenueInsightsWidgetProvider::class.java)
            val insightsIds = appWidgetManager.getAppWidgetIds(insightsComponent)
            if (insightsIds.isNotEmpty()) {
                RevenueInsightsWidgetProvider.updateWidgets(this, appWidgetManager, insightsIds)
            }

            val tabComponent = ComponentName(this, RevenueTabWidgetProvider::class.java)
            val tabIds = appWidgetManager.getAppWidgetIds(tabComponent)
            if (tabIds.isNotEmpty()) {
                RevenueTabWidgetProvider.updateWidgets(this, appWidgetManager, tabIds)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update widgets", e)
        }
    }
}
