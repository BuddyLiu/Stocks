import SwiftUI

/// 涨跌标签：带符号涨跌额 + 涨跌幅，颜色按市场自适应
struct ChangeLabel: View {
    let quote: Quote
    let symbol: Symbol
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 5) {
            Text(Formatting.signed(quote.change, currency: quote.currency))
            Text(Formatting.percent(quote.changePercent))
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(Color.change(isUp: quote.isUp, market: symbol.market, style: settings.changeColorStyle))
        .monospacedDigit()
    }
}
