#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Names, symbols and color roles for scenes and check-in types, shared by the style guide
/// and the feature screens.
extension SceneTheme {
    /// The scene's name, as the week label shows it (「第 42 周 · 跑道」).
    public var name: Text {
        switch self {
        case .pool: Text("游泳池", bundle: .module)
        case .track: Text("跑道", bundle: .module)
        case .gym: Text("健身房", bundle: .module)
        case .tennis: Text("网球场", bundle: .module)
        case .climbing: Text("攀岩馆", bundle: .module)
        }
    }
}

extension Meaning {
    /// The short label on a check-in capsule.
    public var capsuleLabel: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .fresh: Text("健康餐", bundle: .module)
        case .indulgence: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("请假", bundle: .module)
        }
    }

    /// The full name, for tags.
    public var fullName: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .fresh: Text("健康餐", bundle: .module)
        case .indulgence: Text("坦白放纵餐", bundle: .module)
        case .disclaimer: Text("今日请假条", bundle: .module)
        }
    }

    public var symbol: String {
        switch self {
        case .trained: "dumbbell.fill"
        case .fresh: "leaf.fill"
        case .indulgence: "birthday.cake.fill"
        case .disclaimer: "moon.stars.fill"
        }
    }

    public var tint: ColorRole {
        switch self {
        case .trained: .meaningTrained
        case .fresh: .meaningFresh
        case .indulgence: .meaningIndulgence
        case .disclaimer: .meaningDisclaimer
        }
    }

    public var ink: ColorRole {
        switch self {
        case .trained: .meaningTrainedInk
        case .fresh: .meaningFreshInk
        case .indulgence: .meaningIndulgenceInk
        case .disclaimer: .meaningDisclaimerInk
        }
    }

    public var wash: ColorRole {
        switch self {
        case .trained: .meaningTrainedWash
        case .fresh: .meaningFreshWash
        case .indulgence: .meaningIndulgenceWash
        case .disclaimer: .meaningDisclaimerWash
        }
    }

    public var text: ColorRole {
        switch self {
        case .trained: .meaningTrainedText
        case .fresh: .meaningFreshText
        case .indulgence: .meaningIndulgenceText
        case .disclaimer: .meaningDisclaimerText
        }
    }
}
#endif
