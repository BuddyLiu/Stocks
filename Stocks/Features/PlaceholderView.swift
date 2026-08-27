import SwiftUI

/// 未完成功能占位视图
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(item.title)
                .font(.title2.weight(.semibold))
            Text("该功能将在后续版本提供")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
