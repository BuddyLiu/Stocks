import SwiftUI
import Charts

/// K 线/折线图（Swift Charts），Apple Stocks 风格：
/// 收盘价折线 + 渐变面积，悬停显示十字线与日期/价格气泡
struct PriceChartView: View {
    let bars: [PriceBar]
    let range: PriceRange
    var currency: String = ""

    @State private var selectedBar: PriceBar?

    private var isCompact: Bool { range == .day }

    var body: some View {
        Group {
            if bars.isEmpty {
                Text("暂无历史数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        Chart(bars) { bar in
            AreaMark(
                x: .value("日期", bar.date),
                y: .value("价格", bar.close)
            )
            .foregroundStyle(LinearGradient(
                colors: [.blue.opacity(0.18), .blue.opacity(0.0)],
                startPoint: .top, endPoint: .bottom
            ))

            LineMark(
                x: .value("日期", bar.date),
                y: .value("价格", bar.close)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.8))

            if let selectedBar, bar.date == selectedBar.date {
                RuleMark(x: .value("日期", bar.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 6) {
                        tooltip(selectedBar)
                    }
                PointMark(
                    x: .value("日期", bar.date),
                    y: .value("价格", bar.close)
                )
                .foregroundStyle(.blue)
                .symbolSize(60)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: isCompact ? 5 : 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: isCompact
                               ? .dateTime.hour().minute()
                               : .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let date: Date = proxy.value(atX: location.x),
                               let nearest = nearestBar(to: date) {
                                selectedBar = nearest
                            }
                        case .ended:
                            selectedBar = nil
                        }
                    }
            }
        }
    }

    private func nearestBar(to date: Date) -> PriceBar? {
        bars.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func tooltip(_ bar: PriceBar) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Formatting.date(bar.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text("开 \(Formatting.price(bar.open, currency: currency))")
                Text("高 \(Formatting.price(bar.high, currency: currency))")
                Text("低 \(Formatting.price(bar.low, currency: currency))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(Formatting.price(bar.close, currency: currency))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
