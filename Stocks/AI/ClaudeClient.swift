import Foundation

/// Anthropic Messages API 客户端（URLSession REST，无 SDK 依赖）。
/// 请求格式遵循 claude-api skill 确认的规范：
/// - POST https://api.anthropic.com/v1/messages
/// - 头：x-api-key + anthropic-version: 2023-06-01
/// - **不传** temperature/top_p/budget_tokens（Opus/Sonnet 5 会 400 拒绝）
/// - 处理 stop_reason == "refusal"
nonisolated final class ClaudeClient: @unchecked Sendable {
    private let session: URLSession
    private let apiKey: () -> String?

    init(session: URLSession = .shared, apiKey: @escaping () -> String?) {
        self.session = session
        self.apiKey = apiKey
    }

    // MARK: - 请求结构

    struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: [SystemBlock]?
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    struct SystemBlock: Encodable {
        let type = "text"
        let text: String
        let cacheControl: CacheControl

        enum CodingKeys: String, CodingKey {
            case type, text
            case cacheControl = "cache_control"
        }
    }

    struct CacheControl: Encodable {
        let type = "ephemeral"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseBody: Decodable {
        let content: [ContentBlock]
        let stopReason: String?

        struct ContentBlock: Decodable {
            let type: String?
            let text: String?
        }

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    struct ErrorBody: Decodable {
        let error: APIError?
        struct APIError: Decodable {
            let message: String?
        }
    }

    // MARK: - 调用

    /// 发送一次分析请求，返回拼接后的全部文本块。
    func analyze(model: String, systemPrompt: String, userPrompt: String, maxTokens: Int = 16000) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else {
            throw ClaudeError.noKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            system: [SystemBlock(text: systemPrompt, cacheControl: CacheControl())],
            messages: [Message(role: "user", content: userPrompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.network }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ClaudeError.invalidKey
        case 429:
            throw ClaudeError.rateLimited
        default:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message ?? "未知错误"
            throw ClaudeError.http(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if decoded.stopReason == "refusal" {
            throw ClaudeError.refused
        }
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw ClaudeError.empty }
        return text
    }

    // MARK: - 错误

    enum ClaudeError: LocalizedError {
        case noKey
        case invalidKey
        case rateLimited
        case refused
        case http(Int, String)
        case network
        case empty

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "未配置 Anthropic API Key（设置 → AI 服务）"
            case .invalidKey:
                return "Anthropic API Key 无效，请检查设置"
            case .rateLimited:
                return "Anthropic 请求过于频繁，请稍后再试"
            case .refused:
                return "本次分析请求被安全策略拒绝，请稍后再试"
            case .http(let code, let msg):
                return "Anthropic 服务错误（HTTP \(code)）：\(msg)"
            case .network:
                return "网络错误：无法连接 Anthropic 服务"
            case .empty:
                return "AI 分析返回为空，请重试"
            }
        }
    }
}
