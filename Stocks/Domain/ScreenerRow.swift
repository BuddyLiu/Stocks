import Foundation

/// 全市场粗筛结果行（行情级指标，用于初步过滤）
nonisolated struct ScreenerRow: Codable, Sendable, Hashable, Identifiable {
    var ticker: String
    var name: String
    var market: Market
    var price: Double?
    var changePercent: Double?
    var peTTM: Double?
    var pb: Double?
    var marketCap: Double?

    var id: String { "\(market.rawValue):\(ticker)" }
}
