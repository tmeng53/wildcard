import Backend
import MeDomain
import RecapDomain
import RecapUI
import ScenePickDomain

extension AppModel {
    /// 佩戴头衔 on a 战报 saves through 我, so the card there wears it at once.
    static func titleWearing(_ profile: MeModel) -> TitleWearing {
        TitleWearing(worn: profile.overview?.board.worn) { title in await profile.equip(.title(title)) != nil }
    }

    /// 冠军专属 on a 战报's last page: when the reader picks the scene for the week after the
    /// story's and nobody has yet. Offline, there is no sticker.
    static func scenePicker(api: WildcardAPI, after story: WeekStory) async -> ScenePicker? {
        guard let scene = try? await api.scene(of: story.squad), scene.canPick, scene.picked == nil,
            scene.week == story.week.monday.adding(days: 7)
        else { return nil }
        return ScenePicker(
            options: SceneOption.options(from: scene.history),
            service: APIScenePickService(api: api, squad: story.squad, week: scene.week))
    }
}
