import SwiftUI

/// 输入股票代码并解析名称的弹窗（自选 / 持仓复用）。
/// 提交后先拉一次行情取中文名，成功回调 Symbol + 名称。
struct AddSymbolSheet: View {
    let title: String
    let onAdd: (Symbol, String) -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isResolving = false
    @State private var resolveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加\(title)")
                .font(.headline)
            TextField("输入代码，如 AAPL、600519", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(isResolving)

            if let resolveError {
                Text(resolveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isResolving ? "解析中…" : "添加") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func submit() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isResolving else { return }
        isResolving = true
        resolveError = nil

        let symbol = Symbol(input: input)
        Task {
            do {
                let quote = try await MarketDataService.shared.quote(for: symbol)
                let name = quote.companyName ?? symbol.ticker
                await MainActor.run {
                    isResolving = false
                    onAdd(symbol, name)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    resolveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
