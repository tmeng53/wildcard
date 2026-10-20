#if canImport(SwiftUI)
import AvatarArt
import SwiftUI

extension Persona {
    /// The persona's name, as the character editor's 性格 tab shows it.
    public var name: Text {
        switch self {
        case .deadpan: Text("淡人", bundle: .module)
        case .energetic: Text("高能量", bundle: .module)
        case .showoff: Text("显眼包", bundle: .module)
        case .drama: Text("戏精", bundle: .module)
        case .shy: Text("社恐", bundle: .module)
        }
    }

    /// What a character of this persona shouts when its member hasn't set a 口头禅.
    public var defaultCatchphrase: Text {
        switch self {
        case .deadpan: Text("可以", bundle: .module)
        case .energetic: Text("冲冲冲！", bundle: .module)
        case .showoff: Text("名场面", bundle: .module)
        case .drama: Text("泪目了", bundle: .module)
        case .shy: Text("（小声）加油", bundle: .module)
        }
    }
}
#endif
