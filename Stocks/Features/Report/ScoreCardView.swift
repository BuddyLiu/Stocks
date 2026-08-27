import SwiftUI

/// 巴菲特评分卡片：结论徽章 + 总分 + DCF 估值 + 分维度进度条 + 红旗
struct ScoreCardView: View {
    let score: BuffetScore
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !score.valuation.note.isEmpty && !score.valuation.isComputed {
                Text(score.valuation.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(score.pillars) { pillar in
                pillarRow(pillar)
            }

            if !score.redFlags.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("红旗（任一存在即回避）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    ForEach(score.redFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 头部：结论 + 总分 + DCF

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(score.verdict.icon)
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 3) {
                Text(score.verdict.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(verdictColor)
                Text("巴菲特评分 \(Int(score.totalScore)) / 100 · 数据覆盖 \(score.coverageYears) 年")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let iv = score.valuation.intrinsicValuePerShare {
                    Text("内在价值 \(Formatting.price(iv, currency: currency))")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    if let mos = score.valuation.marginOfSafety {
                        Text("安全边际 \(Formatting.percent(mos))")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(marginColor(mos))
                            .monospacedDigit()
                    }
                } else {
                    Text("无法估值")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 维度行

    private func pillarRow(_ pillar: PillarScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pillar.title)
                    .font(.callout.weight(.semibold))
                Text("权重 \(Int(pillar.weight * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pillar.score)) 分")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pillarTint(pillar.key))
            }
            ProgressView(value: pillar.score, total: 100)
                .tint(pillarTint(pillar.key))
            ForEach(pillar.reasons, id: \.self) { reason in
                Text("· \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 颜色

    private var verdictColor: Color {
        switch score.verdict {
        case .buyRange: return .green
        case .watch: return .orange
        case .avoid: return .red
        case .dataInsufficient: return .gray
        }
    }

    private func marginColor(_ mos: Double) -> Color {
        mos >= 0.30 ? .green : (mos > 0 ? .orange : .red)
    }

    private func pillarTint(_ key: String) -> Color {
        switch key {
        case "quality": return .blue
        case "balanceSheet": return .teal
        case "stability": return .indigo
        case "cashFlow": return .green
        case "valuation": return .orange
        default: return .gray
        }
    }
}
