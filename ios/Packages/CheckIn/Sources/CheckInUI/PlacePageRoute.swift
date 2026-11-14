#if os(iOS)
import Contracts
import SwiftUI

/// 地点页 for the place on the compose page's pill, pushed on the stack the compose page is on
/// (Tracy, 2026-11-12: a push, never a sheet). The app passes it in, since the place's page lives
/// in a package above this one.
public struct PlacePageRoute: Sendable {
    let page: (@MainActor @Sendable (Place) -> AnyView)?

    public init(page: @escaping @MainActor @Sendable (Place) -> AnyView) {
        self.page = page
    }

    private init() {
        page = nil
    }

    /// No place's page (the sign-up preview, the style guide): the pill's name does nothing.
    public static let unwired = PlacePageRoute()

    /// Whether a place's page is there to open.
    public var isWired: Bool { page != nil }

    /// The place's page, for a stack in another package to push (the 战报's places); nil unwired.
    @MainActor public func view(of place: Place) -> AnyView? { page?(place) }
}

extension EnvironmentValues {
    @Entry public var placePage = PlacePageRoute.unwired
}
#endif
