#if os(iOS)
import CheckInDomain
import Contracts

/// 我也发 (approved 2026-11-10): a squadmate named the member on their 训练, and the push or 通知
/// row opens the member's own 训练 started from theirs, the squadmate already picked under 一起练.
/// Nothing is posted until the member taps 发布, so a tag never counts by itself.
extension TodayModel {
    /// Opens a new 训练 started from the squadmate's `post`: its sport, start and minutes, the
    /// squadmate picked, and its day when that day can still be posted. A post the home doesn't
    /// have yet is read again first; one that doesn't name the member opens a plain 训练. Nothing
    /// opens over a page already open.
    public func trainAlong(_ post: CheckInID) async {
        if store.home?.hint(along: post) == nil { await store.refresh() }
        guard step == .scene, arrival == nil else { return }
        isBurstOpen = false
        pick(.trained)
        guard let model = compose, let hint = store.home?.hint(along: post) else { return }
        if let day = store.home?.checkIns.first(where: { $0.id == post })?.day,
            store.postableDays.contains(day), day != store.postableDays.last
        {
            model.day = day
        }
        model.take(hint)
    }
}
#endif
