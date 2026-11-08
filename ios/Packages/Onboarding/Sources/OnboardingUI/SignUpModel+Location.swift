#if os(iOS)
import LocationDomain
import OnboardingDomain

/// 打开大概位置 (Tracy, 2026-11-08), between 连上 Apple 健康 and 本周目标.
extension SignUpModel {
    /// Whether this phone can ask for its location, so 打开大概位置 shows.
    var hasLocation: Bool { location != nil }

    /// Whether 打开大概位置 is waiting on the system's prompt.
    var isAskingLocation: Bool { location?.isAsking ?? false }

    /// 允许: the system's prompt for approximate location. Allowed, the step says 已打开 and goes on
    /// with 下一步; refused, it goes straight on, as 以后再说 does.
    func allowLocation() {
        guard let location, !location.isAsking else { return }
        Task {
            await location.ask()
            if location.access != .allowed { finishLocation() }
        }
    }

    /// 下一步 or 以后再说: on to 本周目标. Skipping asks nothing; 设置 › 位置 can later.
    func finishLocation() {
        guard !isAskingLocation else { return }
        show(SignUpStep.location.next(hasHealth: hasHealth, hasLocation: true) ?? .week)
    }
}
#endif
