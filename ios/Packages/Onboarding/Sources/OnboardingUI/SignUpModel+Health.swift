#if os(iOS)
import HealthUI
import OnboardingDomain

/// 连上 Apple 健康 (Tracy, 2026-11-06), between 平时练什么？ and 打开大概位置.
extension SignUpModel {
    /// Whether this phone has Apple Health, so 连上 Apple 健康 shows.
    var hasHealth: Bool { health?.isAvailable ?? false }

    /// 连接: HealthKit's own sheet, where the member picks what the app reads. Whatever they pick,
    /// the step then says 已连接: Health never tells an app what was refused.
    func connectHealth() {
        guard let health, !isConnectingHealth else { return }
        isConnectingHealth = true
        Task {
            await health.connect()
            isConnectingHealth = false
        }
    }

    /// 下一步 or 以后再说: on to 打开大概位置. Skipping connects nothing; 设置 › Apple 健康 can later.
    func finishHealth() {
        guard !isConnectingHealth else { return }
        show(SignUpStep.health.next(hasHealth: true, hasLocation: hasLocation) ?? .week)
    }
}
#endif
