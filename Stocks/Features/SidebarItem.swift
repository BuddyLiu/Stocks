import SwiftUI

/// 侧栏导航项
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case watchlist
    case holdings
    case screener
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "股票分析"
        case .watchlist: return "自选股"
        case .holdings: return "持仓"
        case .screener: return "筛选器"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "magnifyingglass"
        case .watchlist: return "star"
        case .holdings: return "briefcase"
        case .screener: return "line.3.horizontal.decrease.circle"
        case .settings: return "gearshape"
        }
    }
}
