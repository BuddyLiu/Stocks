import SwiftUI

/// 股票分析入口：搜索代码 → 完整巴菲特报告
struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var symbol: Symbol?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField("输入股票代码，如 AAPL、600519", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(search)
                Button(action: search) {
                    Label("分析", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let symbol {
                ReportView(symbol: symbol, settings: settings)
                    .id(symbol.id)
                    .transition(.opacity)
            } else {
                emptyPrompt
            }
        }
        .padding(24)
        .navigationTitle("股票分析")
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("输入代码开始分析")
                .font(.title3.weight(.semibold))
            Text("支持美股（如 AAPL）与 A股（如 600519），输出量化评分 + DCF 估值 + AI 定性分析")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        symbol = Symbol(input: input)
    }
}
