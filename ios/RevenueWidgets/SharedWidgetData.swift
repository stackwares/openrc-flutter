import Foundation
import SwiftUI
import WidgetKit

// MARK: - App Group

let appGroupID = "group.com.revenuecat.client.widgets"
let widgetDataKey = "widget_data_json"

// MARK: - Codable models matching Flutter payload

struct WidgetDataPayload: Codable {
    let lastUpdated: String?
    let transactionsSummary: TransactionsSummaryData?
    let revenueInsights: RevenueInsightsData?
    let revenueTab: RevenueTabData?
}

struct TransactionsSummaryData: Codable {
    let totalRevenue: Double
    let yesterdayRevenue: Double
    let trials: Int
    let conversions: Int
    let renewals: Int
    let purchases: Int
    let refunds: Int
    let cancellations: Int

    static let placeholder = TransactionsSummaryData(
        totalRevenue: 1234.56,
        yesterdayRevenue: 890.12,
        trials: 42,
        conversions: 18,
        renewals: 156,
        purchases: 23,
        refunds: 3,
        cancellations: 7
    )
}

struct RevenueInsightsData: Codable {
    let applePct: Double
    let googlePct: Double
    let appleRevenue: Double
    let googleRevenue: Double
    let newPct: Double
    let renewalPct: Double
    let newRevenue: Double
    let renewalRevenue: Double
    let topApps: [TopAppEntry]
    let topCountries: [TopCountryEntry]

    static let placeholder = RevenueInsightsData(
        applePct: 65.3,
        googlePct: 34.7,
        appleRevenue: 8130.00,
        googleRevenue: 4320.50,
        newPct: 28.5,
        renewalPct: 71.5,
        newRevenue: 3548.39,
        renewalRevenue: 8902.11,
        topApps: [
            TopAppEntry(label: "MyApp Pro", pct: 45.2, revenue: 5627.43),
            TopAppEntry(label: "Widget Hub", pct: 30.1, revenue: 3748.22),
            TopAppEntry(label: "Lite Version", pct: 24.7, revenue: 3074.85),
        ],
        topCountries: [
            TopCountryEntry(code: "US", name: "United States", pct: 38.1, revenue: 4743.50),
            TopCountryEntry(code: "GB", name: "United Kingdom", pct: 15.2, revenue: 1892.48),
            TopCountryEntry(code: "DE", name: "Germany", pct: 12.8, revenue: 1593.67),
        ]
    )
}

struct TopAppEntry: Codable {
    let label: String
    let pct: Double
    let revenue: Double
}

struct TopCountryEntry: Codable {
    let code: String
    let name: String
    let pct: Double
    let revenue: Double

    var flag: String {
        if code == "__" { return "🌍" }
        guard code.count == 2 else { return "🏳️" }
        return String(code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }.map { Character($0) })
    }
}

struct RevenueTabData: Codable {
    let mtdRevenue: Double
    let mtdLabel: String
    let todayRevenue: Double
    let yesterdayRevenue: Double
    let last7DaysRevenue: Double
    let last30DaysRevenue: Double

    static let placeholder = RevenueTabData(
        mtdRevenue: 12450.50,
        mtdLabel: "This month · local",
        todayRevenue: 950.75,
        yesterdayRevenue: 850.25,
        last7DaysRevenue: 5200.00,
        last30DaysRevenue: 18500.00
    )
}

// MARK: - Shared data reading

func loadWidgetData() -> WidgetDataPayload? {
    guard let defaults = UserDefaults(suiteName: appGroupID),
          let jsonString = defaults.string(forKey: widgetDataKey),
          let data = jsonString.data(using: .utf8)
    else {
        return nil
    }
    return try? JSONDecoder().decode(WidgetDataPayload.self, from: data)
}

// MARK: - Currency helpers

let currencyKey = "widget_currency_code"

func currentWidgetCurrencyCode() -> String {
    let defaults = UserDefaults(suiteName: appGroupID)
    return defaults?.string(forKey: currencyKey)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "USD"
}

let widgetCurrencySymbols: [String: String] = [
    "AED": "د.إ", "AFN": "؋", "ALL": "L", "AMD": "֏", "ANG": "ƒ",
    "AOA": "Kz", "ARS": "$", "AUD": "$", "AWG": "ƒ", "AZN": "₼",
    "BAM": "KM", "BBD": "$", "BDT": "৳", "BGN": "лв", "BHD": ".د.ب",
    "BIF": "FBu", "BMD": "$", "BND": "$", "BOB": "Bs.", "BRL": "R$",
    "BSD": "$", "BTN": "Nu.", "BWP": "P", "BYN": "Br", "BZD": "$",
    "CAD": "$", "CDF": "FC", "CHF": "CHF", "CLP": "$", "CNY": "¥",
    "COP": "$", "CRC": "₡", "CUP": "$", "CVE": "$", "CZK": "Kč",
    "DJF": "Fdj", "DKK": "kr", "DOP": "$", "DZD": "د.ج", "EGP": "£",
    "ERN": "Nfk", "ETB": "Br", "EUR": "€", "FJD": "$", "FKP": "£",
    "GBP": "£", "GEL": "₾", "GHS": "₵", "GIP": "£", "GMD": "D",
    "GNF": "FG", "GTQ": "Q", "GYD": "$", "HKD": "$", "HNL": "L",
    "HTG": "G", "HUF": "Ft", "IDR": "Rp", "ILS": "₪", "INR": "₹",
    "IQD": "ع.د", "IRR": "﷼", "ISK": "kr", "JMD": "$", "JOD": "د.ا",
    "JPY": "¥", "KES": "KSh", "KGS": "с", "KHR": "៛", "KMF": "CF",
    "KPW": "₩", "KRW": "₩", "KWD": "د.ك", "KYD": "$", "KZT": "₸",
    "LAK": "₭", "LBP": "ل.ل", "LKR": "Rs", "LRD": "$", "LSL": "L",
    "LYD": "ل.د", "MAD": "د.م.", "MDL": "L", "MGA": "Ar", "MKD": "ден",
    "MMK": "K", "MNT": "₮", "MOP": "MOP$", "MRU": "UM", "MUR": "₨",
    "MVR": "Rf", "MWK": "MK", "MXN": "$", "MYR": "RM", "MZN": "MT",
    "NAD": "$", "NGN": "₦", "NIO": "C$", "NOK": "kr", "NPR": "₨",
    "NZD": "$", "OMR": "ر.ع.", "PAB": "B/.", "PEN": "S/", "PGK": "K",
    "PHP": "₱", "PKR": "₨", "PLN": "zł", "PYG": "₲", "QAR": "ر.ق",
    "RON": "lei", "RSD": "дин", "RUB": "₽", "RWF": "FRw", "SAR": "﷼",
    "SBD": "$", "SCR": "₨", "SDG": "ج.س.", "SEK": "kr", "SGD": "$",
    "SHP": "£", "SLE": "Le", "SOS": "Sh", "SRD": "$", "SSP": "£",
    "STN": "Db", "SYP": "£", "SZL": "L", "THB": "฿", "TJS": "ЅМ",
    "TMT": "m", "TND": "د.ت", "TOP": "T$", "TRY": "₺", "TTD": "$",
    "TWD": "$", "TZS": "TSh", "UAH": "₴", "UGX": "USh", "USD": "$",
    "UYU": "$", "UZS": "so'm", "VES": "Bs.", "VND": "₫", "VUV": "VT",
    "WST": "T", "XAF": "FCFA", "XCD": "$", "XOF": "CFA", "XPF": "₣",
    "YER": "﷼", "ZAR": "R", "ZMW": "ZK", "ZWL": "$", "US": "$",
]

func currencySymbol(for code: String) -> String {
    widgetCurrencySymbols[code.uppercased()] ?? "¤"
}

func widgetCurrencyMinorUnits(_ code: String) -> Int {
    switch code.uppercased() {
    case "BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF":
        return 0
    default:
        return 2
    }
}

// MARK: - Common helpers

func formatWidgetNumber(_ value: Double, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = fractionDigits
    formatter.minimumFractionDigits = fractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
}

func formatCurrency(_ value: Double) -> String {
    let code = currentWidgetCurrencyCode()
    let minorUnits = widgetCurrencyMinorUnits(code)
    let sym = currencySymbol(for: code)
    if value >= 1000 {
        return "\(sym)\(formatWidgetNumber(value, fractionDigits: 0))"
    } else {
        return "\(sym)\(formatWidgetNumber(value, fractionDigits: minorUnits))"
    }
}

func formatCompactCurrency(_ value: Double) -> String {
    let code = currentWidgetCurrencyCode()
    let sym = currencySymbol(for: code)
    if abs(value) >= 1_000_000 {
        return String(format: "\(sym)%.1fM", value / 1_000_000)
    } else if abs(value) >= 10_000 {
        return String(format: "\(sym)%.1fK", value / 1_000)
    } else if abs(value) >= 1_000 {
        return String(format: "\(sym)%.0f", value)
    } else {
        let minorUnits = widgetCurrencyMinorUnits(code)
        return "\(sym)\(formatWidgetNumber(value, fractionDigits: minorUnits))"
    }
}

/// Elapsed time since last update, for display.
func lastUpdatedLabel(from isoString: String?) -> String {
    guard let s = isoString else { return "Not synced" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: s) else {
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        guard let d = formatter.date(from: s) else { return "Not synced" }
        return _relativeLabel(d)
    }
    return _relativeLabel(date)
}

private func _relativeLabel(_ date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    if elapsed < 60 { return "Just now" }
    if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
    if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
    return "\(Int(elapsed / 86400))d ago"
}

// MARK: - Large shared components

struct LargePlatformBar: View {
    let applePct: Double; let googlePct: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.appleBlue)
                    .frame(width: max(4, geo.size.width * CGFloat(applePct / 100)))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.googleGreen)
                    .frame(width: max(4, geo.size.width * CGFloat(googlePct / 100)))
                if applePct + googlePct < 99.5 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.secondary.opacity(0.2))
                }
            }
        }.frame(height: 12)
    }
}

struct LargeNewRenewalBar: View {
    let newPct: Double; let renewalPct: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.newTeal)
                    .frame(width: max(4, geo.size.width * CGFloat(newPct / 100)))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.renewalPurple)
                    .frame(width: max(4, geo.size.width * CGFloat(renewalPct / 100)))
            }
        }.frame(height: 12)
    }
}

// MARK: - Common widget colors

extension Color {
    static let widgetBackground = Color(red: 0.07, green: 0.07, blue: 0.12)
    static let widgetCardBackground = Color(red: 0.12, green: 0.12, blue: 0.18)
    static let widgetAccent = Color(red: 0.30, green: 0.85, blue: 0.65)
    static let appleBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let googleGreen = Color(red: 0.20, green: 0.66, blue: 0.33)
    static let renewalPurple = Color(red: 0.58, green: 0.39, blue: 0.88)
    static let newTeal = Color(red: 0.20, green: 0.78, blue: 0.78)
    static let trialOrange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let refundRed = Color(red: 0.93, green: 0.26, blue: 0.26)
    static let conversionGreen = Color(red: 0.30, green: 0.85, blue: 0.40)
}

extension ShapeStyle where Self == Color {
    static var widgetBackground: Color { Color.widgetBackground }
    static var widgetCardBackground: Color { Color.widgetCardBackground }
    static var widgetAccent: Color { Color.widgetAccent }
    static var appleBlue: Color { Color.appleBlue }
    static var googleGreen: Color { Color.googleGreen }
    static var renewalPurple: Color { Color.renewalPurple }
    static var newTeal: Color { Color.newTeal }
    static var trialOrange: Color { Color.trialOrange }
    static var refundRed: Color { Color.refundRed }
    static var conversionGreen: Color { Color.conversionGreen }
}
