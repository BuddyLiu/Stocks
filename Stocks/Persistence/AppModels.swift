import Foundation
import SwiftData

/// 自选股条目（SwiftData 模型）
@Model
final class WatchItem {
    var ticker: String
    var marketRaw: String
    var displayName: String
    var addedAt: Date

    init(ticker: String, market: Market, displayName: String) {
        self.ticker = ticker
        self.marketRaw = market.rawValue
        self.displayName = displayName
        self.addedAt = Date()
    }

    var symbol: Symbol { Symbol(ticker: ticker, market: Market(rawValue: marketRaw) ?? .us) }
}

/// 持仓条目（SwiftData 模型）：数量 + 每股成本，行情按需刷新计算盈亏
@Model
final class Holding {
    var ticker: String
    var marketRaw: String
    var displayName: String
    var quantity: Double
    var costBasis: Double    // 每股成本（买入均价）
    var addedAt: Date

    init(ticker: String, market: Market, displayName: String, quantity: Double, costBasis: Double) {
        self.ticker = ticker
        self.marketRaw = market.rawValue
        self.displayName = displayName
        self.quantity = quantity
        self.costBasis = costBasis
        self.addedAt = Date()
    }

    var symbol: Symbol { Symbol(ticker: ticker, market: Market(rawValue: marketRaw) ?? .us) }

    /// 持仓成本总额
    var totalCost: Double { quantity * costBasis }

    /// 现价市值
    func marketValue(price: Double) -> Double { quantity * price }

    /// 盈亏额
    func profit(price: Double) -> Double { (price - costBasis) * quantity }

    /// 盈亏率（小数）
    func profitPercent(price: Double) -> Double {
        guard costBasis > 0 else { return 0 }
        return price / costBasis - 1
    }
}
