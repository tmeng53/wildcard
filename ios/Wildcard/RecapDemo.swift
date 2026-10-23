import DesignSystem
import DesignSystemUI
import RecapDomain
import RecapUI
import SwiftUI

/// `-recap`: the 战报's entry tile on a plain page, as 动态 will show it, opening the sample
/// week's story. Until the feed and the API's story route are wired, this is how the story is
/// reached and screenshotted. `-recap-pending` and `-recap-missed` pick the other states.
struct RecapDemo: View {
    @State private var model: RecapModel?

    var body: some View {
        let story = RecapSample.story(pending: LaunchOptions.recapPending, missed: LaunchOptions.recapMissed)
        let cast = RecapSample.cast
        VStack {
            RecapEntryTile(week: story.week, pages: story.pages.count, viewer: cast[cast.viewer]) {
                model = RecapModel(
                    story: story, cast: cast, service: nil, close: { model = nil }, planNextWeek: { model = nil })
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
}
