import Foundation
import Combine

/// 筛选器 ViewModel：市场 → 全市场粗筛（估值过滤）→ 深度精筛（基本面 + 巴菲特引擎）。
/// 美股基本面受 Alpha Vantage 每日 25 次配额限制，不足时自动跳过并提示。
@MainActor
final class ScreenerViewModel: ObservableObject {
    private let service: MarketDataService

    // 筛选条件
    @Published var market: Market = .cn
    @Published var maxPE: Double = 30
    @Published var maxPB: Double = 8
    @Published var minMarketCapYi: Double = 100   // 总市值下限（亿）
    @Published var deepCount: Int = 20            // 深度精筛数量

    // 状态
    @Published private(set) var universe: [ScreenerRow] = []
    @Published private(set) var filtered: [ScreenerRow] = []
    @Published private(set) var results: [ScreenerResult] = []
    @Published private(set) var isLoadingUniverse = false
    @Published private(set) var isDeepScanning = false
    @Published private(set) var universeProgress = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var avRemaining: Int?
    @Published private(set) var deepFailed = 0

    init(service: MarketDataService? = nil) {
        self.service = service ?? .shared
    }

    /// 刷新 Alpha Vantage 剩余配额（美股深度分析提示用）
    func refreshAVBudget() async {
        avRemaining = await service.avRemainingBudget()
    }

    // MARK: - 加载市场

    func loadUniverse() async {
        guard !isLoadingUniverse else { return }
        isLoadingUniverse = true
        errorMessage = nil
        universeProgress = "正在获取\(market.displayName)全市场数据…"
        defer { isLoadingUniverse = false; universeProgress = "" }

        do {
            let rows = try await service.universe(for: market)
            universe = rows
            applyFilters()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 过滤

    func applyFilters() {
        let maxPE = self.maxPE
        let maxPB = self.maxPB
        let minCap = self.minMarketCapYi * 1e8
        filtered = universe.filter { row in
            if let pe = row.peTTM, pe > 0, pe > maxPE { return false }
            if let pb = row.pb, pb > 0, pb > maxPB { return false }
            if let cap = row.marketCap, cap < minCap { return false }
            return true
        }
        results = []
    }

    // MARK: - 深度精筛

    func deepScan() async {
        guard !isDeepScanning, !filtered.isEmpty else { return }
        isDeepScanning = true
        errorMessage = nil
        defer { isDeepScanning = false }

        let candidates = Array(filtered.prefix(deepCount))
        var newResults: [ScreenerResult] = []
        var failed = 0
        for (i, row) in candidates.enumerated() {
            universeProgress = "深度分析 \(i + 1)/\(candidates.count)：\(row.name)…"
            if let result = try? await analyze(row) {
                newResults.append(result)
            } else {
                failed += 1  // 单只失败（多为 Alpha Vantage 配额/Key 未配置）跳过
            }
        }
        results = newResults.sorted { $0.score.totalScore > $1.score.totalScore }
        deepFailed = failed
        universeProgress = ""
    }

    private func analyze(_ row: ScreenerRow) async throws -> ScreenerResult {
        let symbol = Symbol(ticker: row.ticker, market: market)
        let fundamentals = try await service.fundamentals(for: symbol)
        let quote = quote(from: row)
        let score = BuffettEngine.analyze(fundamentals: fundamentals, quote: quote)
        return ScreenerResult(row: row, score: score, quote: quote, fundamentals: fundamentals)
    }

    /// 从粗筛行构造 Quote（引擎只需要 price/pe/pb；previousClose 由涨跌幅反推）
    private func quote(from row: ScreenerRow) -> Quote {
        let prevClose: Double
        if let p = row.price, let c = row.changePercent, p > 0 {
            prevClose = p / (1 + c)
        } else {
            prevClose = row.price ?? 0
        }
        return Quote(
            price: row.price ?? 0,
            previousClose: prevClose,
            currency: market == .cn ? "CNY" : "USD",
            marketCap: row.marketCap,
            peTTM: row.peTTM,
            pb: row.pb,
            fiftyTwoWeekHigh: nil,
            fiftyTwoWeekLow: nil,
            companyName: row.name,
            timestamp: nil
        )
    }
}

/// 深度筛选结果：粗筛行 + 完整巴菲特评分 + 基本面
struct ScreenerResult: Identifiable {
    let row: ScreenerRow
    let score: BuffetScore
    let quote: Quote
    let fundamentals: FundamentalsBundle

    var id: String { row.id }
}
