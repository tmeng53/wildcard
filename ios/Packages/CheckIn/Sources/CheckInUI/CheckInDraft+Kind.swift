#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem

extension CheckInDraft {
    var kind: CheckInKind {
        switch self {
        case .trained: .trained
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .disclaimer: .disclaimer
        }
    }

    /// The line the member wrote: a caption, or a 请假条's words.
    var line: String? {
        switch self {
        case .trained(_, _, let body), .healthyMeal(let body), .cheatMeal(let body): body.caption
        case .disclaimer(let disclaimer): disclaimer.text
        }
    }
}
#endif
