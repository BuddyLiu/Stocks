import Foundation
import Combine

/// 数据访问外观：Views 唯一接触的数据入口。
/// 负责按市场路由到对应 Provider、统一限速与缓存。
final class MarketDataService: ObservableObject {
    static let shared = MarketDataService()

    private let rateLimiter = RateLimiter()
    private let cache = DataCache()
    private let avBudget = DailyBudget(limit: 25)  // Alpha Vantage 免费档 25 次/天

    private lazy var eastmoney: EastmoneyProvider = EastmoneyProvider(rateLimiter: rateLimiter, cache: cache)

    /// 美股财务（Alpha Vantage，25 次/天）；API Key 从钥匙串读取
    private lazy var alphaVantage: AlphaVantageFundamentalsProvider = AlphaVantageFundamentalsProvider(
        rateLimiter: rateLimiter,
        cache: cache,
        budget: avBudget,
        apiKey: { KeychainStore.load("alphaVantageKey") }
    )

    /// A股财务（东方财富 F10，免鉴权）
    private lazy var eastmoneyFundamentals: EastmoneyFundamentalsProvider = EastmoneyFundamentalsProvider(
        rateLimiter: rateLimiter,
        cache: cache
    )

    /// 全市场股票池（东方财富 clist）
    private lazy var eastmoneyUniverse: EastmoneyUniverseProvider = EastmoneyUniverseProvider(
        rateLimiter: rateLimiter,
        cache: cache
    )

    private init() {}

    // MARK: - 行情（美股 + A股，统一走东方财富）

    func quote(for symbol: Symbol) async throws -> Quote {
        try await eastmoney.quote(for: symbol)
    }

    func priceHistory(for symbol: Symbol, range: PriceRange) async throws -> [PriceBar] {
        try await eastmoney.priceHistory(for: symbol, range: range)
    }

    // MARK: - 基本面（美股 Alpha Vantage，A股 P3 接入 F10）

    func fundamentals(for symbol: Symbol) async throws -> FundamentalsBundle {
        switch symbol.market {
        case .us:
            return try await alphaVantage.fundamentals(for: symbol)
        case .cn:
            return try await eastmoneyFundamentals.fundamentals(for: symbol)
        }
    }

    // MARK: - 全市场股票池（筛选器用）

    func universe(for market: Market) async throws -> [ScreenerRow] {
        try await eastmoneyUniverse.universe(for: market)
    }

    // MARK: - 批量行情（自选 / 持仓列表用）

    /// 拉取一组代码的实时行情；单只失败跳过，返回成功项
    func quotes(for symbols: [Symbol]) async -> [String: Quote] {
        var result: [String: Quote] = [:]
        for symbol in symbols {
            if let q = try? await quote(for: symbol) {
                result[symbol.id] = q
            }
        }
        return result
    }

    // MARK: - 配额信息

    /// Alpha Vantage 今日剩余配额
    func avRemainingBudget() async -> Int {
        await avBudget.remaining
    }
}
