import SwiftUI
import WidgetKit

// MARK: - Timeline

struct InsightsTimelineEntry: TimelineEntry {
    let date: Date
    let data: RevenueInsightsData?
    let lastUpdated: String?
}

struct InsightsProvider: TimelineProvider {
    func placeholder(in context: Context) -> InsightsTimelineEntry {
        InsightsTimelineEntry(date: Date(), data: .placeholder, lastUpdated: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (InsightsTimelineEntry) -> Void) {
        let p = loadWidgetData()
        completion(InsightsTimelineEntry(date: Date(), data: p?.revenueInsights ?? .placeholder, lastUpdated: p?.lastUpdated))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<InsightsTimelineEntry>) -> Void) {
        let p = loadWidgetData()
        let entry = InsightsTimelineEntry(date: Date(), data: p?.revenueInsights, lastUpdated: p?.lastUpdated)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct RevenueInsightsWidget: Widget {
    let kind = "RevenueInsightsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InsightsProvider()) { entry in
            InsightsWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Revenue Insights")
        .description("Platform, New vs Renewals, Top Apps & Countries")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root

struct InsightsWidgetView: View {
    let entry: InsightsTimelineEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        if let data = entry.data {
            switch family {
            case .systemSmall: SmallInsightsView(data: data)
            case .systemMedium: MediumInsightsView(data: data, lastUpdated: entry.lastUpdated)
            case .systemLarge: LargeInsightsView(data: data, lastUpdated: entry.lastUpdated)
            default: MediumInsightsView(data: data, lastUpdated: entry.lastUpdated)
            }
        } else {
            InsightsEmptyView()
        }
    }
}

// MARK: - Small

struct SmallInsightsView: View {
    let data: RevenueInsightsData
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill").font(.caption2).foregroundStyle(.widgetAccent)
                Text("PLATFORM").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            PlatformBar(applePct: data.applePct, googlePct: data.googlePct)
            HStack {
                HStack(spacing: 3) {
                    Circle().fill(.appleBlue).frame(width: 6, height: 6)
                    Text("Apple \(Int(data.applePct))%").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(.googleGreen).frame(width: 6, height: 6)
                    Text("Google \(Int(data.googlePct))%").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
            }.foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text("NEW VS RENEWAL").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            NewRenewalBar(newPct: data.newPct, renewalPct: data.renewalPct)
            HStack {
                HStack(spacing: 3) {
                    Circle().fill(.newTeal).frame(width: 6, height: 6)
                    Text("New \(Int(data.newPct))%").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(.renewalPurple).frame(width: 6, height: 6)
                    Text("Renew \(Int(data.renewalPct))%").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
            }.foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium

struct MediumInsightsView: View {
    let data: RevenueInsightsData
    let lastUpdated: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill").font(.caption2).foregroundStyle(.widgetAccent)
                    Text("REVENUE INSIGHTS").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                if let u = lastUpdated {
                    Text(lastUpdatedLabel(from: u)).font(.system(size: 9, weight: .medium)).foregroundStyle(.quaternary)
                }
            }
            HStack(spacing: 12) {
                // Platform
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLATFORM").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    PlatformBar(applePct: data.applePct, googlePct: data.googlePct)
                    HStack(spacing: 8) {
                        PlatformLabel(name: "Apple", pct: data.applePct, revenue: data.appleRevenue, color: .appleBlue)
                        PlatformLabel(name: "Google", pct: data.googlePct, revenue: data.googleRevenue, color: .googleGreen)
                    }
                }
                Divider()
                // New vs Renewal
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW VS RENEWAL").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    NewRenewalBar(newPct: data.newPct, renewalPct: data.renewalPct)
                    HStack(spacing: 8) {
                        PlatformLabel(name: "New", pct: data.newPct, revenue: data.newRevenue, color: .newTeal)
                        PlatformLabel(name: "Renewal", pct: data.renewalPct, revenue: data.renewalRevenue, color: .renewalPurple)
                    }
                }
            }
        }
    }
}

// MARK: - Large

struct LargeInsightsView: View {
    let data: RevenueInsightsData
    let lastUpdated: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill").font(.subheadline).foregroundStyle(.widgetAccent)
                    Text("REVENUE INSIGHTS").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                if let u = lastUpdated {
                    Text(lastUpdatedLabel(from: u)).font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PLATFORM").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    LargePlatformBar(applePct: data.applePct, googlePct: data.googlePct)
                    HStack(spacing: 12) {
                        PlatformLabel(name: "Apple", pct: data.applePct, revenue: data.appleRevenue, color: .appleBlue)
                        PlatformLabel(name: "Google", pct: data.googlePct, revenue: data.googleRevenue, color: .googleGreen)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW VS RENEWAL").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    LargeNewRenewalBar(newPct: data.newPct, renewalPct: data.renewalPct)
                    HStack(spacing: 12) {
                        PlatformLabel(name: "New", pct: data.newPct, revenue: data.newRevenue, color: .newTeal)
                        PlatformLabel(name: "Renewal", pct: data.renewalPct, revenue: data.renewalRevenue, color: .renewalPurple)
                    }
                }
            }
            Divider().opacity(0.2)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP APPS").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    ForEach(Array(data.topApps.prefix(5).enumerated()), id: \.offset) { idx, app in
                        LargeRankedRow(rank: idx + 1, label: app.label, pct: app.pct, revenue: app.revenue, color: .widgetAccent)
                    }
                    if data.topApps.isEmpty {
                        Text("No data").font(.system(size: 12)).foregroundStyle(.quaternary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP COUNTRIES").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    ForEach(Array(data.topCountries.prefix(5).enumerated()), id: \.offset) { idx, country in
                        LargeRankedRow(rank: idx + 1, label: "\(country.flag) \(country.name)", pct: country.pct, revenue: country.revenue, color: .appleBlue)
                    }
                    if data.topCountries.isEmpty {
                        Text("No data").font(.system(size: 12)).foregroundStyle(.quaternary)
                    }
                }
            }
        }
    }
}

struct LargeRankedRow: View {
    let rank: Int; let label: String; let pct: Double; let revenue: Double; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text("\(rank)").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(color.opacity(0.6)).frame(width: 18)
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
            Spacer()
            Text(formatCompactCurrency(revenue)).font(.system(size: 11, weight: .bold, design: .rounded))
            Text("\(Int(pct))%").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Shared components

struct PlatformBar: View {
    let applePct: Double; let googlePct: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.appleBlue)
                    .frame(width: max(4, geo.size.width * CGFloat(applePct / 100)))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.googleGreen)
                    .frame(width: max(4, geo.size.width * CGFloat(googlePct / 100)))
                if applePct + googlePct < 99.5 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.secondary.opacity(0.2))
                }
            }
        }.frame(height: 8)
    }
}

struct NewRenewalBar: View {
    let newPct: Double; let renewalPct: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.newTeal)
                    .frame(width: max(4, geo.size.width * CGFloat(newPct / 100)))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.renewalPurple)
                    .frame(width: max(4, geo.size.width * CGFloat(renewalPct / 100)))
            }
        }.frame(height: 8)
    }
}

struct PlatformLabel: View {
    let name: String; let pct: Double; let revenue: Double; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(name).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(formatCompactCurrency(revenue)).font(.system(size: 10, weight: .bold, design: .rounded))
            Text("\(Int(pct))%").font(.system(size: 8, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

struct RankedRow: View {
    let rank: Int; let label: String; let pct: Double; let revenue: Double; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text("\(rank)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(color.opacity(0.6)).frame(width: 14)
            Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1)
            Spacer()
            Text(formatCompactCurrency(revenue)).font(.system(size: 9, weight: .bold, design: .rounded))
            Text("\(Int(pct))%").font(.system(size: 8, weight: .medium, design: .rounded)).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
        }
    }
}

struct InsightsEmptyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie").font(.title2).foregroundStyle(.secondary)
            Text("Open the app to sync data").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
