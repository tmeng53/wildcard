import DesignSystem
import DesignSystemUI
import RecapDomain
import RecapUI
import SwiftUI

/// `-recap`: the 战报's entry tile on a plain page, opening the sample week's story, which UI
/// tests walk and screenshot. `-recap-pending` and `-recap-missed` pick the other states,
/// `-recap-picker` puts 冠军专属's sticker on the last page, and `-recap-reveal` opens the story
/// with the reveal held on one moment. Once the story is watched to the end, the tile shows it
/// uncovered, as 动态 does.
struct RecapDemo: View {
    @State private var model: RecapModel?
    @State private var seen = false

    init() {
        // A held reveal never ends, so there is nothing to close.
        if let held = LaunchOptions.recapReveal {
            _model = State(initialValue: Self.story(heldReveal: held, close: {}, finished: {}))
        }
    }

    var body: some View {
        let story = RecapSample.story(pending: LaunchOptions.recapPending, missed: LaunchOptions.recapMissed)
        let cast = RecapSample.cast
        VStack {
            RecapEntryTile(story: story, viewer: cast.reader, seen: seen) {
                model = Self.story(close: { model = nil }, finished: { seen = true })
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
        heldReveal: (scene: SceneTheme, at: Double)? = nil, close: @escaping @MainActor () -> Void,
        finished: @escaping @MainActor () -> Void
    ) -> RecapModel {
        let story = RecapSample.story(pending: LaunchOptions.recapPending, missed: LaunchOptions.recapMissed)
        let picks = LaunchOptions.recapPicker || heldReveal != nil
        return RecapModel(
            story: story, cast: RecapSample.cast, service: nil,
            scenePicker: picks ? RecapSample.scenePicker() : nil, heldReveal: heldReveal,
            close: close, finished: finished, planNextWeek: close, scenePicked: { _, _ in close() })
    }
}
