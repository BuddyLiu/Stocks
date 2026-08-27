import Foundation
import Combine
import SwiftUI

/// 应用偏好（UserDefaults 持久化）；API Key 见 KeychainStore。
final class AppSettings: ObservableObject {
    static let defaultModel = "claude-opus-5"

    @Published var changeColorStyle: ChangeColorStyle {
        didSet { UserDefaults.standard.set(changeColorStyle.rawValue, forKey: Keys.colorStyle) }
    }

    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: Keys.claudeModel) }
    }

    private enum Keys {
        static let colorStyle = "changeColorStyle"
        static let claudeModel = "claudeModel"
    }

    init() {
        let ud = UserDefaults.standard
        self.changeColorStyle = ChangeColorStyle(rawValue: ud.string(forKey: Keys.colorStyle) ?? "") ?? .auto
        self.claudeModel = ud.string(forKey: Keys.claudeModel) ?? Self.defaultModel
    }
}
