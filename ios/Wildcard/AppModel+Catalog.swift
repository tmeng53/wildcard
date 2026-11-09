import Backend
import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import SportsUI

extension AppModel {
    /// Hands each part of the catalog to the screens; static, since `init` calls it first.
    static func show(_ catalog: AppCatalog) {
        SportList.shared.show(catalog.sports)
        SceneTheme.list(catalog.scenes)
        DiceLines.shared.show(catalog.diceLines)
        StarterStock.shared.show(catalog.starterStock)
        Switchboard.shared.show(catalog.switches)
        // The lines put show from the next launch, in the app and its extensions alike.
        SharedCopy.inAppGroup?.save(catalog.copy)
    }
}
