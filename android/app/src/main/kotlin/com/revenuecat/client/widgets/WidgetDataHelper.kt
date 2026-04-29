package com.revenuecat.client.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.revenuecat.client.MainActivity
import com.revenuecat.client.R
import org.json.JSONObject

object WidgetDataHelper {
    private const val PREFS_NAME = "widget_data"
    private const val KEY_DATA = "widget_data_json"
    private const val KEY_CURRENCY = "widget_currency_code"
    private const val REQUEST_OPEN_APP = 7001
    private const val MEDIUM_MIN_WIDTH_DP = 200
    private const val LARGE_MIN_WIDTH_DP = 300
    private const val LARGE_MIN_HEIGHT_DP = 220

    enum class WidgetFamily {
        SMALL,
        MEDIUM,
        LARGE,
    }

    fun widgetFamily(maxWidthDp: Int, maxHeightDp: Int): WidgetFamily {
        return when {
            maxWidthDp >= LARGE_MIN_WIDTH_DP && maxHeightDp >= LARGE_MIN_HEIGHT_DP -> WidgetFamily.LARGE
            maxWidthDp >= MEDIUM_MIN_WIDTH_DP -> WidgetFamily.MEDIUM
            else -> WidgetFamily.SMALL
        }
    }

    fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun addOpenAppClick(context: Context, views: RemoteViews) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_OPEN_APP,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widgetRoot, pendingIntent)
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
            kotlin.math.abs(value) >= 1_000 -> String.format("$sym%,.0f", value)
            else -> {
                val minorUnits = if (code in setOf("BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF")) 0 else 2
                String.format("$sym%,.${minorUnits}f", value)
            }
        }
    }

    private fun currencySymbol(code: String): String {
        return when (code.uppercase()) {
            "AED" -> "د.إ"
            "AFN" -> "؋"
            "ALL" -> "L"
            "AMD" -> "֏"
            "ANG" -> "ƒ"
            "AOA" -> "Kz"
            "ARS" -> "$"
            "AWG" -> "ƒ"
            "AZN" -> "₼"
            "BAM" -> "KM"
            "BBD" -> "$"
            "BDT" -> "৳"
            "BGN" -> "лв"
            "BHD" -> ".د.ب"
            "BIF" -> "FBu"
            "BMD" -> "$"
            "BND" -> "$"
            "BOB" -> "Bs."
            "BSD" -> "$"
            "BTN" -> "Nu."
            "BWP" -> "P"
            "BYN" -> "Br"
            "BZD" -> "$"
            "USD" -> "$"
            "EUR" -> "€"
            "GBP" -> "£"
            "JPY" -> "¥"
            "KRW" -> "₩"
            "CNY" -> "¥"
            "BRL" -> "R$"
            "AUD" -> "$"
            "CAD" -> "$"
            "CDF" -> "FC"
            "CHF" -> "CHF"
            "CLP" -> "$"
            "COP" -> "$"
            "CRC" -> "₡"
            "CUP" -> "$"
            "CVE" -> "$"
            "CZK" -> "Kč"
            "DJF" -> "Fdj"
            "DKK" -> "kr"
            "DOP" -> "$"
            "DZD" -> "د.ج"
            "EGP" -> "£"
            "ERN" -> "Nfk"
            "ETB" -> "Br"
            "FJD" -> "$"
            "FKP" -> "£"
            "GEL" -> "₾"
            "GHS" -> "₵"
            "GIP" -> "£"
            "GMD" -> "D"
            "GNF" -> "FG"
            "GTQ" -> "Q"
            "GYD" -> "$"
            "HKD" -> "$"
            "HNL" -> "L"
            "HTG" -> "G"
            "HUF" -> "Ft"
            "IDR" -> "Rp"
            "ILS" -> "₪"
            "INR" -> "₹"
            "IQD" -> "ع.د"
            "IRR" -> "﷼"
            "ISK" -> "kr"
            "JMD" -> "$"
            "JOD" -> "د.ا"
            "KES" -> "KSh"
            "KGS" -> "с"
            "KHR" -> "៛"
            "KMF" -> "CF"
            "KPW" -> "₩"
            "KWD" -> "د.ك"
            "KYD" -> "$"
            "KZT" -> "₸"
            "LAK" -> "₭"
            "LBP" -> "ل.ل"
            "LKR" -> "Rs"
            "LRD" -> "$"
            "LSL" -> "L"
            "LYD" -> "ل.د"
            "MAD" -> "د.م."
            "MDL" -> "L"
            "MGA" -> "Ar"
            "MKD" -> "ден"
            "MMK" -> "K"
            "MNT" -> "₮"
            "MOP" -> "MOP$"
            "MRU" -> "UM"
            "MUR" -> "₨"
            "MVR" -> "Rf"
            "MWK" -> "MK"
            "MXN" -> "$"
            "MYR" -> "RM"
            "MZN" -> "MT"
            "NAD" -> "$"
            "NGN" -> "₦"
            "NIO" -> "C$"
            "NOK" -> "kr"
            "NPR" -> "₨"
            "NZD" -> "$"
            "OMR" -> "ر.ع."
            "PAB" -> "B/."
            "PEN" -> "S/"
            "PGK" -> "K"
            "PHP" -> "₱"
            "PKR" -> "₨"
            "SEK" -> "kr"
            "PLN" -> "zł"
            "PYG" -> "₲"
            "QAR" -> "ر.ق"
            "RON" -> "lei"
            "RSD" -> "дин"
            "RUB" -> "₽"
            "RWF" -> "FRw"
            "SAR" -> "﷼"
            "SBD" -> "$"
            "SCR" -> "₨"
            "SDG" -> "ج.س."
            "SGD" -> "$"
            "SHP" -> "£"
            "SLE" -> "Le"
            "SOS" -> "Sh"
            "SRD" -> "$"
            "SSP" -> "£"
            "STN" -> "Db"
            "SYP" -> "£"
            "SZL" -> "L"
            "THB" -> "฿"
            "TJS" -> "ЅМ"
            "TMT" -> "m"
            "TND" -> "د.ت"
            "TOP" -> "T$"
            "TRY" -> "₺"
            "TTD" -> "$"
            "TWD" -> "$"
            "TZS" -> "TSh"
            "UAH" -> "₴"
            "UGX" -> "USh"
            "UYU" -> "$"
            "UZS" -> "so'm"
            "VES" -> "Bs."
            "VND" -> "₫"
            "VUV" -> "VT"
            "WST" -> "T"
            "XAF" -> "FCFA"
            "XCD" -> "$"
            "XOF" -> "CFA"
            "XPF" -> "₣"
            "YER" -> "﷼"
            "ZAR" -> "R"
            "ZMW" -> "ZK"
            "ZWL" -> "$"
            "US" -> "$"
            else -> "¤"
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
