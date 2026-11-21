import CheckInUI
import DesignSystem
import DesignSystemUI
import SwiftUI

// 打卡's ＋: the round button at the tab bar's end on every tab (Tracy, 2026-11-21), and the
// check-in kinds it opens into over the tab on screen.

extension MainTabs {
    /// The ＋, a cross while the kinds are open; a tap opens or closes them.
    static func checkInButton(isOpen: Bool, toggle: @escaping () -> Void) -> TabBarAction {
        TabBarAction(
            title: Text(copy: "打卡", bundle: .main), systemImage: isOpen ? "xmark" : "plus",
            accessibilityIdentifier: "today.checkin", perform: toggle)
    }

    var checkInAction: TabBarAction {
        Self.checkInButton(isOpen: today.isCheckInMenuOpen) { [today] in today.isCheckInMenuOpen.toggle() }
    }

    /// The ＋ as home has it, for 上场, whose end hands over to home: nothing opens until it has.
    static var entranceCheckInAction: TabBarAction { checkInButton(isOpen: false) {} }
}

/// The tab's screen, blurred under the kinds while they are open, as the scene is (`Scrim`). A
/// pick goes back to 小队's scene, where every check-in is written and lands.
struct CheckInMenuCover: ViewModifier {
    let today: TodayModel
    @Binding var selection: MainTabs.Tab
    @Binding var todayPages: [TodayPage]

    func body(content: Content) -> some View {
        let isOpen = today.isCheckInMenuOpen
        content
            .blur(radius: isOpen ? Scrim.blurRadius : 0)
            .overlay {
                Color(Scrim.tint).opacity(isOpen ? Scrim.tintOpacity : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: isOpen ? Scrim.fadeIn : Scrim.fadeOut), value: isOpen)
            .overlay {
                CheckInMenu(
                    isOpen: Binding(get: { today.isCheckInMenuOpen }, set: { today.isCheckInMenuOpen = $0 }),
                    unavailable: today.unavailable, identifierPrefix: "today"
                ) { kind in
                    selection = .today
                    todayPages = []
                    today.startCheckIn(kind)
                }
            }
    }
}
