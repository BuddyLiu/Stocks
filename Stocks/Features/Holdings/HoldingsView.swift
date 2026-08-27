import SwiftUI
import SwiftData

/// 持仓跟踪：数量 + 成本 + 实时盈亏；点按进入个股报告
struct HoldingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var service: MarketDataService
    @Environment(\.modelContext) private var context

    @Query(sort: \Holding.addedAt) private var holdings: [Holding]
    @State private var quotes: [String: Quote] = [:]
    @State private var selectedSymbol: Symbol?
    @State private var isAdding = false
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if let selectedSymbol {
                ReportView(symbol: selectedSymbol, settings: settings)
                    .id(selectedSymbol.id)
            } else if holdings.isEmpty {
                emptyPrompt
            } else {
                content
            }
        }
        .navigationTitle("持仓")
        .toolbar {
            ToolbarItemGroup {
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                Button { isAdding = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddHoldingSheet { symbol, name, qty, cost in
                add(symbol, name: name, quantity: qty, costBasis: cost)
            }
        }
        .task(id: holdings.map(\.ticker).joined()) { refresh() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            summaryHeader
            List {
                ForEach(holdings) { holding in
                    HoldingRow(holding: holding, quote: quotes[holding.symbol.id])
                        .contentShape(Rectangle())
                        .onTapGesture { selectedSymbol = holding.symbol }
                        .contextMenu {
                            Button("删除", role: .destructive) { context.delete(holding) }
                        }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.inset)
        }
    }

    /// 组合概览：总成本 / 总市值 / 总盈亏
    private var summaryHeader: some View {
        let totalCost = holdings.reduce(0) { $0 + $1.totalCost }
        let totalValue = holdings.reduce(0) { acc, h in
            guard let q = quotes[h.symbol.id] else { return acc }
            return acc + h.marketValue(price: q.price)
        }
        let profit = totalValue - totalCost
        let profitColor = Color.change(isUp: profit >= 0, market: holdings.first?.symbol.market ?? .us, style: settings.changeColorStyle)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总市值").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.compactLargeNumber(totalValue)).font(.title2.weight(.semibold)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("总盈亏").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(Formatting.signed(profit, currency: ""))
                        Text(Formatting.percent(totalCost > 0 ? profit / totalCost : 0))
                    }
                    .font(.title3.weight(.medium))
                    .foregroundStyle(profitColor)
                    .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("总成本").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.compactLargeNumber(totalCost)).font(.title3).monospacedDigit()
                }
            }
            Divider()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("还没有持仓")
                .font(.title3.weight(.semibold))
            Text("点击右上角 + 记录持仓数量与成本，跟踪实时盈亏")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func add(_ symbol: Symbol, name: String, quantity: Double, costBasis: Double) {
        guard !holdings.contains(where: { $0.symbol == symbol }) else {
            // 已存在则合并？v1 直接更新数量与成本
            if let existing = holdings.first(where: { $0.symbol == symbol }) {
                existing.quantity = quantity
                existing.costBasis = costBasis
            }
            return
        }
        let holding = Holding(ticker: symbol.ticker, market: symbol.market, displayName: name, quantity: quantity, costBasis: costBasis)
        context.insert(holding)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(holdings[index]) }
    }

    private func refresh() {
        guard !holdings.isEmpty else { return }
        isRefreshing = true
        let symbols = holdings.map(\.symbol)
        Task {
            let result = await service.quotes(for: symbols)
            await MainActor.run {
                quotes = result
                isRefreshing = false
            }
        }
    }
}

/// 单行：名称 / 数量×成本 / 现价 / 盈亏
private struct HoldingRow: View {
    @EnvironmentObject private var settings: AppSettings
    let holding: Holding
    let quote: Quote?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.displayName)
                    .font(.body.weight(.medium))
                Text("\(holding.symbol.ticker) · \(holding.symbol.market.displayName) · \(trim(holding.quantity))股")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let quote {
                let profit = holding.profit(price: quote.price)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatting.price(quote.price, currency: quote.currency))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        Text(Formatting.signed(profit, currency: quote.currency))
                        Text(Formatting.percent(holding.profitPercent(price: quote.price)))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.change(isUp: profit >= 0, market: holding.symbol.market, style: settings.changeColorStyle))
                    .monospacedDigit()
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}
