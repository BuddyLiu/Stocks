import SwiftUI
import SwiftData

@main
struct StocksApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var service = MarketDataService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(service)
                .modelContainer(for: [WatchItem.self, Holding.self])
        }
    }
}
