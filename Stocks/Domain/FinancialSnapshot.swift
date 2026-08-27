import Foundation

/// 单个会计年度的财务快照（归一化，美股 / A股通用）
nonisolated struct FinancialSnapshot: Codable, Sendable, Hashable {
    var year: Int
    var revenue: Double?            // 营业总收入
    var netIncome: Double?          // 归母净利润
    var eps: Double?                // 基本每股收益
    var roe: Double?                // 净资产收益率（小数，如 0.20 = 20%）
    var grossMargin: Double?        // 毛利率（小数）
    var netMargin: Double?          // 净利率（小数）
    var debtToEquity: Double?       // 有息负债 / 权益
    var debtToAsset: Double?        // 资产负债率（小数）
    var interestCoverage: Double?   // 利息保障倍数
    var freeCashFlow: Double?       // 自由现金流
    var totalEquity: Double?        // 净资产
    var totalDebt: Double?          // 有息负债
    var cashAndEquivalents: Double? // 现金及等价物
    var sharesOutstanding: Double?  // 总股本
}

/// 基本面数据包：逐年快照（新 → 旧）+ 覆盖年数 + 币种
nonisolated struct FundamentalsBundle: Codable, Sendable, Hashable {
    var symbol: String
    var market: Market
    var snapshots: [FinancialSnapshot]  // 新 → 旧
    var currency: String
    var generatedAt: Date
    var industry: String?              // 行业/组织类型（用于金融股豁免判断）

    var coverageYears: Int { snapshots.count }

    init(symbol: String, market: Market, snapshots: [FinancialSnapshot], currency: String, generatedAt: Date, industry: String? = nil) {
        self.symbol = symbol
        self.market = market
        self.snapshots = snapshots
        self.currency = currency
        self.generatedAt = generatedAt
        self.industry = industry
    }
}
