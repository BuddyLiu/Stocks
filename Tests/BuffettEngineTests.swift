import Foundation

@main
struct EngineTests {
    static func snapshot(year: Int, revenue: Double?, netIncome: Double?, eps: Double?, roe: Double?, netMargin: Double?,
                  debtToEquity: Double?, debtToAsset: Double?, interestCoverage: Double?, fcf: Double?,
                  totalEquity: Double?, totalDebt: Double?, cash: Double?, shares: Double?) -> FinancialSnapshot {
        FinancialSnapshot(year: year, revenue: revenue, netIncome: netIncome, eps: eps,
                          roe: roe, grossMargin: nil, netMargin: netMargin,
                          debtToEquity: debtToEquity, debtToAsset: debtToAsset, interestCoverage: interestCoverage,
                          freeCashFlow: fcf, totalEquity: totalEquity, totalDebt: totalDebt,
                          cashAndEquivalents: cash, sharesOutstanding: shares)
    }

    static var failures = 0
    static func check(_ cond: Bool, _ msg: String) {
        if cond { print("  ✅ \(msg)") }
        else { failures += 1; print("  ❌ \(msg)") }
    }

    static let great = [
        snapshot(year: 2020, revenue: 200, netIncome: 30, eps: 1.5, roe: 0.30, netMargin: 0.15,
                 debtToEquity: 0.4, debtToAsset: nil, interestCoverage: 12, fcf: 22,
                 totalEquity: 100, totalDebt: 40, cash: 30, shares: 20),
        snapshot(year: 2021, revenue: 220, netIncome: 33, eps: 1.65, roe: 0.30, netMargin: 0.15,
                 debtToEquity: 0.4, debtToAsset: nil, interestCoverage: 13, fcf: 24,
                 totalEquity: 110, totalDebt: 44, cash: 34, shares: 20),
        snapshot(year: 2022, revenue: 250, netIncome: 38, eps: 1.9, roe: 0.31, netMargin: 0.15,
                 debtToEquity: 0.42, debtToAsset: nil, interestCoverage: 14, fcf: 27,
                 totalEquity: 122, totalDebt: 50, cash: 38, shares: 20),
        snapshot(year: 2023, revenue: 280, netIncome: 43, eps: 2.15, roe: 0.32, netMargin: 0.15,
                 debtToEquity: 0.4, debtToAsset: nil, interestCoverage: 15, fcf: 30,
                 totalEquity: 135, totalDebt: 54, cash: 42, shares: 20),
        snapshot(year: 2024, revenue: 310, netIncome: 48, eps: 2.4, roe: 0.32, netMargin: 0.155,
                 debtToEquity: 0.38, debtToAsset: nil, interestCoverage: 16, fcf: 33,
                 totalEquity: 150, totalDebt: 57, cash: 46, shares: 20),
    ]

    static func main() {
        // ===== 案例 1a：优质公司 + 便宜价格 → 买入区间 =====
        let cheapBundle = FundamentalsBundle(symbol: "TEST", market: .us, snapshots: great, currency: "USD", generatedAt: Date())
        let cheapQuote = Quote(price: 20, previousClose: 19.9, currency: "USD", marketCap: 400, peTTM: 8, pb: 1.3, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "测试公司", timestamp: nil)
        print("案例 1a：优质公司 5 年，现价 20（安全边际充足）")
        let s1 = BuffettEngine.analyze(fundamentals: cheapBundle, quote: cheapQuote)
        print("  总分 \(Int(s1.totalScore)) 结论 \(s1.verdict.title) 安全边际 \(s1.valuation.marginOfSafety.map { String(format: "%.1f%%", $0*100) } ?? "nil")")
        check(s1.verdict == .buyRange, "应为买入区间")
        check(s1.redFlags.isEmpty, "无红旗")
        check(s1.pillars.count == 5, "5 个维度")
        let weights = s1.pillars.map(\.weight).reduce(0,+)
        check(abs(weights - 1.0) < 0.001, "权重合计 = 1")
        check(s1.totalScore >= 70, "总分 ≥ 70")

        // ===== 案例 1b：同一家公司，价格过高 → 回避（安全边际≤0）=====
        let expensiveQuote = Quote(price: 100, previousClose: 99, currency: "USD", marketCap: 2000, peTTM: 25, pb: 5, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "测试公司", timestamp: nil)
        print("\n案例 1b：同一家公司，现价 100（远超内在价值）")
        let s1b = BuffettEngine.analyze(fundamentals: cheapBundle, quote: expensiveQuote)
        print("  总分 \(Int(s1b.totalScore)) 结论 \(s1b.verdict.title) 安全边际 \(s1b.valuation.marginOfSafety.map { String(format: "%.1f%%", $0*100) } ?? "nil")")
        check(s1b.verdict == .avoid, "价格过高应回避（安全边际为负）")

        // ===== 案例 2：亏损公司 → 回避 + 红旗 =====
        let bad = [
            snapshot(year: 2021, revenue: 100, netIncome: -10, eps: -1.0, roe: -0.2, netMargin: -0.1,
                     debtToEquity: 3.0, debtToAsset: nil, interestCoverage: 0.5, fcf: -5,
                     totalEquity: -10, totalDebt: 100, cash: 5, shares: 20),
            snapshot(year: 2022, revenue: 90, netIncome: -15, eps: -1.5, roe: -0.3, netMargin: -0.17,
                     debtToEquity: 4.0, debtToAsset: nil, interestCoverage: 0.3, fcf: -8,
                     totalEquity: -20, totalDebt: 120, cash: 3, shares: 20),
            snapshot(year: 2023, revenue: 80, netIncome: -20, eps: -2.0, roe: -0.4, netMargin: -0.25,
                     debtToEquity: 5.0, debtToAsset: nil, interestCoverage: 0.2, fcf: -10,
                     totalEquity: -30, totalDebt: 140, cash: 2, shares: 20),
        ]
        let badBundle = FundamentalsBundle(symbol: "BAD", market: .us, snapshots: bad, currency: "USD", generatedAt: Date())
        let badQuote = Quote(price: 5, previousClose: 5, currency: "USD", marketCap: 100, peTTM: nil, pb: 0.5, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "差公司", timestamp: nil)
        print("\n案例 2：连续亏损 + 净资产为负")
        let s2 = BuffettEngine.analyze(fundamentals: badBundle, quote: badQuote)
        check(s2.verdict == .avoid, "应为回避（红旗）")
        check(s2.redFlags.count >= 2, "红旗至少 2 项（净资产为负 + 亏损年）")

        // ===== 案例 3：DCF 数学（FCF=10 恒定、净现金 0、股本=10）=====
        let flat = (2020...2024).map { y in
            snapshot(year: y, revenue: 100, netIncome: 10, eps: 1, roe: 0.1, netMargin: 0.1,
                     debtToEquity: 0.2, debtToAsset: nil, interestCoverage: 8, fcf: 10,
                     totalEquity: 100, totalDebt: 0, cash: 0, shares: 10)
        }
        let dcf = DCF.compute(snapshots: flat, price: 10)
        print("\n案例 3：DCF 数学（FCF=10 恒定，股本=10，现价=10）")
        if let iv = dcf.intrinsicValuePerShare, let mos = dcf.marginOfSafety {
            let expectedIV = 10*(1-pow(1.1,-10))/0.1 + (10*1.025/0.075)/pow(1.1,10)
            check(abs(iv - expectedIV/10) < 0.01, "每股内在价值 ≈ \(String(format: "%.2f", expectedIV/10))（实得 \(String(format: "%.2f", iv))）")
            check(mos > 0 && mos < 0.15, "安全边际 ≈ 12%（实得 \(String(format: "%.1f%%", mos*100))）")
            check(dcf.growthRate == 0, "FCF 恒定 → g = 0（实得 \(String(format: "%.1f%%", (dcf.growthRate ?? 0)*100))）")
        } else { check(false, "DCF 应可计算") }

        // ===== 案例 4：FCF 为负（3 年）→ 无法估值 → 回避 =====
        let negFCF = (2021...2023).map { y in
            snapshot(year: y, revenue: 100, netIncome: 15, eps: 1.5, roe: 0.2, netMargin: 0.15,
                     debtToEquity: 0.3, debtToAsset: nil, interestCoverage: 10, fcf: -5,
                     totalEquity: 80, totalDebt: 20, cash: 10, shares: 10)
        }
        let negBundle = FundamentalsBundle(symbol: "NEG", market: .us, snapshots: negFCF, currency: "USD", generatedAt: Date())
        let negQuote = Quote(price: 30, previousClose: 30, currency: "USD", marketCap: 300, peTTM: 20, pb: 3.5, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "负现金流", timestamp: nil)
        print("\n案例 4：FCF 持续为负（3 年）")
        let s4 = BuffettEngine.analyze(fundamentals: negBundle, quote: negQuote)
        check(!s4.valuation.isComputed, "DCF 不可计算")
        check(s4.verdict == .avoid, "应为回避")
        check(s4.redFlags.contains("自由现金流半数以上为负"), "红旗含 FCF 持续为负")

        // ===== 案例 5：数据覆盖不足 → 数据不足 =====
        let sparse = [
            snapshot(year: 2023, revenue: 100, netIncome: 10, eps: 1, roe: 0.1, netMargin: 0.1,
                     debtToEquity: 0.5, debtToAsset: nil, interestCoverage: 5, fcf: 10,
                     totalEquity: 100, totalDebt: 50, cash: 10, shares: 10),
        ]
        let sparseBundle = FundamentalsBundle(symbol: "SP", market: .us, snapshots: sparse, currency: "USD", generatedAt: Date())
        print("\n案例 5：仅 1 年数据")
        let s5 = BuffettEngine.analyze(fundamentals: sparseBundle, quote: negQuote)
        check(s5.verdict == .dataInsufficient, "应为数据不足")

        // ===== 案例 6：A股 资产负债率口径 =====
        let cn = (2021...2023).map { y in
            snapshot(year: y, revenue: 200, netIncome: 30, eps: 1.5, roe: 0.25, netMargin: 0.15,
                     debtToEquity: nil, debtToAsset: 0.45, interestCoverage: 9, fcf: 25,
                     totalEquity: 120, totalDebt: 30, cash: 50, shares: 10)
        }
        let cnBundle = FundamentalsBundle(symbol: "600000", market: .cn, snapshots: cn, currency: "CNY", generatedAt: Date())
        let cnQuote = Quote(price: 20, previousClose: 25, currency: "CNY", marketCap: 250, peTTM: 12, pb: 2, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "测试银行", timestamp: nil)
        print("\n案例 6：A股 资产负债率 45%（非金融）")
        let s6 = BuffettEngine.analyze(fundamentals: cnBundle, quote: cnQuote)
        check(s6.verdict == .buyRange, "A股优质 + 低负债 + 低估 → 买入区间（实得 \(s6.verdict.title)）")

        // ===== 案例 7：金融股杠杆豁免（银行 90% 资产负债率）=====
        let bankSnaps = (2021...2023).map { y in
            snapshot(year: y, revenue: 200, netIncome: 30, eps: 1.5, roe: 0.12, netMargin: 0.35,
                     debtToEquity: nil, debtToAsset: 0.90, interestCoverage: 10, fcf: 25,
                     totalEquity: 120, totalDebt: 300, cash: 300, shares: 10)
        }
        let bankQuote = Quote(price: 20, previousClose: 20, currency: "CNY", marketCap: 200, peTTM: 8, pb: 1.2, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "测试银行", timestamp: nil)
        let bankBundle = FundamentalsBundle(symbol: "600000", market: .cn, snapshots: bankSnaps, currency: "CNY", generatedAt: Date(), industry: "银行")
        let sameBundleAsBank = FundamentalsBundle(symbol: "600000", market: .cn, snapshots: bankSnaps, currency: "CNY", generatedAt: Date(), industry: "白酒")
        print("\n案例 7：金融股杠杆豁免（银行 90% 资产负债率）")
        let s7 = BuffettEngine.analyze(fundamentals: bankBundle, quote: bankQuote)
        let s7NonFin = BuffettEngine.analyze(fundamentals: sameBundleAsBank, quote: bankQuote)
        let bankBS = s7.pillars.first { $0.key == "balanceSheet" }!
        let nonFinBS = s7NonFin.pillars.first { $0.key == "balanceSheet" }!
        check(bankBS.reasons.joined().contains("豁免"), "银行杠杆标准豁免（理由：\(bankBS.reasons.joined(separator: "；"))）")
        check(bankBS.score > nonFinBS.score, "银行版资产负债表得分 \(Int(bankBS.score)) 高于非金融版 \(Int(nonFinBS.score))")

        // ===== 案例 8：空快照不崩溃 → 数据不足 =====
        let emptyBundle = FundamentalsBundle(symbol: "EMPTY", market: .us, snapshots: [], currency: "USD", generatedAt: Date())
        print("\n案例 8：无财务数据")
        let s8 = BuffettEngine.analyze(fundamentals: emptyBundle, quote: bankQuote)
        check(s8.verdict == .dataInsufficient, "应为数据不足，不崩溃（实得 \(s8.verdict.title)）")

        // ===== 案例 9：负现金流 + 正营收 → 维度得分钳制在 [0,100]（回归：曾出现总分 -290）=====
        let extreme = (2021...2024).map { y in
            snapshot(year: y, revenue: 200, netIncome: 10, eps: 0.5, roe: 0.1, netMargin: 0.05,
                     debtToEquity: 0.8, debtToAsset: nil, interestCoverage: 3, fcf: -100,
                     totalEquity: 100, totalDebt: 60, cash: 20, shares: 10)
        }
        let extremeBundle = FundamentalsBundle(symbol: "EXT", market: .cn, snapshots: extreme, currency: "CNY", generatedAt: Date(), industry: "半导体")
        let extremeQuote = Quote(price: 30, previousClose: 30, currency: "CNY", marketCap: 300, peTTM: 100, pb: 3, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil, companyName: "极端公司", timestamp: nil)
        print("\n案例 9：极端财务数据得分钳制")
        let s9 = BuffettEngine.analyze(fundamentals: extremeBundle, quote: extremeQuote)
        check(s9.totalScore >= 0 && s9.totalScore <= 100, "总分钳制在 [0,100]（实得 \(Int(s9.totalScore))）")
        check(s9.pillars.allSatisfy { $0.score >= 0 && $0.score <= 100 }, "各维度均在 [0,100]")
        check(s9.verdict == .avoid, "FCF 为负 → 回避")

        print("\n\(failures == 0 ? "🎉 全部通过" : "⚠️ \(failures) 项失败")")
        exit(failures == 0 ? 0 : 1)
    }
}
