import Foundation

/// 美股财务基本面数据源（Alpha Vantage 免费档）。
/// 免费档每日 25 次请求、约 5 年年度报表；每只股票需 3 次：
/// INCOME_STATEMENT / BALANCE_SHEET / CASH_FLOW。
/// 所有数值字段在响应中均为字符串，decoder 统一转 Double 并带别名兜底。
nonisolated final class AlphaVantageFundamentalsProvider: FundamentalsProvider, @unchecked Sendable {
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let cache: DataCache
    private let budget: DailyBudget
    private let apiKey: () -> String?
    private let host = "www.alphavantage.co"

    init(session: URLSession = .shared, rateLimiter: RateLimiter, cache: DataCache, budget: DailyBudget, apiKey: @escaping () -> String?) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.cache = cache
        self.budget = budget
        self.apiKey = apiKey
    }

    // MARK: - FundamentalsProvider

    func fundamentals(for symbol: Symbol) async throws -> FundamentalsBundle {
        guard symbol.market == .us else { throw DataError.noData("Alpha Vantage 仅支持美股") }
        let key = "av.fund.\(symbol.ticker)"
        if let cached: FundamentalsBundle = await cache.value(for: key) { return cached }

        guard let key = apiKey(), !key.isEmpty else {
            throw DataError.noData("未配置 Alpha Vantage API Key（设置 → 数据源）")
        }
        guard await budget.remaining >= 3 else {
            throw DataError.quotaExhausted("Alpha Vantage 免费档每日 25 次，今日剩余不足 3 次")
        }

        _ = await budget.take()
        let income = try await statement(function: "INCOME_STATEMENT", symbol: symbol, apiKey: key)
        _ = await budget.take()
        let balance = try await statement(function: "BALANCE_SHEET", symbol: symbol, apiKey: key)
        _ = await budget.take()
        let cash = try await statement(function: "CASH_FLOW", symbol: symbol, apiKey: key)

        let bundle = Self.merge(income: income, balance: balance, cash: cash, symbol: symbol)
        guard bundle.coverageYears > 0 else { throw DataError.noData("\(symbol.ticker) 无年度财务数据") }
        await cache.set(bundle, for: key, ttl: 24 * 3600)
        return bundle
    }

    // MARK: - Requests

    private func statement(function: String, symbol: Symbol, apiKey: String) async throws -> [AVAnnualReport] {
        await rateLimiter.waitForSlot(host, interval: 2.0)
        var components = URLComponents(string: "https://\(host)/query")!
        components.queryItems = [
            URLQueryItem(name: "function", value: function),
            URLQueryItem(name: "symbol", value: symbol.ticker),
            URLQueryItem(name: "apikey", value: apiKey),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataError.network("无响应") }
        guard http.statusCode == 200 else { throw DataError.httpStatus(http.statusCode) }

        let envelope = try JSONDecoder().decode(AVStatementEnvelope.self, from: data)
        if let info = envelope.information {
            throw DataError.noData(info)
        }
        guard let reports = envelope.annualReports, !reports.isEmpty else {
            throw DataError.noData("\(symbol.ticker) 无 \(function) 年度数据")
        }
        return reports
    }

    // MARK: - Merge

    private static func merge(income: [AVAnnualReport], balance: [AVAnnualReport], cash: [AVAnnualReport], symbol: Symbol) -> FundamentalsBundle {
        var byYear: [Int: FinancialSnapshot] = [:]

        for r in income {
            guard let year = Self.year(r["fiscalDateEnding"]) else { continue }
            var s = byYear[year] ?? FinancialSnapshot(year: year, revenue: nil, netIncome: nil, eps: nil,
                                                      roe: nil, grossMargin: nil, netMargin: nil,
                                                      debtToEquity: nil, debtToAsset: nil, interestCoverage: nil,
                                                      freeCashFlow: nil, totalEquity: nil, totalDebt: nil,
                                                      cashAndEquivalents: nil, sharesOutstanding: nil)
            s.revenue = r.double("totalRevenue")
            s.netIncome = r.double("netIncome")
            s.eps = r.double("eps")
            s.sharesOutstanding = r.double("weightedAverageShsOut") ?? r.double("weightedAverageShsOutDiluted")
            if let gp = r.double("grossProfit"), let rev = s.revenue, rev > 0 {
                s.grossMargin = gp / rev
            }
            if let oi = r.double("operatingIncome"), let ie = r.double("interestExpense"), ie != 0 {
                s.interestCoverage = oi / ie
            }
            byYear[year] = s
        }

        for r in balance {
            guard let year = Self.year(r["fiscalDateEnding"]) else { continue }
            var s = byYear[year] ?? FinancialSnapshot(year: year, revenue: nil, netIncome: nil, eps: nil,
                                                      roe: nil, grossMargin: nil, netMargin: nil,
                                                      debtToEquity: nil, debtToAsset: nil, interestCoverage: nil,
                                                      freeCashFlow: nil, totalEquity: nil, totalDebt: nil,
                                                      cashAndEquivalents: nil, sharesOutstanding: nil)
            s.totalEquity = r.double("totalShareholderEquity")
            s.cashAndEquivalents = r.double("cashAndCashEquivalentsAtCarryingValue")
            if let sh = r.double("commonStockSharesOutstanding") { s.sharesOutstanding = sh }

            let shortDebt = r.double("shortTermDebt")
            let longDebt = r.double("longTermDebt")
            if shortDebt != nil || longDebt != nil {
                s.totalDebt = (shortDebt ?? 0) + (longDebt ?? 0)
            }

            if let ni = s.netIncome, let eq = s.totalEquity, eq != 0 { s.roe = ni / eq }
            if let ni = s.netIncome, let rev = s.revenue, rev != 0 { s.netMargin = ni / rev }
            if let debt = s.totalDebt, let eq = s.totalEquity, eq != 0 { s.debtToEquity = debt / eq }
            if let liabilities = r.double("totalLiabilities"), let assets = r.double("totalAssets"), assets != 0 {
                s.debtToAsset = liabilities / assets
            }
            byYear[year] = s
        }

        for r in cash {
            guard let year = Self.year(r["fiscalDateEnding"]) else { continue }
            var s = byYear[year] ?? FinancialSnapshot(year: year, revenue: nil, netIncome: nil, eps: nil,
                                                      roe: nil, grossMargin: nil, netMargin: nil,
                                                      debtToEquity: nil, debtToAsset: nil, interestCoverage: nil,
                                                      freeCashFlow: nil, totalEquity: nil, totalDebt: nil,
                                                      cashAndEquivalents: nil, sharesOutstanding: nil)
            s.freeCashFlow = r.double("freeCashFlow") ?? r.double("operatingCashflow")
            byYear[year] = s
        }

        let snapshots = byYear.values.sorted { $0.year > $1.year }  // 新 → 旧
        return FundamentalsBundle(
            symbol: symbol.ticker,
            market: symbol.market,
            snapshots: snapshots,
            currency: "USD",
            generatedAt: Date()
        )
    }

    private static func year(_ fiscalEnding: String?) -> Int? {
        guard let s = fiscalEnding, s.count >= 4 else { return nil }
        return Int(s.prefix(4))
    }
}

// MARK: - Alpha Vantage JSON DTOs

/// 报表信封：`annualReports` 数组 + 可能出现的错误/提示信息
nonisolated struct AVStatementEnvelope: Decodable {
    let annualReports: [AVAnnualReport]?
    let information: String?

    enum CodingKeys: String, CodingKey {
        case annualReports, information
    }
}

/// 单年度报表：字段多为字符串数字，null/缺失时跳过（容错解码）
nonisolated struct AVAnnualReport: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var dict: [String: String] = [:]
        for key in container.allKeys {
            if let s = try? container.decode(String.self, forKey: key) {
                dict[key.stringValue] = s
            } else if let n = try? container.decode(Double.self, forKey: key) {
                dict[key.stringValue] = String(n)
            }
            // null 或其他类型 → 跳过
        }
        values = dict
    }

    func double(_ key: String) -> Double? {
        guard let s = values[key], !s.isEmpty else { return nil }
        return Double(s)
    }

    subscript(key: String) -> String? { values[key] }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
