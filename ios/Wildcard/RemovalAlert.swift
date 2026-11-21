import Contracts
import DesignSystemUI
import Foundation
import SwiftUI

extension View {
    /// 「你已被移出 X」, or 「X」已解散 when its captain disbanded it, with 确认, while `exit` is the
    /// squad the captain took the member out of.
    func removalAlert(_ exit: Binding<SquadExit?>) -> some View {
        alert(
            title(exit.wrappedValue),
            isPresented: Binding(
                get: { exit.wrappedValue != nil },
                set: { shown in if !shown { exit.wrappedValue = nil } })
        ) {
            Button {
                exit.wrappedValue = nil
            } label: {
                Text(copy: "确认", bundle: .main)
            }
        }
    }

    private func title(_ exit: SquadExit?) -> Text {
        let name = exit?.name ?? ""
        return exit?.how == .disbanded
            ? Text(copy: "「\(name)」已解散", bundle: .main) : Text(copy: "你已被移出 \(name)", bundle: .main)
    }
}

/// Which removal this phone has told the member of, so 「你已被移出」 or 「已解散」 shows once for each.
enum RemovalNotice {
    private static let key = "toldRemovalFromSquad"

    /// True the first time it is asked about this squad's removal on this phone.
    @MainActor static func isNew(_ squad: SquadID) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: key) != squad.description else { return false }
        defaults.set(squad.description, forKey: key)
        return true
    }

    @MainActor static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension LaunchOptions {
    /// On the sample squad, `-onboarding-rejoin`: a member the captain removed from a squad, told
    /// so, then 加入小队 as the character they made, then 今天.
    static var rejoins: Bool {
        ProcessInfo.processInfo.arguments.contains("-onboarding-rejoin")
    }
}
