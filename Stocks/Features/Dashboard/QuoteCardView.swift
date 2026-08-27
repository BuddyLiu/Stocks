import SwiftUI

/// 行情卡片：大字号现价 + 涨跌 + 关键指标（Apple Stocks 风格）
struct QuoteCardView: View {
    let symbol: Symbol
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Text(quote.companyName ?? symbol.ticker)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(symbol.market.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(Formatting.price(quote.price, currency: quote.currency))
                    .font(.system(size: 42, weight: .semibold))
                    .monospacedDigit()
                ChangeLabel(quote: quote, symbol: symbol)
                    .font(.title3)
            }

            HStack(spacing: 28) {
                stat("今开/昨收", "— / \(Formatting.price(quote.previousClose, currency: quote.currency))")
                stat("52周高", quote.fiftyTwoWeekHigh.map { Formatting.price($0, currency: quote.currency) } ?? "—")
                stat("52周低", quote.fiftyTwoWeekLow.map { Formatting.price($0, currency: quote.currency) } ?? "—")
                stat("币种", quote.currency)
                if let t = quote.timestamp {
                    stat("时间", Formatting.timeHM(t))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }
}
