import DesignSystem
import DesignSystemUI
import RecapDomain
import RecapUI
import SwiftUI

/// `-recap`: the 战报's entry tile on a plain page, opening the sample week's story, which UI
/// tests walk and screenshot. `-recap-pending` and `-recap-missed` pick the other states,
/// `-recap-picker` puts 冠军专属's sticker on the last page, and `-recap-reveal` opens the story
/// with the reveal held on one moment.
struct RecapDemo: View {
    @State private var model: RecapModel?

    init() {
        // A held reveal never ends, so there is nothing to close.
        if let held = LaunchOptions.recapReveal {
            _model = State(initialValue: Self.story(heldReveal: held, close: {}))
        }
    }

    var body: some View {
        let story = RecapSample.story(pending: LaunchOptions.recapPending, missed: LaunchOptions.recapMissed)
        let cast = RecapSample.cast
        VStack {
            RecapEntryTile(week: story.week, pages: story.pages.count, viewer: cast[cast.viewer]) {
                model = Self.story { model = nil }
            }
            .padding(.horizontal, Space.pageMargin)
            Spacer()
        }
        .padding(.top, Space.xxl)
        .background(Color(role: .bgCanvas, in: cast.scene))
        .environment(\.sceneTheme, cast.scene)
        .fullScreenCover(isPresented: Binding(get: { model != nil }, set: { if !$0 { model = nil } })) {
            if let model { RecapView(model: model, autoAdvances: !LaunchOptions.recapManual) }
        }
    }

    /// The sample story; a picked scene's reveal closes it, as home would take over.
    private static func story(
        heldReveal: (scene: SceneTheme, at: Double)? = nil, close: @escaping @MainActor () -> Void
    ) -> RecapModel {
        let story = RecapSample.story(pending: LaunchOptions.recapPending, missed: LaunchOptions.recapMissed)
        let picks = LaunchOptions.recapPicker || heldReveal != nil
        return RecapModel(
            story: story, cast: RecapSample.cast, service: nil,
            scenePicker: picks ? RecapSample.scenePicker() : nil, heldReveal: heldReveal,
            close: close, planNextWeek: close, scenePicked: { _ in close() })
    }
}
