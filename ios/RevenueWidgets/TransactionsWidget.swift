import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct TransactionsTimelineEntry: TimelineEntry {
    let date: Date
    let data: TransactionsSummaryData?
    let lastUpdated: String?
}

struct TransactionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TransactionsTimelineEntry {
        TransactionsTimelineEntry(date: Date(), data: .placeholder, lastUpdated: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TransactionsTimelineEntry) -> Void) {
        let payload = loadWidgetData()
        completion(TransactionsTimelineEntry(
            date: Date(),
            data: payload?.transactionsSummary ?? .placeholder,
            lastUpdated: payload?.lastUpdated
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TransactionsTimelineEntry>) -> Void) {
        let payload = loadWidgetData()
        let entry = TransactionsTimelineEntry(date: Date(), data: payload?.transactionsSummary, lastUpdated: payload?.lastUpdated)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct TransactionsWidget: Widget {
    let kind = "TransactionsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TransactionsProvider()) { entry in
            TransactionsWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Transactions")
        .description("Today's revenue and transaction summary")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root View

struct TransactionsWidgetView: View {
    let entry: TransactionsTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let data = entry.data {
            switch family {
            case .systemSmall: SmallTxView(data: data, lastUpdated: entry.lastUpdated)
            case .systemMedium: MediumTxView(data: data, lastUpdated: entry.lastUpdated)
            case .systemLarge: LargeTxView(data: data, lastUpdated: entry.lastUpdated)
            default: MediumTxView(data: data, lastUpdated: entry.lastUpdated)
            }
        } else {
            EmptyStateView(message: "Open the app to sync data")
        }
    }
}

// MARK: - Small

struct SmallTxView: View {
    let data: TransactionsSummaryData
    let lastUpdated: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.caption2).foregroundStyle(.widgetAccent)
                Text("TODAY").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(formatCurrency(data.totalRevenue))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 2)
            HStack(spacing: 4) {
                Text("Yesterday").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(formatCompactCurrency(data.yesterdayRevenue))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                MiniPill(label: "TRL", count: data.trials, color: .trialOrange)
                MiniPill(label: "RNW", count: data.renewals, color: .widgetAccent)
                MiniPill(label: "REF", count: data.refunds, color: .refundRed)
            }
            if let u = lastUpdated {
                Text(lastUpdatedLabel(from: u)).font(.system(size: 8, weight: .medium)).foregroundStyle(.quaternary)
            }
        }
    }
}

struct MiniPill: View {
    let label: String; let count: Int; let color: Color
    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(color.opacity(0.8))
            Text("\(count)").font(.system(size: 9, weight: .heavy, design: .rounded))
        }
    }
}

// MARK: - Medium

struct MediumTxView: View {
    let data: TransactionsSummaryData
    let lastUpdated: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill").font(.caption2).foregroundStyle(.widgetAccent)
                        Text("TODAY'S REVENUE").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(formatCurrency(data.totalRevenue))
                        .font(.system(size: 24, weight: .heavy, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("YESTERDAY").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text(formatCompactCurrency(data.yesterdayRevenue))
                        .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.primary.opacity(0.8))
                }
            }
            HStack(spacing: 6) {
                TxCountCell(label: "Trials", count: data.trials, color: .trialOrange, icon: "sparkles")
                TxCountCell(label: "Conversions", count: data.conversions, color: .conversionGreen, icon: "arrow.up.right")
                TxCountCell(label: "Renewals", count: data.renewals, color: .widgetAccent, icon: "arrow.clockwise")
            }
            HStack(spacing: 6) {
                TxCountCell(label: "Purchases", count: data.purchases, color: .appleBlue, icon: "bag.fill")
                TxCountCell(label: "Refunds", count: data.refunds, color: .refundRed, icon: "arrow.uturn.backward")
                TxCountCell(label: "Cancels", count: data.cancellations, color: .red.opacity(0.7), icon: "xmark.circle")
            }
        }
    }
}

struct TxCountCell: View {
    let label: String; let count: Int; let color: Color; let icon: String
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                Text("\(count)").font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            Text(label).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Large

struct LargeTxView: View {
    let data: TransactionsSummaryData
    let lastUpdated: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.title3).foregroundStyle(.widgetAccent)
                Text("TRANSACTIONS TODAY").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                if let u = lastUpdated {
                    Text(lastUpdatedLabel(from: u)).font(.system(size: 10, weight: .medium)).foregroundStyle(.quaternary)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text(formatCurrency(data.totalRevenue))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.widgetAccent).minimumScaleFactor(0.6).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("YESTERDAY").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text(formatCurrency(data.yesterdayRevenue))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary).minimumScaleFactor(0.6).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                BigCountCell(label: "Trials", count: data.trials, color: .trialOrange, icon: "sparkles")
                BigCountCell(label: "Conversions", count: data.conversions, color: .conversionGreen, icon: "arrow.up.right")
                BigCountCell(label: "Renewals", count: data.renewals, color: .widgetAccent, icon: "arrow.clockwise")
            }
            HStack(spacing: 10) {
                BigCountCell(label: "Purchases", count: data.purchases, color: .appleBlue, icon: "bag.fill")
                BigCountCell(label: "Refunds", count: data.refunds, color: .refundRed, icon: "arrow.uturn.backward")
                BigCountCell(label: "Cancellations", count: data.cancellations, color: .red.opacity(0.7), icon: "xmark.circle")
            }
        }
    }
}

struct BigCountCell: View {
    let label: String; let count: Int; let color: Color; let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(color)
            Text("\(count)").font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(.secondary)
            Text(message).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
