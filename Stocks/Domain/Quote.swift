import Foundation

/// 实时行情快照
nonisolated struct Quote: Codable, Sendable, Hashable {
    var price: Double
    var previousClose: Double
    var currency: String
    var marketCap: Double?
    var peTTM: Double?
    var pb: Double?
    var fiftyTwoWeekHigh: Double?
    var fiftyTwoWeekLow: Double?
    var companyName: String?
    var timestamp: Date?

    /// 涨跌额
    var change: Double { price - previousClose }

    /// 涨跌幅（小数，如 0.0123 = +1.23%）
    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return price / previousClose - 1
    }

    /// 是否上涨
    var isUp: Bool { price >= previousClose }
}
