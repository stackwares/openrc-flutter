import SwiftUI
import WidgetKit

// MARK: - Timeline

struct RevenueTabTimelineEntry: TimelineEntry {
    let date: Date
    let tab: RevenueTabData?
    let insights: RevenueInsightsData?
    let lastUpdated: String?
}

struct RevenueTabProvider: TimelineProvider {
    func placeholder(in context: Context) -> RevenueTabTimelineEntry {
        RevenueTabTimelineEntry(date: Date(), tab: .placeholder, insights: .placeholder, lastUpdated: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (RevenueTabTimelineEntry) -> Void) {
        let p = loadWidgetData()
        completion(RevenueTabTimelineEntry(date: Date(), tab: p?.revenueTab ?? .placeholder, insights: p?.revenueInsights ?? .placeholder, lastUpdated: p?.lastUpdated))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RevenueTabTimelineEntry>) -> Void) {
        let p = loadWidgetData()
        let entry = RevenueTabTimelineEntry(date: Date(), tab: p?.revenueTab, insights: p?.revenueInsights, lastUpdated: p?.lastUpdated)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct RevenueTabWidget: Widget {
    let kind = "RevenueTabWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RevenueTabProvider()) { entry in
            RevenueTabWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Revenue")
        .description("Month-to-date revenue dashboard")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root

struct RevenueTabWidgetView: View {
    let entry: RevenueTabTimelineEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        if let tab = entry.tab {
            switch family {
            case .systemSmall: SmallRevenueTabView(tab: tab)
            case .systemMedium: MediumRevenueTabView(tab: tab, lastUpdated: entry.lastUpdated)
            case .systemLarge: LargeRevenueTabView(tab: tab, insights: entry.insights, lastUpdated: entry.lastUpdated)
            default: MediumRevenueTabView(tab: tab, lastUpdated: entry.lastUpdated)
            }
        } else {
            RevTabEmptyView()
        }
    }
}

// MARK: - Small

struct SmallRevenueTabView: View {
    let tab: RevenueTabData
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundStyle(.widgetAccent)
                Text("MTD REVENUE").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(formatCurrency(tab.mtdRevenue))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(tab.mtdLabel).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(formatCompactCurrency(tab.todayRevenue)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.widgetAccent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Yesterday").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(formatCompactCurrency(tab.yesterdayRevenue)).font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

// MARK: - Medium

struct MediumRevenueTabView: View {
    let tab: RevenueTabData
    let lastUpdated: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundStyle(.widgetAccent)
                        Text("MONTH-TO-DATE").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(formatCurrency(tab.mtdRevenue))
                        .font(.system(size: 24, weight: .heavy, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text(tab.mtdLabel).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                if let u = lastUpdated {
                    Text(lastUpdatedLabel(from: u)).font(.system(size: 9, weight: .medium)).foregroundStyle(.quaternary)
                }
            }
            HStack(spacing: 6) {
                PeriodCard(label: "Today", value: tab.todayRevenue, color: .widgetAccent)
                PeriodCard(label: "Yesterday", value: tab.yesterdayRevenue, color: .primary)
                PeriodCard(label: "7 Days", value: tab.last7DaysRevenue, color: .appleBlue)
                PeriodCard(label: "30 Days", value: tab.last30DaysRevenue, color: .renewalPurple)
            }
        }
    }
}

struct PeriodCard: View {
    let label: String; let value: Double; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(formatCompactCurrency(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Large

struct LargeRevenueTabView: View {
    let tab: RevenueTabData
    let insights: RevenueInsightsData?
    let lastUpdated: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.title3).foregroundStyle(.widgetAccent)
                Text("REVENUE DASHBOARD").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                if let u = lastUpdated {
                    Text(lastUpdatedLabel(from: u)).font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(formatCurrency(tab.mtdRevenue))
                    .font(.system(size: 38, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text(tab.mtdLabel).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                LargePeriodCard(label: "Today", value: tab.todayRevenue, color: .widgetAccent)
                LargePeriodCard(label: "Yesterday", value: tab.yesterdayRevenue, color: .primary)
                LargePeriodCard(label: "7 Days", value: tab.last7DaysRevenue, color: .appleBlue)
                LargePeriodCard(label: "30 Days", value: tab.last30DaysRevenue, color: .renewalPurple)
            }

            if let insights = insights {
                Divider().opacity(0.2)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PLATFORM").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        LargePlatformBar(applePct: insights.applePct, googlePct: insights.googlePct)
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Circle().fill(.appleBlue).frame(width: 6, height: 6)
                                Text("Apple \(Int(insights.applePct))%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.googleGreen).frame(width: 6, height: 6)
                                Text("Google \(Int(insights.googlePct))%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEW VS RENEWAL").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        LargeNewRenewalBar(newPct: insights.newPct, renewalPct: insights.renewalPct)
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Circle().fill(.newTeal).frame(width: 6, height: 6)
                                Text("New \(Int(insights.newPct))%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.renewalPurple).frame(width: 6, height: 6)
                                Text("Renew \(Int(insights.renewalPct))%").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LargePeriodCard: View {
    let label: String; let value: Double; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(formatCompactCurrency(value))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RevTabEmptyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle").font(.title2).foregroundStyle(.secondary)
            Text("Open the app to sync data").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
