#if os(iOS)
import CheckInDomain
import Contracts
import Foundation
import Observation

/// The compose page's state, for a new post (from 打卡) or an edit of a saved one (from its
/// 「…」): the photos with their cover, the sport and minutes for a 练了, the line, and for a new
/// post the squads it goes to. The caller saves it.
@MainActor @Observable
public final class ComposeModel {
    public enum Purpose: Equatable {
        /// A new post, shared to these squads unless the member unticks one.
        case new(shareSquads: [Squad])
        /// An edit of this saved post; its squads stay as posted.
        case edit(CheckIn)
    }

    let kind: CheckInKind
    let purpose: Purpose
    /// At most `Photos.maxCount`, the cover first.
    var photos: [ComposedPhoto]
    var line: String
    /// The sport picked; the suggestion until the member picks one.
    var activity: Activity?
    var minutes: WorkoutMinutes?
    /// The squads a new post goes to.
    var shared: Set<SquadID>
    let suggestedActivity: Activity
    let recentActivities: [Activity]
    private(set) var isSending = false
    /// The last save didn't go through; the page says so and can try again.
    private(set) var sendFailed = false

    @ObservationIgnored private let initial: Snapshot
    @ObservationIgnored let loadPhoto: @Sendable (PhotoRef) async -> Data?
    @ObservationIgnored private let save: @MainActor (ComposeModel) async -> Bool
    @ObservationIgnored let close: @MainActor () -> Void

    /// - Parameters:
    ///   - photos: the photos it starts with, the cover first.
    ///   - loadPhoto: a saved photo's JPEG, for an edit.
    ///   - save: posts or saves it; false when it didn't go through.
    ///   - close: leaves the page without saving.
    init(
        kind: CheckInKind, purpose: Purpose, photos: [ComposedPhoto] = [], suggestedActivity: Activity,
        recentActivities: [Activity], loadPhoto: @escaping @Sendable (PhotoRef) async -> Data? = { _ in nil },
        save: @escaping @MainActor (ComposeModel) async -> Bool, close: @escaping @MainActor () -> Void
    ) {
        self.kind = kind
        self.purpose = purpose
        self.suggestedActivity = suggestedActivity
        self.recentActivities = recentActivities
        self.loadPhoto = loadPhoto
        self.save = save
        self.close = close
        switch purpose {
        case .new(let squads):
            self.photos = Array(photos.prefix(Photos.maxCount))
            line = ""
            shared = Set(squads.map(\.id))
        case .edit(let checkIn):
            self.photos = ComposedPhoto.of(checkIn)
            line = checkIn.entry.line ?? ""
            shared = Set(checkIn.audience.squads)
            if case .trained(let training) = checkIn.entry {
                activity = training.activity
                minutes = training.minutes
            }
        }
        initial = Snapshot(photos: self.photos, line: line, activity: activity, minutes: minutes)
    }

    /// An edit of one of the member's own posts, saved through `editor`.
    public convenience init(
        editing checkIn: CheckIn, editor: any PostEditing, loadPhoto: @escaping @Sendable (PhotoRef) async -> Data?,
        saved: @escaping @MainActor (CheckIn) -> Void, close: @escaping @MainActor () -> Void
    ) {
        let activity: Activity =
            if case .trained(let training) = checkIn.entry { training.activity } else { .sport("run") }
        self.init(
            kind: checkIn.entry.kind, purpose: .edit(checkIn), suggestedActivity: activity,
            recentActivities: editor.recentActivities, loadPhoto: loadPhoto,
            save: { model in
                guard let edit = model.edit else { return false }
                do throws(CheckInError) {
                    saved(try await editor.save(edit))
                    return true
                } catch {
                    return false
                }
            },
            close: close)
    }

    var isEditing: Bool { if case .edit = purpose { true } else { false } }

    var shareSquads: [Squad] { if case .new(let squads) = purpose { squads } else { [] } }

    var currentActivity: Activity { activity ?? suggestedActivity }

    var canAddPhoto: Bool { photos.count < Photos.maxCount }

    /// A 请假条 needs its words; the other kinds post with photos or words or neither.
    var canSave: Bool {
        guard kind == .disclaimer else { return true }
        return (try? Disclaimer(line)) != nil
    }

    /// The most a line may hold: a caption's, or a 请假条's.
    var lineLimit: Int { kind == .disclaimer ? Disclaimer.maxLength : Caption.maxLength }

    /// What the member would lose by leaving: anything added to a new post, any change to an edit.
    var hasChanges: Bool {
        if isEditing {
            return Snapshot(photos: photos, line: line, activity: activity, minutes: minutes) != initial
        }
        return !photos.isEmpty || !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func add(_ picked: [PreparedPhoto]) {
        photos = Array((photos + picked.map(ComposedPhoto.new)).prefix(Photos.maxCount))
    }

    func remove(_ photo: ComposedPhoto) {
        photos.removeAll { $0 == photo }
    }

    /// Moves `photo` to the front, as the cover.
    func makeCover(_ photo: ComposedPhoto) {
        guard let index = photos.firstIndex(of: photo) else { return }
        photos.insert(photos.remove(at: index), at: 0)
    }

    /// Fits what is typed: no line breaks, at most `lineLimit` characters.
    func fit(_ typed: String) -> String {
        String(typed.filter { !$0.isNewline }.prefix(lineLimit))
    }

    func send() async {
        guard !isSending, canSave else { return }
        isSending = true
        sendFailed = false
        let saved = await save(self)
        isSending = false
        sendFailed = !saved
    }

    /// A new post as drafted, its photos all just picked.
    var draft: CheckInDraft {
        let picked = photos.compactMap { if case .new(let photo) = $0 { photo } else { nil } }
        let body = PostBody(photos: picked, caption: line)
        return switch kind {
        case .trained: .trained(currentActivity, minutes, body)
        case .healthyMeal: .healthyMeal(body)
        case .cheatMeal, .disclaimer: .cheatMeal(body)
        }
    }

    /// The saved post as edited; nil for a new one.
    var edit: PostEdit? {
        guard case .edit(let checkIn) = purpose else { return nil }
        return PostEdit(original: checkIn, activity: currentActivity, minutes: minutes, line: line, photos: photos)
    }

    private struct Snapshot: Equatable {
        let photos: [ComposedPhoto]
        let line: String
        let activity: Activity?
        let minutes: WorkoutMinutes?
    }
}

/// Saves edits of the member's own posts and deletes them. The app passes the home's store, so
/// the home counts again; previews pass the sample squad.
@MainActor
public protocol PostEditing: AnyObject {
    /// The sports a 练了's picker offers first.
    var recentActivities: [Activity] { get }
    func save(_ edit: PostEdit) async throws(CheckInError) -> CheckIn
    func delete(_ checkIn: CheckInID) async throws(CheckInError)
}

extension TodayStore: PostEditing {
    public func save(_ edit: PostEdit) async throws(CheckInError) -> CheckIn {
        try await self.edit(edit)
    }
}

extension CheckIn.Entry {
    var kind: CheckInKind {
        switch self {
        case .trained: .trained
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .disclaimer: .disclaimer
        }
    }
}
#endif
