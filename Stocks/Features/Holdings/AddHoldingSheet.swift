import SwiftUI

/// 新增持仓弹窗：选择代码 + 数量 + 每股成本
struct AddHoldingSheet: View {
    let onAdd: (Symbol, String, Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var quantity = ""
    @State private var cost = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增持仓")
                .font(.headline)
            TextField("输入代码，如 AAPL、600519", text: $query)
                .textFieldStyle(.roundedBorder)
                .disabled(isResolving)
            TextField("数量（股）", text: $quantity)
                .textFieldStyle(.roundedBorder)
            TextField("每股成本", text: $cost)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isResolving ? "解析中…" : "添加") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var isValid: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(quantity) != nil && Double(quantity)! > 0 &&
        Double(cost) != nil && Double(cost)! > 0 &&
        !isResolving
    }

    private func submit() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qty = Double(quantity), let cst = Double(cost), !isResolving else { return }
        isResolving = true
        errorMessage = nil

        let symbol = Symbol(input: input)
        Task {
            do {
                let quote = try await MarketDataService.shared.quote(for: symbol)
                let name = quote.companyName ?? symbol.ticker
                await MainActor.run {
                    isResolving = false
                    onAdd(symbol, name, qty, cst)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
