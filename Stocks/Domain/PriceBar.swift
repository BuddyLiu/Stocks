import Foundation

/// 单根 K 线 / 折线数据点
nonisolated struct PriceBar: Codable, Sendable, Hashable, Identifiable {
    var date: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double

    var id: Date { date }
}

/// 图表时间区间
nonisolated enum PriceRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonth = "3M"
    case year = "1Y"
    case all = "全部"

    var id: String { rawValue }
}
