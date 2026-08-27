import Foundation

/// 每主机令牌桶限速器：限制对同一数据源的请求频率，避免被封 IP。
actor RateLimiter {
    private struct Slot {
        var lastRequest: Date
        var interval: TimeInterval
    }

    private var slots: [String: Slot] = [:]

    init() {}

    /// 等待直到允许向 `host` 发起下一次请求（不足间隔则休眠补齐）
    func waitForSlot(_ host: String, interval: TimeInterval) async {
        let now = Date()
        if let slot = slots[host] {
            let elapsed = now.timeIntervalSince(slot.lastRequest)
            if elapsed < slot.interval {
                let waitNs = UInt64((slot.interval - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: waitNs)
            }
        }
        slots[host] = Slot(lastRequest: Date(), interval: interval)
    }
}

/// 每日请求配额计数器（如 FMP 免费档 250 次/天），按本地日历日重置。
actor DailyBudget {
    private let limit: Int
    private var currentDay: Int
    private var used: Int
    private let calendar = Calendar.current

    init(limit: Int) {
        self.limit = limit
        self.currentDay = Self.dayNumber(calendar: calendar)
        self.used = 0
    }

    private static func dayNumber(calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        return (comps.year ?? 0) * 10000 + (comps.month ?? 0) * 100 + (comps.day ?? 0)
    }

    private func rollOverIfNeeded() {
        let day = Self.dayNumber(calendar: calendar)
        if day != currentDay {
            currentDay = day
            used = 0
        }
    }

    /// 尝试消耗一个配额；当天已用尽返回 false
    func take() -> Bool {
        rollOverIfNeeded()
        guard used < limit else { return false }
        used += 1
        return true
    }

    /// 今日剩余配额
    var remaining: Int {
        rollOverIfNeeded()
        return max(0, limit - used)
    }
}
