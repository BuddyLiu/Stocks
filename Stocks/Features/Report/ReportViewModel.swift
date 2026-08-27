import Foundation
import Combine

/// 个股分析报告 ViewModel：行情 + 基本面 + 量化评分 + AI 定性分析。
/// 渲染策略：量化结果立即渲染，Claude 报告异步补上，AI 失败不影响量化展示。
@MainActor
final class ReportViewModel: ObservableObject {
    let symbol: Symbol

    @Published private(set) var quote: Quote?
    @Published private(set) var fundamentals: FundamentalsBundle?
    @Published private(set) var score: BuffetScore?
    @Published private(set) var priceHistory: [PriceBar] = []
    @Published private(set) var aiReport: String?
    @Published private(set) var aiMessage: String?
    @Published var selectedRange: PriceRange = .year
    @Published private(set) var isLoading = false
    @Published private(set) var isHistoryLoading = false
    @Published private(set) var isAILoading = false
    @Published private(set) var errorMessage: String?

    private let service: MarketDataService
    private let settings: AppSettings
    private let claude: ClaudeClient

    init(symbol: Symbol, settings: AppSettings, service: MarketDataService? = nil) {
        self.symbol = symbol
        self.settings = settings
        self.service = service ?? .shared
        self.claude = ClaudeClient(apiKey: { KeychainStore.load("anthropicKey") })
    }

    // MARK: - 加载

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 行情先行，行情失败则整体失败
        do {
            quote = try await service.quote(for: symbol)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        Task { await loadHistory() }

        // 基本面 → 量化评分（失败不阻塞行情展示）
        do {
            let f = try await service.fundamentals(for: symbol)
            fundamentals = f
            if let quote {
                score = BuffettEngine.analyze(fundamentals: f, quote: quote)
                Task { await runAIAnalysis() }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadHistory() async {
        isHistoryLoading = true
        defer { isHistoryLoading = false }
        do {
            priceHistory = try await service.priceHistory(for: symbol, range: selectedRange)
        } catch {
            priceHistory = []
        }
    }

    // MARK: - AI

    func runAIAnalysis() async {
        guard let quote, let fundamentals, let score else { return }
        if (KeychainStore.load("anthropicKey") ?? "").isEmpty {
            aiMessage = "未配置 Anthropic API Key（设置 → AI 服务）。量化评分仍可用，AI 定性分析已跳过。"
            return
        }
        guard !isAILoading else { return }
        isAILoading = true
        aiMessage = nil
        defer { isAILoading = false }

        do {
            let userPrompt = BuffettAnalysisPrompts.userPrompt(
                symbol: symbol, quote: quote, fundamentals: fundamentals, score: score
            )
            aiReport = try await claude.analyze(
                model: settings.claudeModel,
                systemPrompt: BuffettAnalysisPrompts.system,
                userPrompt: userPrompt
            )
        } catch {
            aiMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 区间切换后重新拉取历史
    func onRangeChanged() async {
        await loadHistory()
    }

    /// 手动刷新：重新拉取行情与历史（基本面命中缓存，快速返回）
    func reload() async {
        do {
            quote = try await service.quote(for: symbol)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        errorMessage = nil
        Task { await loadHistory() }
        if let f = fundamentals, let q = quote {
            score = BuffettEngine.analyze(fundamentals: f, quote: q)
            Task { await runAIAnalysis() }
        }
    }
}
