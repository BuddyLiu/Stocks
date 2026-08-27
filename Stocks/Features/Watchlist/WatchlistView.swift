import SwiftUI
import SwiftData

/// 自选股：列表展示实时行情，点按进入个股报告，可增删
struct WatchlistView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var service: MarketDataService
    @Environment(\.modelContext) private var context

    @Query(sort: \WatchItem.addedAt) private var items: [WatchItem]
    @State private var quotes: [String: Quote] = [:]
    @State private var selectedSymbol: Symbol?
    @State private var isAdding = false
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if let selectedSymbol {
                ReportView(symbol: selectedSymbol, settings: settings)
                    .id(selectedSymbol.id)
            } else if items.isEmpty {
                emptyPrompt
            } else {
                list
            }
        }
        .navigationTitle("自选股")
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
            AddSymbolSheet(title: "自选股") { symbol, name in
                add(symbol, name: name)
            }
        }
        .task(id: items.map(\.ticker).joined()) { refresh() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(items) { item in
                    WatchlistRow(item: item, quote: quotes[item.symbol.id])
                        .contentShape(Rectangle())
                        .onTapGesture { selectedSymbol = item.symbol }
                }
                .onDelete(perform: delete)
            } header: {
                Text("\(items.count) 只股票")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("还没有自选股")
                .font(.title3.weight(.semibold))
            Text("点击右上角 + 添加，例如 AAPL、600519")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func add(_ symbol: Symbol, name: String) {
        guard !items.contains(where: { $0.symbol == symbol }) else { return }
        let item = WatchItem(ticker: symbol.ticker, market: symbol.market, displayName: name)
        context.insert(item)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(items[index]) }
    }

    private func refresh() {
        guard !items.isEmpty else { return }
        isRefreshing = true
        let symbols = items.map(\.symbol)
        Task {
            let result = await service.quotes(for: symbols)
            await MainActor.run {
                quotes = result
                isRefreshing = false
            }
        }
    }
}

/// 单行：名称 / 代码 / 现价 / 涨跌
private struct WatchlistRow: View {
    let item: WatchItem
    let quote: Quote?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                Text(item.symbol.ticker + " · " + item.symbol.market.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatting.price(quote.price, currency: quote.currency))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    ChangeLabel(quote: quote, symbol: item.symbol)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
