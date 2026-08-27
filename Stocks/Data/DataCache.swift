import Foundation

/// 带 TTL 的进程内缓存（JSON 编码存储，线程安全）。
actor DataCache {
    private struct Entry {
        let data: Data
        let expiresAt: Date
    }

    private var storage: [String: Entry] = [:]

    init() {}

    func value<T: Codable>(for key: String) -> T? {
        guard let entry = storage[key], entry.expiresAt > Date() else { return nil }
        return try? JSONDecoder().decode(T.self, from: entry.data)
    }

    func set<T: Codable>(_ value: T, for key: String, ttl: TimeInterval) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        storage[key] = Entry(data: data, expiresAt: Date().addingTimeInterval(ttl))
    }

    func remove(_ key: String) {
        storage.removeValue(forKey: key)
    }
}
