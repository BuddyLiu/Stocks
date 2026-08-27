import Foundation

/// 巴菲特定性分析提示词（中文）。
/// system 为稳定前缀（可 prompt 缓存）；user 为结构化财务数据 + 量化评分。
nonisolated enum BuffettAnalysisPrompts {

    /// 稳定 system 提示词：只做定性解释，不得更改量化结论。
    static let system: String = """
    你是一位严谨的价值投资分析师，严格参照沃伦·巴菲特的投资哲学工作。你的任务是在**确定性量化引擎已经算出的结论之外**，提供护城河、管理层、商业模式与风险的定性分析。

    ## 职责边界（必须遵守）
    1. 量化引擎已给出总分、结论（买入区间/观望/回避）与安全边际，基于公开财务数据计算、可复现。你**不得修改或质疑**这些数字与结论，只负责解释其背后的逻辑并补充定性判断。
    2. 如果财务数据覆盖年数有限（如仅 5 年），请明确标注「数据覆盖仅 N 年」的局限，避免过度外推。
    3. 只依据用户消息中提供的财务数据与指标作答，**不得编造**任何你没有看到的数字、事件或报道。
    4. 你无法看到实时新闻或管理层讲话，对管理层质量的判断只能基于财务数据中的线索（资本配置、利润率、现金流转化）。

    ## 输出要求
    - 使用中文，Markdown 格式，结构清晰。
    - 至少包含以下小节：
      ### 护城河评估
      判断护城河类型（无形资产/转换成本/网络效应/成本优势/有效规模）、强度（宽/窄/无）与可持续性，并用财务数据佐证（如毛利率水平）。
      ### 管理层与资本配置
      基于再投资回报、分红回购、现金流转化率等财务线索评估资本配置是否股东友好。
      ### 商业模式与能力圈
      商业模式是否简单可理解、未来十年能否预见经营走向；若看不懂请直说「超出能力圈」。
      ### 主要风险
      列出 2–4 条最实质的风险，包括数据覆盖局限。
      ### 结论
      重申量化结论，并给出 1–2 句人话总结。不要给出买入/卖出指令。
    - 全文控制在 400–600 字，避免空话套话。
    - 结尾固定附一行免责声明：本内容仅供研究参考，不构成投资建议。
    """

    /// 组装 user 消息：财务数据表 + 分项评分 + 估值结论
    static func userPrompt(symbol: Symbol, quote: Quote, fundamentals: FundamentalsBundle, score: BuffetScore) -> String {
        var lines: [String] = []

        lines.append("# 公司与行情")
        lines.append("- 代码：\(symbol.ticker)（\(symbol.market.displayName)）")
        lines.append("- 公司名：\(quote.companyName ?? symbol.ticker)")
        lines.append("- 现价：\(Self.money(quote.price, currency: quote.currency))")
        if let pe = quote.peTTM { lines.append("- PE(TTM)：\(Self.decimal(pe))") }
        if let pb = quote.pb { lines.append("- PB：\(Self.decimal(pb))") }
        if let cap = quote.marketCap { lines.append("- 总市值：\(Self.compact(cap))") }

        lines.append("")
        lines.append("# 年度财务数据（新 → 旧，共 \(fundamentals.coverageYears) 年）")
        lines.append("| 年份 | 营收 | 归母净利润 | EPS | ROE | 净利率 | D/E或资产负债率 | 自由现金流 |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for s in fundamentals.snapshots {
            let de = s.debtToEquity.map { Self.decimal($0) } ?? s.debtToAsset.map { Self.pct($0) } ?? "—"
            lines.append("| \(s.year) | \(s.revenue.map(Self.compact) ?? "—") | \(s.netIncome.map(Self.compact) ?? "—") | \(s.eps.map(Self.decimal) ?? "—") | \(s.roe.map(Self.pct) ?? "—") | \(s.netMargin.map(Self.pct) ?? "—") | \(de) | \(s.freeCashFlow.map(Self.compact) ?? "—") |")
        }

        lines.append("")
        lines.append("# 量化引擎评分（总分 \(Int(score.totalScore))，结论：\(score.verdict.title)）")
        for p in score.pillars {
            lines.append("- **\(p.title)**（权重 \(Int(p.weight * 100))%）：\(Int(p.score)) 分")
            for r in p.reasons { lines.append("  - \(r)") }
        }
        if !score.redFlags.isEmpty {
            lines.append("")
            lines.append("## 红旗")
            for f in score.redFlags { lines.append("- \(f)") }
        }

        lines.append("")
        lines.append("# 估值")
        let v = score.valuation
        if v.isComputed {
            lines.append("- DCF 每股内在价值：\(v.intrinsicValuePerShare.map { Self.money($0, currency: quote.currency) } ?? "—")")
            lines.append("- 安全边际：\(v.marginOfSafety.map(Self.pct) ?? "—")")
            lines.append("- 采用的增速 g：\(v.growthRate.map(Self.pct) ?? "—")，折现率 \(Self.pct(v.discountRate))，永续 \(Self.pct(v.terminalGrowthRate))")
        } else {
            lines.append("- 无法完成 DCF 估值：\(v.note)")
        }
        lines.append("- 结论理由：\(score.verdictReason)")

        lines.append("")
        lines.append("请基于以上数据，按 system 提示词的要求输出中文定性分析（Markdown）。")

        return lines.joined(separator: "\n")
    }

    // MARK: - 格式化

    private static func money(_ value: Double, currency: String) -> String {
        let sym: String
        switch currency.uppercased() {
        case "USD", "US": sym = "$"
        case "CNY", "CNH", "CN": sym = "¥"
        default: sym = "\(currency) "
        }
        return sym + String(format: "%.2f", value)
    }

    private static func pct(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func compact(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1e12...: return "\(sign)\(String(format: "%.1f", absValue / 1e12))万亿"
        case 1e8...:  return "\(sign)\(String(format: "%.1f", absValue / 1e8))亿"
        case 1e4...:  return "\(sign)\(String(format: "%.1f", absValue / 1e4))万"
        default:      return "\(sign)\(Int(absValue))"
        }
    }
}
