import Foundation

/// 全市场股票池（东方财富 clist，免鉴权）。
/// - A股：`fs=m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23`（深主板/创业板/沪主板/科创板），约 5500 只
/// - 美股：`fs=m:105,m:106`（NASDAQ/NYSE），约 9000 只；f14 为中文名
/// 分页 pz=100 封顶，rate limit 1/s；A股全量约 56 页，美股默认取市值前 1200 只（12 页）。
nonisolated final class EastmoneyUniverseProvider: UniverseProvider, @unchecked Sendable {
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let cache: DataCache
    private let host = "push2.eastmoney.com"

    init(session: URLSession = .shared, rateLimiter: RateLimiter, cache: DataCache) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.cache = cache
    }

    // MARK: - UniverseProvider

    func universe(for market: Market) async throws -> [ScreenerRow] {
        let key = "em.universe.\(market.rawValue)"
        if let cached: [ScreenerRow] = await cache.value(for: key) { return cached }

        let fs: String
        let maxPages: Int
        switch market {
        case .cn:
            fs = "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23"
            maxPages = 60
        case .us:
            fs = "m:105,m:106"
            maxPages = 12
        }

        var rows: [ScreenerRow] = []
        var total = Int.max
        var page = 1
        while rows.count < total && page <= maxPages {
            let batch = try await fetchPage(page, fs: fs, market: market)
            total = batch.total
            rows.append(contentsOf: batch.rows)
            page += 1
            if batch.rows.isEmpty { break }
        }

        // 去重并排除无效行（无代码）
        var seen = Set<String>()
        rows = rows.filter { !$0.ticker.isEmpty && seen.insert($0.ticker).inserted }

        await cache.set(rows, for: key, ttl: 6 * 3600)
        return rows
    }

    // MARK: - Request

    private func fetchPage(_ pn: Int, fs: String, market: Market) async throws -> (total: Int, rows: [ScreenerRow]) {
        await rateLimiter.waitForSlot(host, interval: 1.0)
        var components = URLComponents(string: "https://\(host)/api/qt/clist/get")!
        components.queryItems = [
            URLQueryItem(name: "pn", value: "\(pn)"),
            URLQueryItem(name: "pz", value: "100"),
            URLQueryItem(name: "po", value: "1"),
            URLQueryItem(name: "np", value: "1"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fid", value: "f20"),            // 按总市值排序
            URLQueryItem(name: "fs", value: fs),
            URLQueryItem(name: "fields", value: "f12,f14,f2,f3,f9,f115,f23,f20"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataError.network("无响应") }
        guard http.statusCode == 200 else { throw DataError.httpStatus(http.statusCode) }

        let envelope = try JSONDecoder().decode(ClistEnvelope.self, from: data)
        guard let payload = envelope.data else { throw DataError.noData("市场数据为空") }

        var rows: [ScreenerRow] = []
        for item in payload.diff ?? [] {
            guard let ticker = item.f12, !ticker.isEmpty else { continue }
            rows.append(ScreenerRow(
                ticker: ticker,
                name: item.f14 ?? ticker,
                market: market,
                price: item.f2.flatMap(Self.number),
                changePercent: item.f3.flatMap(Self.number).map { $0 / 100 },
                peTTM: item.f115.flatMap(Self.number),
                pb: item.f23.flatMap(Self.number),
                marketCap: item.f20.flatMap(Self.number)
            ))
        }
        return (payload.total ?? rows.count, rows)
    }

    /// 值可能是数字或 "-"（停牌等），统一转 Double?
    private static func number(_ value: ClistValue) -> Double? {
        if let d = value.double { return d }
        return value.string.flatMap { Double($0) }
    }
}

// MARK: - clist JSON DTOs

nonisolated struct ClistEnvelope: Decodable {
    let data: ClistPayload?
    struct ClistPayload: Decodable {
        let total: Int?
        let diff: [ClistItem]?
    }
}

nonisolated struct ClistItem: Decodable {
    let f12: String?   // 代码
    let f14: String?   // 名称
    let f2: ClistValue?   // 最新价
    let f3: ClistValue?   // 涨跌幅
    let f9: ClistValue?   // 动态 PE
    let f115: ClistValue? // PE TTM
    let f23: ClistValue?  // PB
    let f20: ClistValue?  // 总市值

    enum CodingKeys: String, CodingKey { case f12, f14, f2, f3, f9, f115, f23, f20 }
}

/// 容错数值：兼容数字 / 字符串 / null
nonisolated struct ClistValue: Decodable {
    let double: Double?
    let string: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { double = d; string = nil }
        else if let i = try? c.decode(Int.self) { double = Double(i); string = nil }
        else if let s = try? c.decode(String.self) { double = Double(s); string = s }
        else { double = nil; string = nil }
    }
}
