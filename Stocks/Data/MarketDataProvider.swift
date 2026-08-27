import Foundation

/// 行情价格数据源
protocol PriceProvider: Sendable {
    func quote(for symbol: Symbol) async throws -> Quote
    func priceHistory(for symbol: Symbol, range: PriceRange) async throws -> [PriceBar]
}

/// 财务基本面数据源
protocol FundamentalsProvider: Sendable {
    func fundamentals(for symbol: Symbol) async throws -> FundamentalsBundle
}

/// 全市场股票池数据源（按市场）
protocol UniverseProvider: Sendable {
    func universe(for market: Market) async throws -> [ScreenerRow]
}

/// 统一错误类型，UI 渲染中文错误提示
nonisolated enum DataError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case rateLimited
    case blocked
    case decoding(String)
    case network(String)
    case noData(String)
    case quotaExhausted(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的请求地址"
        case .httpStatus(let code):
            return "数据源返回错误（HTTP \(code)）"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .blocked:
            return "数据源拒绝了请求，请稍后再试"
        case .decoding(let msg):
            return "数据解析失败：\(msg)"
        case .network(let msg):
            return "网络错误：\(msg)"
        case .noData(let msg):
            return "没有可用数据：\(msg)"
        case .quotaExhausted(let msg):
            return "免费数据配额已用尽：\(msg)"
        }
    }
}
