import Foundation

/// 东方财富统一行情数据源（美股 + A股，同一 API 家族，仅 secid 不同）。
/// - push2.eastmoney.com    实时行情
/// - push2his.eastmoney.com K 线历史
/// 免鉴权、无 SLA；限速 ≥1 请求/秒，避免封 IP。
nonisolated final class EastmoneyProvider: PriceProvider, @unchecked Sendable {
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let cache: DataCache
    private let quoteHost = "push2.eastmoney.com"
    private let klineHost = "push2his.eastmoney.com"

    init(session: URLSession = .shared, rateLimiter: RateLimiter, cache: DataCache) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.cache = cache
    }

    // MARK: - PriceProvider

    func quote(for symbol: Symbol) async throws -> Quote {
        let key = "em.quote.\(symbol.id)"
        if let cached: Quote = await cache.value(for: key) {
            return cached
        }

        var lastError: Error?
        for secid in symbol.eastmoneySecIDs {
            do {
                let quote = try await requestQuote(secid: secid, symbol: symbol)
                await cache.set(quote, for: key, ttl: 120)
                return quote
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DataError.noData(symbol.ticker)
    }

    func priceHistory(for symbol: Symbol, range: PriceRange) async throws -> [PriceBar] {
        let key = "em.history.\(symbol.id).\(range.rawValue)"
        if let cached: [PriceBar] = await cache.value(for: key) {
            return cached
        }

        let secid = symbol.eastmoneySecID
        let (klt, beg, end) = Self.params(for: range)
        var bars = try await requestKline(secid: secid, klt: klt, beg: beg, end: end)

        // 盘中分时（1D）对美股可能不支持，回退到日线
        if bars.isEmpty, klt != 101 {
            bars = try await requestKline(secid: secid, klt: 101, beg: beg, end: end)
        }
        guard !bars.isEmpty else { throw DataError.noData("\(symbol.ticker) 历史行情") }

        await cache.set(bars, for: key, ttl: 24 * 3600)
        return bars
    }

    // MARK: - Requests

    private func requestQuote(secid: String, symbol: Symbol) async throws -> Quote {
        await rateLimiter.waitForSlot(quoteHost, interval: 1.0)
        var components = URLComponents(string: "https://\(quoteHost)/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f43,f58,f60,f116,f162,f167,f169,f170"),
        ]
        let envelope: EMQuoteEnvelope = try await get(components.url, host: quoteHost)
        guard let data = envelope.data else {
            throw DataError.noData(symbol.ticker)
        }
        guard let price = data.f43?.value, price > 0 else {
            throw DataError.noData("\(symbol.ticker) 无有效行情")
        }
        let prevClose = data.f60?.value ?? price
        return Quote(
            price: price,
            previousClose: prevClose,
            currency: symbol.market == .cn ? "CNY" : "USD",
            marketCap: data.f116?.value,
            peTTM: data.f162?.value,
            pb: data.f167?.value,
            fiftyTwoWeekHigh: nil,
            fiftyTwoWeekLow: nil,
            companyName: data.f58 ?? symbol.ticker,
            timestamp: Date()
        )
    }

    private func requestKline(secid: String, klt: Int, beg: String, end: String) async throws -> [PriceBar] {
        await rateLimiter.waitForSlot(klineHost, interval: 1.0)
        var components = URLComponents(string: "https://\(klineHost)/api/qt/stock/kline/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "klt", value: "\(klt)"),
            URLQueryItem(name: "fqt", value: "1"),
            URLQueryItem(name: "beg", value: beg),
            URLQueryItem(name: "end", value: end),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56"),
        ]
        let envelope: EMKlineEnvelope = try await get(components.url, host: klineHost)
        guard let klines = envelope.data?.klines else {
            return []
        }
        var bars: [PriceBar] = []
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        for line in klines {
            let parts = line.split(separator: ",").map(String.init)
            guard parts.count >= 6,
                  let close = Double(parts[2]),
                  close > 0,
                  let open = Double(parts[1]),
                  let high = Double(parts[3]),
                  let low = Double(parts[4]),
                  let volume = Double(parts[5]),
                  let date = parseEMDate(parts[0], parser: parser) else { continue }
            bars.append(PriceBar(date: date, open: open, high: high, low: low, close: close, volume: volume))
        }
        return bars
    }

    private func get<T: Decodable>(_ url: URL?, host: String) async throws -> T {
        guard let url else { throw DataError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataError.network("无响应") }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw DataError.rateLimited }
            throw DataError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Helpers

    /// 解析 K 线日期：日线为 yyyy-MM-dd，分时为 yyyy-MM-dd HH:mm
    private func parseEMDate(_ raw: String, parser: DateFormatter) -> Date? {
        if raw.contains(" ") {
            parser.dateFormat = "yyyy-MM-dd HH:mm"
        } else {
            parser.dateFormat = "yyyy-MM-dd"
        }
        return parser.date(from: raw)
    }

    /// 区间参数：klt（1=1分 5=5分 15 30 60 101=日 102=周 103=月），beg/end 为日期
    private static func params(for range: PriceRange) -> (Int, String, String) {
        let now = Date()
        let calendar = Calendar.current
        func date(_ daysAgo: Int) -> String {
            let d = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            return f.string(from: d)
        }
        switch range {
        case .day:        return (5, date(1), date(0))     // 当日 5 分钟线
        case .week:       return (101, date(7), date(0))
        case .month:      return (101, date(35), date(0))
        case .threeMonth: return (101, date(100), date(0))
        case .year:       return (101, date(370), date(0))
        case .all:        return (101, "19900101", date(0))
        }
    }
}

// MARK: - Eastmoney JSON DTOs

nonisolated struct EMQuoteEnvelope: Decodable {
    let data: EMQuoteData?
}

nonisolated struct EMQuoteData: Decodable {
    let f43: FlexibleNumber?   // 现价
    let f58: String?           // 名称（中文）
    let f60: FlexibleNumber?   // 昨收
    let f116: FlexibleNumber?  // 总市值
    let f162: FlexibleNumber?  // 动态 PE（美股可能为 "-"）
    let f167: FlexibleNumber?  // 市净率
    let f169: FlexibleNumber?  // 涨跌额
    let f170: FlexibleNumber?  // 涨跌幅
}

nonisolated struct EMKlineEnvelope: Decodable {
    let data: EMKlineData?
}

nonisolated struct EMKlineData: Decodable {
    let klines: [String]?  // "date,open,close,high,low,volume"
}

/// 兼容数字或 "-" 字符串的字段解码
nonisolated struct FlexibleNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let i = try? c.decode(Int.self) {
            value = Double(i)
        } else if let s = try? c.decode(String.self) {
            value = Double(s)
        } else {
            value = nil
        }
    }
}
