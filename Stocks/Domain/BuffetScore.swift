import Foundation

/// 单个维度的评分（0–100）+ 中文理由，保证可解释性
nonisolated struct PillarScore: Codable, Sendable, Hashable, Identifiable {
    var key: String          // 唯一标识
    var title: String        // 中文维度名
    var score: Double        // 0–100
    var weight: Double       // 权重（0–1）
    var reasons: [String]    // 中文理由

    var id: String { key }
    var weighted: Double { score * weight }
}

/// 投资结论（确定性规则，AI 不覆盖）
nonisolated enum Verdict: String, Codable, Sendable, Hashable {
    case buyRange          // 🟢 买入区间
    case watch             // 🟡 观望
    case avoid             // 🔴 回避
    case dataInsufficient  // ⚪ 数据不足

    var title: String {
        switch self {
        case .buyRange: return "买入区间"
        case .watch: return "观望"
        case .avoid: return "回避"
        case .dataInsufficient: return "数据不足"
        }
    }

    var icon: String {
        switch self {
        case .buyRange: return "🟢"
        case .watch: return "🟡"
        case .avoid: return "🔴"
        case .dataInsufficient: return "⚪"
        }
    }
}

/// DCF 估值结果（见 STRATEGY §3）
nonisolated struct DCFValuation: Codable, Sendable, Hashable {
    var isComputed: Bool               // FCF 为负/缺失时 false
    var intrinsicValuePerShare: Double?  // 每股内在价值
    var marginOfSafety: Double?          // 安全边际（小数，如 0.32 = 32%）
    var growthRate: Double?              // 采用的自由现金流增速（小数）
    var discountRate: Double             // 折现率
    var terminalGrowthRate: Double       // 永续增长率
    var netCash: Double?                 // 净现金（现金 − 有息负债）
    var sharesOutstanding: Double?       // 总股本
    var note: String                     // 中文说明
}

/// 巴菲特量化评分总结果
nonisolated struct BuffetScore: Codable, Sendable, Hashable {
    var pillars: [PillarScore]
    var totalScore: Double          // 加权总分 0–100
    var verdict: Verdict
    var verdictReason: String       // 结论的中文解释
    var valuation: DCFValuation
    var redFlags: [String]          // 红旗（任一存在即回避）
    var coverageYears: Int          // 数据覆盖年数

    var totalPillarScore: Double { pillars.reduce(0) { $0 + $1.weighted } }
}
