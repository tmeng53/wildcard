import Contracts
import DesignSystemUI
import Foundation
import SwiftUI

extension View {
    /// 「你已被移出 X」 with 确认, while `squad` names the squad whose captain removed the member.
    func removalAlert(_ squad: Binding<String?>) -> some View {
        alert(
            Text(copy: "你已被移出 \(squad.wrappedValue ?? "")", bundle: .main),
            isPresented: Binding(
                get: { squad.wrappedValue != nil },
                set: { shown in if !shown { squad.wrappedValue = nil } })
        ) {
            Button {
                squad.wrappedValue = nil
            } label: {
                Text(copy: "确认", bundle: .main)
            }
        }
    }
}

/// Which removal this phone has told the member of, so 「你已被移出」 shows once for each.
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
