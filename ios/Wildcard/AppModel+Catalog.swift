import Backend
import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import Foundation
import SportsUI

extension AppModel {
    /// Hands each part of the catalog to the screens; static, since `init` calls it first.
    /// `keepsCopy` is false for the copy this build ships with, shown before the kept catalog
    /// is read, so it never stands over the lines last put that the extensions read.
    static func show(_ catalog: AppCatalog, keepsCopy: Bool = true) {
        SportList.shared.show(catalog.sports)
        SceneTheme.list(catalog.scenes)
        DiceLines.shared.show(catalog.diceLines)
        StarterStock.shared.show(catalog.starterStock)
        Switchboard.shared.show(catalog.switches)
        QuickReactions.shared.show(catalog.quickReactions)
        // The lines put show from the next launch, in the app and its extensions alike.
        if keepsCopy { SharedCopy.inAppGroup?.save(catalog.copy) }
    }

    /// Whether this build is older than the lowest `catalog` lets run. A build whose number it
    /// can't read (never one from TestFlight or the App Store) runs.
    static func mustUpdate(_ catalog: AppCatalog) -> Bool {
        let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build = number.flatMap(AppBuild.init) else { return false }
        return !build.mayRun(withMinimum: catalog.minimumBuild)
    }
}
