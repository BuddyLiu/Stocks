import Foundation

/// A股财务基本面数据源（东方财富 F10 datacenter，免鉴权、无 SLA）。
/// - 利润表/比率/现金流：`RPT_F10_FINANCE_MAINFINADATA`（165 字段，年+季混合）
/// - 现金及等价物：`RPT_F10_FINANCE_GBALANCE`（资产负债表）
/// 客户端只保留 REPORT_DATE 以 `-12-31` 结尾的年报行；每只股票 2 次请求。
nonisolated final class EastmoneyFundamentalsProvider: FundamentalsProvider, @unchecked Sendable {
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let cache: DataCache
    private let host = "datacenter.eastmoney.com"

    init(session: URLSession = .shared, rateLimiter: RateLimiter, cache: DataCache) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.cache = cache
    }

    // MARK: - FundamentalsProvider

    func fundamentals(for symbol: Symbol) async throws -> FundamentalsBundle {
        guard symbol.market == .cn else { throw DataError.noData("东方财富 F10 仅支持 A股") }
        let key = "em.fund.\(symbol.id)"
        if let cached: FundamentalsBundle = await cache.value(for: key) { return cached }

        let secucode = symbol.secucode
        let main = try await report(name: "RPT_F10_FINANCE_MAINFINADATA", secucode: secucode)
        // 现金报表失败不致命：无现金时 DCF 净现金按仅扣有息负债处理
        let balance = (try? await report(name: "RPT_F10_FINANCE_GBALANCE", secucode: secucode)) ?? []

        let bundle = Self.merge(main: main, balance: balance, symbol: symbol)
        guard bundle.coverageYears > 0 else { throw DataError.noData("\(symbol.ticker) 无年度财务数据") }
        await cache.set(bundle, for: key, ttl: 24 * 3600)
        return bundle
    }

    // MARK: - Requests

    private func report(name: String, secucode: String) async throws -> [F10Row] {
        await rateLimiter.waitForSlot(host, interval: 1.0)
        var components = URLComponents(string: "https://\(host)/securities/api/data/v1/get")!
        components.queryItems = [
            URLQueryItem(name: "reportName", value: name),
            URLQueryItem(name: "columns", value: "ALL"),
            URLQueryItem(name: "filter", value: "(SECUCODE=\"\(secucode)\")"),
            URLQueryItem(name: "sortColumns", value: "REPORT_DATE"),
            URLQueryItem(name: "sortTypes", value: "-1"),
            URLQueryItem(name: "pageSize", value: "60"),
            URLQueryItem(name: "source", value: "F10"),
            URLQueryItem(name: "client", value: "PC"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataError.network("无响应") }
        guard http.statusCode == 200 else { throw DataError.httpStatus(http.statusCode) }

        let envelope = try JSONDecoder().decode(F10Envelope.self, from: data)
        guard envelope.success == true, let rows = envelope.result?.data else {
            throw DataError.noData("\(secucode) \(name) 返回失败")
        }
        return rows
    }

    // MARK: - Merge

    private static func merge(main: [F10Row], balance: [F10Row], symbol: Symbol) -> FundamentalsBundle {
        var byYear: [Int: FinancialSnapshot] = [:]
        var industry: String?

        for row in main {
            guard let date = row.string("REPORT_DATE"),
                  isAnnual(date),
                  let year = Int(date.prefix(4)) else { continue }
            if industry == nil { industry = row.string("ORG_TYPE") }

            var s = byYear[year] ?? emptySnapshot(year: year)
            s.revenue = row.double("TOTALOPERATEREVE")
            s.netIncome = row.double("PARENTNETPROFIT")
            s.eps = row.double("EPSJB")
            s.roe = divide(row.double("ROEJQ"), by: 100)
            s.grossMargin = divide(row.double("XSMLL"), by: 100)
            s.netMargin = divide(row.double("XSJLL"), by: 100)
            s.debtToAsset = divide(row.double("ZCFZL"), by: 100)
            s.interestCoverage = row.double("INTEREST_COVERAGE_RATIO")
            s.freeCashFlow = row.double("FCFF_FORWARD")
            s.sharesOutstanding = row.double("TOTAL_SHARE")
            s.totalEquity = row.double("TOTAL_EQUITY_PK")
            // 有息负债 = 有息负债率 × 总资产
            if let rate = row.double("INTEREST_DEBT_RATIO"), let assets = row.double("TOTAL_ASSETS_PK") {
                s.totalDebt = rate / 100 * assets
                if let eq = s.totalEquity, eq != 0 { s.debtToEquity = s.totalDebt! / eq }
            }
            byYear[year] = s
        }

        for row in balance {
            guard let date = row.string("REPORT_DATE"),
                  isAnnual(date),
                  let year = Int(date.prefix(4)) else { continue }
            var s = byYear[year] ?? emptySnapshot(year: year)
            if let cash = row.double("MONETARYFUNDS") { s.cashAndEquivalents = cash }
            byYear[year] = s
        }

        let snapshots = byYear.values.sorted { $0.year > $1.year }  // 新 → 旧
        return FundamentalsBundle(
            symbol: symbol.ticker,
            market: symbol.market,
            snapshots: snapshots,
            currency: "CNY",
            generatedAt: Date(),
            industry: industry
        )
    }

    private static func emptySnapshot(year: Int) -> FinancialSnapshot {
        FinancialSnapshot(year: year, revenue: nil, netIncome: nil, eps: nil,
                          roe: nil, grossMargin: nil, netMargin: nil,
                          debtToEquity: nil, debtToAsset: nil, interestCoverage: nil,
                          freeCashFlow: nil, totalEquity: nil, totalDebt: nil,
                          cashAndEquivalents: nil, sharesOutstanding: nil)
    }

    private static func divide(_ value: Double?, by divisor: Double) -> Double? {
        guard let value else { return nil }
        return value / divisor
    }

    /// REPORT_DATE 形如 "2025-12-31 00:00:00"：取前 10 位判断是否年报（12-31 结尾）
    private static func isAnnual(_ date: String) -> Bool {
        let day = date.count >= 10 ? String(date.prefix(10)) : date
        return day.hasSuffix("12-31")
    }
}

// MARK: - F10 JSON DTOs

nonisolated struct F10Envelope: Decodable {
    let success: Bool?
    let result: F10Result?
    struct F10Result: Decodable {
        let data: [F10Row]?
    }
}

/// 容错字段值：兼容数字 / 数字字符串 / null
nonisolated struct F10Value: Decodable {
    let double: Double?
    let string: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            double = d; string = nil
        } else if let i = try? c.decode(Int.self) {
            double = Double(i); string = nil
        } else if let s = try? c.decode(String.self) {
            double = Double(s); string = s
        } else {
            double = nil; string = nil
        }
    }
}

/// 单行报表数据：按字段名取值
nonisolated struct F10Row: Decodable {
    let values: [String: F10Value]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var dict: [String: F10Value] = [:]
        for key in container.allKeys {
            if let v = try? container.decode(F10Value.self, forKey: key) {
                dict[key.stringValue] = v
            }
        }
        values = dict
    }

    func double(_ key: String) -> Double? { values[key]?.double }
    func string(_ key: String) -> String? { values[key]?.string }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
