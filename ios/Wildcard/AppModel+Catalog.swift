import Backend
import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
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
        // The lines put show from the next launch, in the app and its extensions alike.
        if keepsCopy { SharedCopy.inAppGroup?.save(catalog.copy) }
    }
}
