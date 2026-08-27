import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .navigationTitle("巴菲特助手")
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .watchlist:
                WatchlistView()
            case .holdings:
                HoldingsView()
            case .screener:
                ScreenerView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 920, minHeight: 640)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(MarketDataService.shared)
}
