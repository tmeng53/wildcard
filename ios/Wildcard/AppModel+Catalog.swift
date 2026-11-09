import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import Foundation
import SportsUI

extension AppModel {
    /// Hands each part of the catalog to the screens; static, since `init` calls it first.
    static func show(_ catalog: AppCatalog) {
        SportList.shared.show(catalog.sports)
        SceneTheme.list(catalog.scenes)
        DiceLines.shared.show(catalog.diceLines)
        StarterStock.shared.show(catalog.starterStock)
        Switchboard.shared.show(catalog.switches)
        QuickReactions.shared.show(catalog.quickReactions)
    }

    /// Whether this build is older than the lowest `catalog` lets run. A build whose number it
    /// can't read (never one from TestFlight or the App Store) runs.
    static func mustUpdate(_ catalog: AppCatalog) -> Bool {
        let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build = number.flatMap(AppBuild.init) else { return false }
        return !build.mayRun(withMinimum: catalog.minimumBuild)
    }
}
