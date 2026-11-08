#if os(iOS)
import OnboardingDomain

/// 平时练什么？
extension SignUpModel {
    /// 下一步: on to the next step this phone can do (连上 Apple 健康, 打开大概位置 or 本周目标).
    func finishSports() {
        show(SignUpStep.sports.next(hasHealth: hasHealth, hasLocation: hasLocation) ?? .week)
    }
}
#endif
