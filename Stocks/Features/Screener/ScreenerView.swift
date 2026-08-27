import SwiftUI

/// 全市场筛选器：估值粗筛 → 巴菲特引擎深度精筛，结果表可点按进报告
struct ScreenerView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = ScreenerViewModel()

    @State private var selectedSymbol: Symbol?

    var body: some View {
        Group {
            if let selectedSymbol {
                ReportView(symbol: selectedSymbol, settings: settings)
                    .id(selectedSymbol.id)
            } else {
                content
            }
        }
        .navigationTitle("筛选器")
        .task { await viewModel.refreshAVBudget() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            criteriaBar
            Divider()
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }
            if viewModel.isLoadingUniverse {
                ProgressView(viewModel.universeProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.universe.isEmpty {
                emptyPrompt
            } else {
                resultArea
            }
        }
        .padding(.top, 16)
    }

    // MARK: - 条件栏

    private var criteriaBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("市场", selection: $viewModel.market) {
                Text("A股").tag(Market.cn)
                Text("美股").tag(Market.us)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: viewModel.market) { _, _ in
                Task { await viewModel.loadUniverse() }
            }

            HStack(spacing: 18) {
                cap("PE(TTM) ≤", value: $viewModel.maxPE, format: "%.0f")
                cap("PB ≤", value: $viewModel.maxPB, format: "%.1f")
                cap("市值 ≥（亿）", value: $viewModel.minMarketCapYi, format: "%.0f")
                VStack(alignment: .leading, spacing: 2) {
                    Text("深度分析前").font(.caption).foregroundStyle(.secondary)
                    Stepper("\(viewModel.deepCount) 只", value: $viewModel.deepCount, in: 1...100)
                }
                Spacer()
                Button {
                    viewModel.applyFilters()
                    Task { await viewModel.deepScan() }
                } label: {
                    if viewModel.isDeepScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("开始筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.universe.isEmpty || viewModel.isDeepScanning)
            }

            HStack {
                if viewModel.universe.isEmpty {
                    Text("尚未加载市场数据")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("全市场 \(viewModel.universe.count) 只 · 估值粗筛通过 \(viewModel.filtered.count) 只")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.market == .us, let remain = viewModel.avRemaining {
                        Text(remain < 3 ? "⚠️ Alpha Vantage 剩余 \(remain) 次，深度分析将受限" : "Alpha Vantage 今日剩余 \(remain) 次")
                            .font(.callout)
                            .foregroundStyle(remain < 3 ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func cap(_ title: String, value: Binding<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultArea: some View {
        if viewModel.isDeepScanning {
            VStack(spacing: 8) {
                ProgressView(value: progressFraction)
                Text(viewModel.universeProgress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        if viewModel.results.isEmpty && !viewModel.isDeepScanning {
            Text(viewModel.filtered.isEmpty
                 ? "没有股票通过估值粗筛，请放宽条件（PE / PB / 市值）"
                 : "共 \(viewModel.filtered.count) 只通过粗筛。点击「开始筛选」进行巴菲特深度分析")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if !viewModel.results.isEmpty {
            resultsTable
        }
        if viewModel.deepFailed > 0 {
            Text("⚠️ \(viewModel.deepFailed) 只深度分析失败（Alpha Vantage 配额不足或未配置 Key，可到设置填写后重试）")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 20)
        }
    }

    private var progressFraction: Double {
        guard viewModel.deepCount > 0 else { return 0 }
        return min(1, Double(viewModel.results.count) / Double(viewModel.deepCount))
    }

    private var resultsTable: some View {
        Table(viewModel.results) {
            TableColumn("公司") { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.row.name).font(.body.weight(.medium))
                    Text("\(r.row.ticker) · \(r.row.market.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .width(min: 140, ideal: 170)

            TableColumn("结论") { r in
                HStack(spacing: 4) {
                    Text(r.score.verdict.icon)
                    Text(r.score.verdict.title)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(verdictColor(r.score.verdict))
            }
            .width(min: 90, ideal: 100)

            TableColumn("总分") { r in
                Text("\(Int(r.score.totalScore))")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor(r.score.totalScore))
            }
            .width(60)

            TableColumn("现价") { r in
                Text(Formatting.price(r.quote.price, currency: r.quote.currency))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 90)

            TableColumn("内在价值") { r in
                if let iv = r.score.valuation.intrinsicValuePerShare {
                    Text(Formatting.price(iv, currency: r.quote.currency)).monospacedDigit()
                } else { Text("—").foregroundStyle(.secondary) }
            }
            .width(min: 90, ideal: 100)

            TableColumn("安全边际") { r in
                if let mos = r.score.valuation.marginOfSafety {
                    Text(Formatting.percent(mos))
                        .monospacedDigit()
                        .foregroundStyle(mos >= 0 ? .green : .red)
                } else { Text("—").foregroundStyle(.secondary) }
            }
            .width(min: 90, ideal: 100)

            TableColumn("ROE") { r in
                if let roe = r.fundamentals.snapshots.first?.roe {
                    Text(Formatting.percent(roe)).monospacedDigit()
                } else { Text("—").foregroundStyle(.secondary) }
            }
            .width(min: 70, ideal: 80)

            TableColumn("资产负债率") { r in
                if let dta = r.fundamentals.snapshots.first?.debtToAsset {
                    Text(Formatting.percent(dta)).monospacedDigit()
                } else { Text("—").foregroundStyle(.secondary) }
            }
            .width(min: 90, ideal: 100)
        }
        .contextMenu(forSelectionType: ScreenerResult.ID.self) { ids in
            if let id = ids.first, let result = viewModel.results.first(where: { $0.id == id }) {
                Button("查看完整报告") {
                    selectedSymbol = Symbol(ticker: result.row.ticker, market: result.row.market)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let result = viewModel.results.first(where: { $0.id == id }) {
                selectedSymbol = Symbol(ticker: result.row.ticker, market: result.row.market)
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("全市场巴菲特筛选")
                .font(.title3.weight(.semibold))
            Text("选择市场后自动加载全市场数据，设定估值条件，深度分析前 N 只输出评分与结论")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verdictColor(_ v: Verdict) -> Color {
        switch v {
        case .buyRange: return .green
        case .watch: return .orange
        case .avoid: return .red
        case .dataInsufficient: return .secondary
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
}
