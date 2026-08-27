import Foundation

/// 巴菲特五维度量化评分引擎（纯函数，nonisolated，可单测）。
/// 规则见 docs/STRATEGY.md §2：财务质量25 / 资产负债表20 / 盈利稳定与增长20 / 现金流15 / 估值与安全边际20。
/// 结论为确定性规则：量化结论由引擎决定，Claude 只解释、不覆盖。
nonisolated enum BuffettEngine {

    /// 全量分析入口：输入归一化财务快照 + 实时行情，输出评分与结论。
    static func analyze(fundamentals: FundamentalsBundle, quote: Quote, isFinancial: Bool? = nil) -> BuffetScore {
        let snapshots = fundamentals.snapshots  // 新 → 旧
        if snapshots.isEmpty {
            return BuffetScore(
                pillars: [], totalScore: 0, verdict: .dataInsufficient,
                verdictReason: "无财务数据，无法分析",
                valuation: DCFValuation(isComputed: false, intrinsicValuePerShare: nil, marginOfSafety: nil,
                                        growthRate: nil, discountRate: DCF.discountRate, terminalGrowthRate: DCF.terminalGrowthRate,
                                        netCash: nil, sharesOutstanding: nil, note: "无财务数据"),
                redFlags: [], coverageYears: 0
            )
        }
        let financial = isFinancial ?? isFinancialIndustry(fundamentals.industry)
        let valuation = DCF.compute(snapshots: snapshots, price: quote.price, isFinancial: financial)

        let quality = financialQuality(snapshots)
        let balance = balanceSheet(snapshots, market: fundamentals.market, isFinancial: financial)
        let stability = stabilityAndGrowth(snapshots, coverageYears: fundamentals.coverageYears)
        let cash = cashFlow(snapshots)

        let price = quote.price
        let mos = valuation.isComputed ? valuation.marginOfSafety : nil
        let pe = quote.peTTM
        let valuationPillar = valuationPillar(valuation: valuation, peTTM: pe)

        let pillars = [
            PillarScore(key: "quality", title: "财务质量", score: clamp(quality.score), weight: 0.25, reasons: quality.reasons),
            PillarScore(key: "balanceSheet", title: "资产负债表", score: clamp(balance.score), weight: 0.20, reasons: balance.reasons),
            PillarScore(key: "stability", title: "盈利稳定与增长", score: clamp(stability.score), weight: 0.20, reasons: stability.reasons),
            PillarScore(key: "cashFlow", title: "现金流", score: clamp(cash.score), weight: 0.15, reasons: cash.reasons),
            PillarScore(key: "valuation", title: "估值与安全边际", score: clamp(valuationPillar.score), weight: 0.20, reasons: valuationPillar.reasons),
        ]
        let total = pillars.reduce(0) { $0 + $1.weighted }

        let redFlags = collectRedFlags(snapshots)
        let verdict = decideVerdict(total: total, valuation: valuation, mos: mos, redFlags: redFlags, coverageYears: fundamentals.coverageYears, price: price)

        return BuffetScore(
            pillars: pillars,
            totalScore: total,
            verdict: verdict.0,
            verdictReason: verdict.1,
            valuation: valuation,
            redFlags: redFlags,
            coverageYears: fundamentals.coverageYears
        )
    }

    // MARK: - 维度评分

    /// 财务质量（25%）：近 5 年均 ROE≥15% 且稳定 + 净利率≥15%
    private static func financialQuality(_ snapshots: [FinancialSnapshot]) -> (score: Double, reasons: [String]) {
        let recent = Array(snapshots.prefix(5))
        let roes = recent.compactMap(\.roe).filter { $0 > -1 && $0 < 5 }  // 剔除明显异常
        let margins = recent.compactMap(\.netMargin).filter { $0 > -1 && $0 < 5 }

        var reasons: [String] = []

        guard !roes.isEmpty else {
            return (0, ["ROE 数据不足"])
        }
        let avgROE = roes.reduce(0, +) / Double(roes.count)
        let cv = coefficientOfVariation(roes)
        let stabilityFactor = stabilityFactor(cv)
        let roeScore = min(100, avgROE / 0.15 * 100) * stabilityFactor
        if avgROE >= 0.15 {
            reasons.append("近\(roes.count)年平均ROE \(pct(avgROE))，\(cv <= 0.3 ? "盈利稳定" : "波动偏大")")
        } else {
            reasons.append("近\(roes.count)年平均ROE \(pct(avgROE))，低于 15% 满分线")
        }

        var marginScore = 100.0
        if !margins.isEmpty {
            let avgNM = margins.reduce(0, +) / Double(margins.count)
            marginScore = min(100, avgNM / 0.15 * 100)
            reasons.append(avgNM >= 0.15 ? "平均净利率 \(pct(avgNM))，定价权强" : "平均净利率 \(pct(avgNM))，低于 15%")
        }

        return (0.6 * roeScore + 0.4 * marginScore, reasons)
    }

    /// 资产负债表（20%）：美股 D/E<1、A股 资产负债率<60%（金融股豁免）；利息保障≥5
    private static func balanceSheet(_ snapshots: [FinancialSnapshot], market: Market, isFinancial: Bool) -> (score: Double, reasons: [String]) {
        guard let latest = snapshots.first else { return (0, ["无财务数据"]) }
        var reasons: [String] = []
        var components: [(value: Double, weight: Double)] = []

        // 杠杆
        var leverageScore: Double?
        if isFinancial {
            leverageScore = 60
            reasons.append("金融股，杠杆标准豁免")
        } else if market == .us, let de = latest.debtToEquity {
            leverageScore = max(0, min(100, 100 - (de / 1.0) * 40))
            reasons.append("D/E \(decimal(de))，\(de < 1 ? "杠杆健康" : "杠杆偏高")")
        } else if market == .cn, let dta = latest.debtToAsset {
            leverageScore = max(0, min(100, 100 - (dta / 0.6) * 40))
            reasons.append("资产负债率 \(pct(dta))，\(dta < 0.6 ? "杠杆健康" : "杠杆偏高")")
        }
        if let leverageScore { components.append((leverageScore, 0.6)) }

        // 利息保障
        if let ic = latest.interestCoverage {
            let icScore = min(100, max(0, ic / 5 * 100))
            reasons.append("利息保障 \(decimal(ic)) 倍，\(ic >= 5 ? "付息无忧" : "付息承压")")
            components.append((icScore, 0.4))
        }

        guard !components.isEmpty else { return (0, ["负债数据不足"]) }
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let score = components.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
        return (score, reasons)
    }

    /// 盈利稳定与增长（20%）：无亏损年、EPS 正增长占比、复合增速；按覆盖年数缩放
    private static func stabilityAndGrowth(_ snapshots: [FinancialSnapshot], coverageYears: Int) -> (score: Double, reasons: [String]) {
        let sorted = snapshots.sorted { $0.year < $1.year }  // 旧 → 新
        var reasons: [String] = []

        // 亏损年
        let hasLoss = sorted.contains { s in
            if let ni = s.netIncome { return ni < 0 }
            if let eps = s.eps { return eps < 0 }
            return false
        }
        let lossCleanliness = hasLoss ? 20.0 : 100.0
        reasons.append(hasLoss ? "⚠️ 覆盖期内存在亏损年" : "覆盖 \(coverageYears) 年无亏损年")

        // EPS 逐年正增长占比
        var pairs = 0
        var positive = 0
        for i in 1..<sorted.count {
            guard let prev = sorted[i - 1].eps, let curr = sorted[i].eps, prev > 0 else { continue }
            pairs += 1
            if curr > prev { positive += 1 }
        }
        var growthScore = 0.0
        if pairs > 0 {
            let ratio = Double(positive) / Double(pairs)
            growthScore = min(100, ratio / (2.0 / 3.0) * 100)
            reasons.append("EPS 正增长年占 \(Int(ratio * 100))%")
        } else {
            reasons.append("EPS 序列数据不足，无法评估增长")
        }

        // EPS 复合增速
        if let first = sorted.first(where: { ($0.eps ?? 0) > 0 }),
           let last = sorted.last(where: { ($0.eps ?? 0) > 0 }),
           first.year != last.year {
            let years = Double(last.year - first.year)
            let cagr = pow(last.eps! / first.eps!, 1.0 / years) - 1
            if cagr <= 0 { growthScore *= 0.6 }
            reasons.append(cagr > 0 ? "EPS 复合增速 \(pct(cagr))" : "EPS 复合增速 \(pct(cagr))，成长不足")
        }

        // 数据覆盖缩放：目标 10 年，至少 5 年；不足按比例折减
        let coverageFactor = min(1.0, Double(coverageYears) / 10.0)
        let score = (0.5 * lossCleanliness + 0.5 * growthScore) * coverageFactor
        if coverageFactor < 1 { reasons.append("数据仅覆盖 \(coverageYears) 年，本维度得分按比例缩放") }
        return (score, reasons)
    }

    /// 现金流（15%）：FCF 多为正、FCF/净利润≥0.7、轻资产
    private static func cashFlow(_ snapshots: [FinancialSnapshot]) -> (score: Double, reasons: [String]) {
        let fcfList = snapshots.compactMap(\.freeCashFlow)
        guard !fcfList.isEmpty else { return (0, ["自由现金流数据不足"]) }
        var reasons: [String] = []

        let positiveCount = fcfList.filter { $0 > 0 }.count
        let positiveRatio = Double(positiveCount) / Double(fcfList.count)
        reasons.append("自由现金流正占比 \(Int(positiveRatio * 100))%")

        var fcfToNISum = 0.0
        var fcfToNICount = 0
        for s in snapshots {
            guard let fcf = s.freeCashFlow, let ni = s.netIncome, ni > 0 else { continue }
            fcfToNISum += fcf / ni
            fcfToNICount += 1
        }
        let fcfToNI = fcfToNICount > 0 ? fcfToNISum / Double(fcfToNICount) : 0
        reasons.append(fcfToNICount > 0 ? "FCF/净利润 \(decimal(fcfToNI))" : "FCF/净利润数据不足")

        var fcfMarginSum = 0.0
        var fcfMarginCount = 0
        for s in snapshots {
            guard let fcf = s.freeCashFlow, let rev = s.revenue, rev > 0 else { continue }
            fcfMarginSum += fcf / rev
            fcfMarginCount += 1
        }
        let fcfMargin = fcfMarginCount > 0 ? fcfMarginSum / Double(fcfMarginCount) : 0

        let posScore = positiveRatio * 100
        let niScore = fcfToNICount > 0 ? min(100, fcfToNI / 0.7 * 100) : 50
        let marginScore = fcfMarginCount > 0 ? min(100, fcfMargin / 0.10 * 100) : 50
        return (0.4 * posScore + 0.4 * niScore + 0.2 * marginScore, reasons)
    }

    /// 估值与安全边际（20%）：DCF 安全边际为主，PE 合理性为辅
    private static func valuationPillar(valuation: DCFValuation, peTTM: Double?) -> (score: Double, reasons: [String]) {
        var reasons: [String] = []
        var safetyScore = 0.0
        if let mos = valuation.marginOfSafety, valuation.isComputed {
            safetyScore = max(0, min(100, mos / 0.30 * 100))
            reasons.append(mos >= 0
                ? "DCF 安全边际 \(pct(mos))，\(mos >= 0.30 ? "显著打折" : "折让不足")"
                : "安全边际 \(pct(mos))，价格高于内在价值")
        } else {
            reasons.append(valuation.note)
        }

        var peScore = 50.0
        if let pe = peTTM {
            if pe <= 0 {
                peScore = 30
                reasons.append("PE(TTM) 为负，当前处于亏损/微利")
            } else if pe > 60 {
                peScore = 40
                reasons.append("PE(TTM) \(decimal(pe))，估值偏贵")
            } else {
                peScore = 100
                reasons.append("PE(TTM) \(decimal(pe))，估值合理")
            }
        }
        return (0.85 * safetyScore + 0.15 * peScore, reasons)
    }

    /// 金融股（银行/保险/证券/信托等）豁免 D/E、资产负债率标准
    private static func isFinancialIndustry(_ industry: String?) -> Bool {
        guard let industry else { return false }
        let keywords = ["银行", "保险", "证券", "信托", "多元金融", "金融"]
        return keywords.contains { industry.contains($0) }
    }

    /// 维度得分统一钳制到 [0, 100]
    private static func clamp(_ score: Double) -> Double {
        min(100, max(0, score))
    }

    // MARK: - 红旗与结论

    private static func collectRedFlags(_ snapshots: [FinancialSnapshot]) -> [String] {
        var flags: [String] = []
        let latest = snapshots.first
        if let eq = latest?.totalEquity, eq < 0 {
            flags.append("净资产为负")
        }
        let hasLoss = snapshots.contains { s in
            if let ni = s.netIncome { return ni < 0 }
            if let eps = s.eps { return eps < 0 }
            return false
        }
        if hasLoss { flags.append("覆盖期内存在亏损年") }
        let fcfList = snapshots.compactMap(\.freeCashFlow)
        if !fcfList.isEmpty {
            let negativeCount = fcfList.filter { $0 <= 0 }.count
            if Double(negativeCount) / Double(fcfList.count) >= 0.5 {
                flags.append("自由现金流半数以上为负")
            }
        }
        return flags
    }

    private static func decideVerdict(total: Double, valuation: DCFValuation, mos: Double?, redFlags: [String], coverageYears: Int, price: Double) -> (Verdict, String) {
        if coverageYears < 3 {
            return (.dataInsufficient, "财务数据仅覆盖 \(coverageYears) 年，不足以得出结论")
        }
        if !redFlags.isEmpty {
            return (.avoid, "出现红旗：\(redFlags.joined(separator: "、"))")
        }
        if !valuation.isComputed {
            return (.avoid, "自由现金流缺失或为负，安全边际不成立，无法估值")
        }
        guard let mos else { return (.avoid, "安全边际不可计算") }

        if (mos >= 0.30 && total >= 70) || (total >= 75 && mos >= 0.25) {
            return (.buyRange, "安全边际 \(pct(mos))，总分 \(Int(total))：低于保守内在价值，可分批建仓")
        }
        if mos <= 0 {
            return (.avoid, "安全边际 \(pct(mos)) ≤ 0，现价不低于内在价值，无安全垫")
        }
        if total < 50 {
            return (.avoid, "总分 \(Int(total)) 低于 50，公司质量不达标")
        }
        return (.watch, total >= 60
            ? "公司质量尚可（总分 \(Int(total))），但安全边际 \(pct(mos)) 不足，等待更好价格"
            : "总分 \(Int(total)) 与安全边际 \(pct(mos)) 均不足，观望")
    }

    // MARK: - 统计与格式化

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func stddev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        let variance = values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        guard abs(m) > 1e-9 else { return 1 }
        return stddev(values) / abs(m)
    }

    /// 稳定性系数：CV≤0.3 → 1.0；CV≥1.0 → 0.4；线性过渡
    private static func stabilityFactor(_ cv: Double) -> Double {
        if cv <= 0.3 { return 1.0 }
        if cv >= 1.0 { return 0.4 }
        return 1.0 - (cv - 0.3) / 0.7 * 0.6
    }

    private static func pct(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
