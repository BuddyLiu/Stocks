import Foundation
import SwiftUI

/// 中文数字/货币/百分比格式化工具
enum Formatting {
    /// 货币符号
    static func currencySymbol(_ currency: String) -> String {
        switch currency.uppercased() {
        case "USD", "US": return "$"
        case "CNY", "CNH", "CN": return "¥"
        case "HKD", "HK": return "HK$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return "\(currency) "
        }
    }

    /// 价格：保留 2 位小数（小额保留 4 位）
    static func price(_ value: Double, currency: String = "") -> String {
        let sym = currencySymbol(currency)
        let digits = value < 1 ? 4 : 2
        return sym + String(format: "%.\(digits)f", value)
    }

    /// 涨跌幅（带符号 + 号）
    static func percent(_ fraction: Double, withSign: Bool = true) -> String {
        let sign = withSign ? (fraction >= 0 ? "+" : "") : ""
        return sign + String(format: "%.2f%%", fraction * 100)
    }

    /// 涨跌额（带符号 + 号）
    static func signed(_ value: Double, currency: String = "") -> String {
        let sym = currencySymbol(currency)
        let sign = value >= 0 ? "+" : ""
        let digits = abs(value) < 1 ? 4 : 2
        return sign + sym + String(format: "%.\(digits)f", value)
    }

    /// 大数缩写：1.2万亿 / 3.45亿 / 8.9百万
    static func compactLargeNumber(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1e12...:
            return "\(sign)\(String(format: "%.2f", absValue / 1e12))万亿"
        case 1e8...:
            return "\(sign)\(String(format: "%.2f", absValue / 1e8))亿"
        case 1e4...:
            return "\(sign)\(String(format: "%.2f", absValue / 1e4))万"
        default:
            return "\(sign)\(String(format: "%.0f", absValue))"
        }
    }

    /// 日期：yyyy-MM-dd
    static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 时间：HH:mm
    static func timeHM(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// 涨跌颜色习惯
enum ChangeColorStyle: String, CaseIterable, Identifiable {
    case auto      // 按市场自适应：美股绿涨红跌 / A股红涨绿跌
    case apple     // 同苹果股市 App：绿涨红跌
    case cn        // A股习惯：红涨绿跌

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "按市场自适应"
        case .apple: return "绿涨红跌（Apple）"
        case .cn: return "红涨绿跌（A股）"
        }
    }
}

extension Color {
    /// 涨跌颜色（支持负数按"跌"处理）
    static func change(percent: Double, market: Market, style: ChangeColorStyle) -> Color {
        let up = percent >= 0
        return change(isUp: up, market: market, style: style)
    }

    static func change(isUp: Bool, market: Market, style: ChangeColorStyle) -> Color {
        let redUp = (style == .cn) || (style == .auto && market == .cn)
        let up = isUp
        if redUp {
            return up ? .red : .green
        } else {
            return up ? .green : .red
        }
    }
}
