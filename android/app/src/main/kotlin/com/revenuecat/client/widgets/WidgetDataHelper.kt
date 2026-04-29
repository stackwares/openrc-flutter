package com.revenuecat.client.widgets

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

object WidgetDataHelper {
    private const val PREFS_NAME = "widget_data"
    private const val KEY_DATA = "widget_data_json"
    private const val KEY_CURRENCY = "widget_currency_code"

    fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun loadPayload(context: Context): JSONObject? {
        val json = getPrefs(context).getString(KEY_DATA, null) ?: return null
        return try {
            JSONObject(json)
        } catch (_: Exception) {
            null
        }
    }

    fun currencyCode(context: Context): String {
        return getPrefs(context).getString(KEY_CURRENCY, "USD")?.uppercase() ?: "USD"
    }

    fun formatCurrency(context: Context, value: Double): String {
        val code = currencyCode(context)
        val sym = currencySymbol(code)
        val minorUnits = if (code in setOf("BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF")) 0 else 2
        return if (value >= 1000) {
            String.format("$sym%,.0f", value)
        } else {
            String.format("$sym%,.${minorUnits}f", value)
        }
    }

    fun formatCompactCurrency(context: Context, value: Double): String {
        val code = currencyCode(context)
        val sym = currencySymbol(code)
        return when {
            kotlin.math.abs(value) >= 1_000_000 -> String.format("$sym%.1fM", value / 1_000_000)
            kotlin.math.abs(value) >= 10_000 -> String.format("$sym%.1fK", value / 1_000)
            kotlin.math.abs(value) >= 1_000 -> String.format("$sym%.0f", value)
            else -> {
                val minorUnits = if (code in setOf("BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF")) 0 else 2
                String.format("$sym%,.${minorUnits}f", value)
            }
        }
    }

    private fun currencySymbol(code: String): String {
        return when (code.uppercase()) {
            "USD" -> "$"
            "EUR" -> "€"
            "GBP" -> "£"
            "JPY" -> "¥"
            "KRW" -> "₩"
            "CNY" -> "¥"
            "BRL" -> "R$"
            "AUD" -> "A$"
            "CAD" -> "C$"
            "MXN" -> "MX$"
            "SEK" -> "kr"
            "PLN" -> "zł"
            else -> code
        }
    }

    fun lastUpdatedLabel(isoString: String?): String {
        if (isoString.isNullOrEmpty()) return "Not synced"
        val formatter = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
        formatter.timeZone = java.util.TimeZone.getTimeZone("UTC")
        val date = try {
            formatter.parse(isoString)
        } catch (_: Exception) {
            try {
                java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }.parse(isoString)
            } catch (_: Exception) {
                return "Not synced"
            }
        } ?: return "Not synced"
        val elapsed = (System.currentTimeMillis() - date.time) / 1000
        return when {
            elapsed < 60 -> "Just now"
            elapsed < 3600 -> "${elapsed / 60}m ago"
            elapsed < 86400 -> "${elapsed / 3600}h ago"
            else -> "${elapsed / 86400}d ago"
        }
    }

    fun flagForCountryCode(code: String): String {
        if (code == "__") return "🌍"
        if (code.length != 2) return "🏳️"
        val upper = code.uppercase()
        return upper.map { c ->
            val codePoint = 0x1F1E6 + (c.code - 'A'.code)
            Character.toChars(codePoint).toList()
        }.flatten().toCharArray().concatToString()
    }
}