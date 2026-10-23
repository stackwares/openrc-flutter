package com.openrc.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.util.Log
import com.openrc.app.widgets.RevenueInsightsLargeWidgetProvider
import com.openrc.app.widgets.RevenueInsightsSmallWidgetProvider
import com.openrc.app.widgets.RevenueInsightsWidgetProvider
import com.openrc.app.widgets.RevenueInsightsWidgetUpdater
import com.openrc.app.widgets.RevenueTabLargeWidgetProvider
import com.openrc.app.widgets.RevenueTabSmallWidgetProvider
import com.openrc.app.widgets.RevenueTabWidgetProvider
import com.openrc.app.widgets.RevenueTabWidgetUpdater
import com.openrc.app.widgets.TransactionsLargeWidgetProvider
import com.openrc.app.widgets.TransactionsSmallWidgetProvider
import com.openrc.app.widgets.TransactionsWidgetProvider
import com.openrc.app.widgets.TransactionsWidgetUpdater
import com.openrc.app.widgets.WidgetDataHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.openrc.app/widgets"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgetData" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
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

            updateProvider(appWidgetManager, TransactionsSmallWidgetProvider::class.java) { ids ->
                TransactionsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.SMALL)
            }
            updateProvider(appWidgetManager, TransactionsWidgetProvider::class.java) { ids ->
                TransactionsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.MEDIUM)
            }
            updateProvider(appWidgetManager, TransactionsLargeWidgetProvider::class.java) { ids ->
                TransactionsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.LARGE)
            }

            updateProvider(appWidgetManager, RevenueInsightsSmallWidgetProvider::class.java) { ids ->
                RevenueInsightsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.SMALL)
            }
            updateProvider(appWidgetManager, RevenueInsightsWidgetProvider::class.java) { ids ->
                RevenueInsightsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.MEDIUM)
            }
            updateProvider(appWidgetManager, RevenueInsightsLargeWidgetProvider::class.java) { ids ->
                RevenueInsightsWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.LARGE)
            }

            updateProvider(appWidgetManager, RevenueTabSmallWidgetProvider::class.java) { ids ->
                RevenueTabWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.SMALL)
            }
            updateProvider(appWidgetManager, RevenueTabWidgetProvider::class.java) { ids ->
                RevenueTabWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.MEDIUM)
            }
            updateProvider(appWidgetManager, RevenueTabLargeWidgetProvider::class.java) { ids ->
                RevenueTabWidgetUpdater.updateWidgets(this, appWidgetManager, ids, WidgetDataHelper.WidgetFamily.LARGE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update widgets", e)
        }
    }

    private fun updateProvider(
        appWidgetManager: AppWidgetManager,
        providerClass: Class<out AppWidgetProvider>,
        update: (IntArray) -> Unit,
    ) {
        val ids = appWidgetManager.getAppWidgetIds(ComponentName(this, providerClass))
        if (ids.isNotEmpty()) {
            update(ids)
        }
    }
}
