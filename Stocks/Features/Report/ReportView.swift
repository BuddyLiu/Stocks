import SwiftUI

/// 个股巴菲特分析报告页（Apple Stocks 风格）：
/// 行情卡片 → K线图（区间切换）→ 关键指标 → 巴菲特评分 → AI 定性分析
struct ReportView: View {
    let symbol: Symbol
    @StateObject private var viewModel: ReportViewModel

    init(symbol: Symbol, settings: AppSettings) {
        self.symbol = symbol
        _viewModel = StateObject(wrappedValue: ReportViewModel(symbol: symbol, settings: settings))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.quote == nil {
                loadingState
            } else if viewModel.quote == nil {
                errorState
            } else {
                content
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let quote = viewModel.quote {
                    QuoteCardView(symbol: symbol, quote: quote)
                }
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                chartCard
                statsCard
                if let score = viewModel.score {
                    ScoreCardView(score: score, currency: viewModel.quote?.currency ?? "USD")
                    aiCard
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - 图表

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("价格走势")
                    .font(.headline)
                if viewModel.isHistoryLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新行情")
                Picker("区间", selection: $viewModel.selectedRange) {
                    ForEach(PriceRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
                .onChange(of: viewModel.selectedRange) { _, _ in
                    Task { await viewModel.onRangeChanged() }
                }
            }
            PriceChartView(bars: viewModel.priceHistory, range: viewModel.selectedRange, currency: viewModel.quote?.currency ?? "")
                .frame(height: 230)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 关键指标

    private var statsCard: some View {
        let stats = buildStats()
        return VStack(alignment: .leading, spacing: 10) {
            Text("关键指标")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(stats) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(s.value)
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private struct Stat: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    private func buildStats() -> [Stat] {
        let quote = viewModel.quote
        let latest = viewModel.fundamentals?.snapshots.first
        let currency = quote?.currency ?? "USD"

        var stats: [Stat] = []
        stats.append(Stat(title: "PE (TTM)", value: quote?.peTTM.map { dec($0) } ?? "—"))
        stats.append(Stat(title: "PB", value: quote?.pb.map { dec($0) } ?? "—"))
        stats.append(Stat(title: "ROE（最新年报）", value: latest?.roe.map { pct($0) } ?? "—"))
        if let dta = latest?.debtToAsset {
            stats.append(Stat(title: "资产负债率", value: pct(dta)))
        } else if let de = latest?.debtToEquity {
            stats.append(Stat(title: "有息负债/权益", value: dec(de)))
        } else {
            stats.append(Stat(title: "资产负债率", value: "—"))
        }
        stats.append(Stat(title: "总市值", value: quote?.marketCap.map { Formatting.compactLargeNumber($0) } ?? "—"))
        stats.append(Stat(title: "52周高", value: quote?.fiftyTwoWeekHigh.map { Formatting.price($0, currency: currency) } ?? "—"))
        stats.append(Stat(title: "52周低", value: quote?.fiftyTwoWeekLow.map { Formatting.price($0, currency: currency) } ?? "—"))
        stats.append(Stat(title: "数据覆盖", value: "\(viewModel.fundamentals?.coverageYears ?? 0) 年"))
        return stats
    }

    // MARK: - AI 分析

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 定性分析", systemImage: "sparkles")
                    .font(.headline)
                if viewModel.isAILoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Claude 正在分析护城河与管理层…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let report = viewModel.aiReport {
                aiMarkdown(report)
            } else if let message = viewModel.aiMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !viewModel.isAILoading {
                Text("点击生成 AI 分析报告")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func aiMarkdown(_ text: String) -> some View {
        if let attr = try? AttributedString(markdown: text) {
            return AnyView(Text(attr).frame(maxWidth: .infinity, alignment: .leading))
        }
        return AnyView(Text(text).frame(maxWidth: .infinity, alignment: .leading))
    }

    // MARK: - 状态

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载 \(symbol.ticker) 的财务数据…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(viewModel.errorMessage ?? "加载失败")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pct(_ fraction: Double) -> String { String(format: "%.1f%%", fraction * 100) }
    private func dec(_ value: Double) -> String { String(format: "%.2f", value) }
}
