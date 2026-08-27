import SwiftUI

/// 设置：API Key（Keychain）、模型、涨跌颜色习惯
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var anthropicKey = ""
    @State private var alphaVantageKey = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("AI 服务") {
                SecureField("Anthropic API Key（用于 Claude 语义分析）", text: $anthropicKey)
                Button("保存 API Key") {
                    saveAnthropic()
                }
            }

            Section("数据源") {
                SecureField("Alpha Vantage API Key（免费注册，美股财务数据，每日 25 次）", text: $alphaVantageKey)
                Button("保存 Alpha Vantage Key") {
                    saveAlphaVantage()
                }
            }

            Section("偏好") {
                Picker("Claude 模型", selection: $settings.claudeModel) {
                    Text("claude-opus-5（最强）").tag("claude-opus-5")
                    Text("claude-sonnet-5（省钱）").tag("claude-sonnet-5")
                }
                Picker("涨跌颜色", selection: $settings.changeColorStyle) {
                    ForEach(ChangeColorStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section("说明") {
                Text("""
                API Key 仅保存在本机钥匙串（Keychain）中，仅用于调用对应服务。
                Alpha Vantage 免费档每日 25 次请求，用尽后当日将暂停美股财务刷新。
                若未填写 Claude Key，仍可正常使用量化评分，仅 AI 语义分析不可用。
                行情与 K 线（美股 + A股）来自东方财富，无需 Key。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .onAppear {
            anthropicKey = KeychainStore.load("anthropicKey") ?? ""
            alphaVantageKey = KeychainStore.load("alphaVantageKey") ?? ""
        }
    }

    private func saveAnthropic() {
        let value = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            KeychainStore.delete("anthropicKey")
        } else {
            do { try KeychainStore.save(value, key: "anthropicKey") }
            catch { showStatus(error.localizedDescription, isError: true); return }
        }
        showStatus("已保存 Claude API Key", isError: false)
    }

    private func saveAlphaVantage() {
        let value = alphaVantageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            KeychainStore.delete("alphaVantageKey")
        } else {
            do { try KeychainStore.save(value, key: "alphaVantageKey") }
            catch { showStatus(error.localizedDescription, isError: true); return }
        }
        showStatus("已保存 Alpha Vantage Key", isError: false)
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if statusMessage == message { statusMessage = nil }
        }
    }
}
