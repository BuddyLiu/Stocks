import Foundation

/// 市场枚举：美股 / A股
nonisolated enum Market: String, Codable, CaseIterable, Identifiable, Sendable {
    case us
    case cn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: return "美股"
        case .cn: return "A股"
        }
    }
}

/// 统一证券符号：美股用 ticker（如 AAPL），A股用 6 位代码（如 600519、000001）。
nonisolated struct Symbol: Hashable, Codable, Sendable, Identifiable {
    var ticker: String
    var market: Market

    var id: String { "\(market.rawValue):\(ticker)" }

    init(ticker: String, market: Market) {
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.market = market
    }

    /// 东方财富 secid（主选）：`1.`=沪/科创，`0.`=深/创业板；美股 `105.`=NASDAQ、`106.`=NYSE
    var eastmoneySecID: String {
        switch market {
        case .cn:
            return (ticker.hasPrefix("6") ? "1." : "0.") + ticker
        case .us:
            return "105." + ticker
        }
    }

    /// 东方财富 secid 候选（美股需在 105/106 间探测）
    var eastmoneySecIDs: [String] {
        switch market {
        case .cn:
            return [eastmoneySecID]
        case .us:
            return ["105.\(ticker)", "106.\(ticker)"]
        }
    }

    /// 搜索字符串：用户输入（如 "AAPL"、"600519"、"贵州茅台"）
    var displayTicker: String { ticker }

    /// 交易所代码后缀（东方财富 F10 用）：沪 "600519.SH"、深 "000001.SZ"
    var secucode: String {
        switch market {
        case .cn:
            return ticker + (ticker.hasPrefix("6") ? ".SH" : ".SZ")
        case .us:
            return ticker
        }
    }

    /// 根据输入自动识别市场：6 位纯数字 → A股，否则美股
    init(input: String) {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if t.count == 6, t.allSatisfy(\.isNumber) {
            self.init(ticker: t, market: .cn)
        } else {
            self.init(ticker: t, market: .us)
        }
    }
}
