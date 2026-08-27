import Foundation

/// 两阶段自由现金流折现模型（保守口径，纯函数，可单测）。
/// 规则见 docs/STRATEGY.md §3：
///   g = min(近 5 年 FCF 复合增速, 8%)，折现率 10%，永续增长率 2.5%
///   IV = Σ(t=1..10) FCF·(1+g)^t/(1.10)^t + TV/(1.10)^10 + 净现金
///  FCF 为负或缺失时安全边际不成立（回避），绝不硬算。
nonisolated enum DCF {
    static let discountRate = 0.10
    static let terminalGrowthRate = 0.025
    static let maxGrowthRate = 0.08

    /// 计算内在价值与安全边际。
    /// - Parameters:
    ///   - snapshots: 逐年财务快照（顺序任意，内部按年排序）
    ///   - price: 当前股价
    ///   - isFinancial: 金融股（银行/保险/证券）资产负债以吸收存款为主，净现金调整不适用
    static func compute(snapshots: [FinancialSnapshot], price: Double, isFinancial: Bool = false) -> DCFValuation {
        let sorted = snapshots.sorted { $0.year < $1.year }
        let fcfByYear: [(year: Int, fcf: Double)] = sorted.compactMap { s in
            guard let fcf = s.freeCashFlow else { return nil }
            return (s.year, fcf)
        }

        guard let latest = fcfByYear.last, latest.fcf > 0 else {
            return DCFValuation(
                isComputed: false,
                intrinsicValuePerShare: nil,
                marginOfSafety: nil,
                growthRate: nil,
                discountRate: discountRate,
                terminalGrowthRate: terminalGrowthRate,
                netCash: nil,
                sharesOutstanding: nil,
                note: "自由现金流缺失或为负，无法估值"
            )
        }

        // 增长 g：近 5 年 FCF 复合增速，上限 8%（负增速保持保守）
        var g = 0.0
        if fcfByYear.count >= 2, let first = fcfByYear.first, first.fcf > 0 {
            let years = max(1, latest.year - first.year)
            let cagr = pow(latest.fcf / first.fcf, 1.0 / Double(years)) - 1
            g = cagr
        }
        g = min(g, Self.maxGrowthRate)

        // 内在价值
        let r = discountRate
        let tgr = terminalGrowthRate
        var projected = latest.fcf
        var iv = 0.0
        for t in 1...10 {
            projected *= (1 + g)
            iv += projected / pow(1 + r, Double(t))
        }
        let tv = (latest.fcf * pow(1 + g, 10) * (1 + tgr)) / (r - tgr)
        iv += tv / pow(1 + r, 10)

        // 净现金 = 现金及等价物 − 有息负债（用最新年报）；金融股豁免（存款非债务）
        let netCash = isFinancial ? 0 : latestNetCash(in: sorted)
        iv += netCash

        // 每股内在价值
        let shares = latestShares(in: sorted)
        guard let shares, shares > 0 else {
            return DCFValuation(
                isComputed: false,
                intrinsicValuePerShare: nil,
                marginOfSafety: nil,
                growthRate: g,
                discountRate: r,
                terminalGrowthRate: tgr,
                netCash: netCash,
                sharesOutstanding: nil,
                note: "总股本缺失，无法计算每股价值"
            )
        }
        let perShare = iv / shares
        let margin = (perShare - price) / perShare

        return DCFValuation(
            isComputed: true,
            intrinsicValuePerShare: perShare,
            marginOfSafety: margin,
            growthRate: g,
            discountRate: r,
            terminalGrowthRate: tgr,
            netCash: netCash,
            sharesOutstanding: shares,
            note: "两阶段 DCF：增速 \(Self.percent(g))，折现 \(Self.percent(r))，永续 \(Self.percent(tgr))"
        )
    }

    private static func latestNetCash(in sorted: [FinancialSnapshot]) -> Double {
        for s in sorted.reversed() {
            if let cash = s.cashAndEquivalents {
                return cash - (s.totalDebt ?? 0)
            }
        }
        return 0
    }

    private static func latestShares(in sorted: [FinancialSnapshot]) -> Double? {
        for s in sorted.reversed() where s.sharesOutstanding != nil {
            return s.sharesOutstanding
        }
        return nil
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }
}
