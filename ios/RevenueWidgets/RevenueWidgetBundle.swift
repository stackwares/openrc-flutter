import SwiftUI
import WidgetKit

@main
struct RevenueWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransactionsWidget()
        RevenueInsightsWidget()
        RevenueTabWidget()
    }
}
