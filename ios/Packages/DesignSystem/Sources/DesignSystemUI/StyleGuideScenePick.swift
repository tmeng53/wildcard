#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The scene pick's pieces: the tiles, two of them scenes the squad knows and the rest cartons
/// (the gym picked, so it shakes), and the carton the reveal opens.
struct ScenePickGuide: View {
    @State private var scene: SceneTheme = .gym

    var body: some View {
        GuideGroup(Text("下周场地：去过的是色卡，没开过的是纸箱", bundle: .module)) {
            HStack(alignment: .top, spacing: Space.xxs) {
                ForEach(SceneTheme.allCases, id: \.self) { option in
                    SceneTile(
                        scene: option, name: option.name, isOpened: option == .pool || option == .track,
                        isSelected: scene == option
                    ) {
                        scene = option
                    }
                    .accessibilityIdentifier("styleguide.scenetile.\(option.rawValue)")
                }
            }
            CartonBox()
                .frame(maxWidth: .infinity)
        }
    }
}
#endif
