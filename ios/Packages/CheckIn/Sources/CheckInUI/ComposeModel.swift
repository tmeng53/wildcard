#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import Foundation
import HealthDomain
import Observation
import SportsUI

/// The compose page's state, for a new post (from 打卡) or an edit of a saved one (from its
/// 「…」): the photos with their cover, the sport and minutes for a 训练, the line, and for a new
/// post whether the squad sees it. A 训练 can come from one of today's Apple Health workouts: its
/// numbers on the 成绩条 (each can be struck out) take the minutes' place, and its map or chart
/// joins the photos as a tile. The caller saves it.
@MainActor @Observable
public final class ComposeModel {
    public enum Purpose: Equatable {
        /// A new post, shared to this squad (none when the member is in none) unless the member
        /// turns it off.
        case new(shareSquad: Squad?)
        /// An edit of this saved post; its squads stay as posted.
        case edit(CheckIn)
    }

    let kind: CheckInKind
    let purpose: Purpose
    /// The photo row in the post's order, the cover first: at most `Photos.maxCount` photos and
    /// the workout's tile, which doesn't count toward them.
    var tiles: [ComposedTile]
    var line: String
    /// The sport picked; the suggestion until the member picks one.
    var activity: Activity?
    var minutes: WorkoutMinutes?
    /// When a 训练 made by hand started, if the member picked it on the flip clock; a workout
    /// from Apple Health carries its own.
    var startTime: StartTime?
    /// The workout the 训练 is posted from, as Health has it (or, for an edit, as it was posted);
    /// nil for one made by hand.
    private(set) var workout: Workout?
    /// The workout's numbers struck out on the 成绩条, which aren't posted.
    private(set) var struck: Set<WorkoutCell> = []
    /// Where the chart was when striking its number took it off, to put it back there.
    @ObservationIgnored private var chartTakenAt: Int?
    /// Today's workouts from Health, newest first, for a new 训练's chips; empty when Health
    /// isn't connected or has none.
    let healthWorkouts: [TodaysWorkout]
    /// What a workout picked from Health starts with: the numbers and tile 设置 shares.
    @ObservationIgnored private let sharing: HealthSharing
    /// Whether a new post goes to the squad; off keeps it to the member. An edit keeps its squads
    /// as posted and never reads it.
    var isShared = true
    /// The days a new post can count for (补打卡), today last; none for an edit, whose day stays.
    let postableDays: [LocalDay]
    /// The past day a new post counts for, once the member picks one; nil is today, whatever
    /// day it is when it posts (the page may stay open past midnight).
    var day: LocalDay?
    let suggestedActivity: Activity
    let recentActivities: [Activity]
    private(set) var isSending = false
    /// Picked photos are still loading: the post waits for them, so none are left behind.
    var isPreparingPhotos = false
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
        kind: CheckInKind, purpose: Purpose, photos: [ComposedPhoto] = [], postableDays: [LocalDay] = [],
        suggestedActivity: Activity, recentActivities: [Activity], healthWorkouts: [TodaysWorkout] = [],
        sharing: HealthSharing = HealthSharing(),
        loadPhoto: @escaping @Sendable (PhotoRef) async -> Data? = { _ in nil },
        save: @escaping @MainActor (ComposeModel) async -> Bool, close: @escaping @MainActor () -> Void
    ) {
        self.kind = kind
        self.purpose = purpose
        self.postableDays = postableDays
        self.suggestedActivity = suggestedActivity
        self.recentActivities = recentActivities
        self.healthWorkouts = healthWorkouts
        self.sharing = sharing
        self.loadPhoto = loadPhoto
        self.save = save
        self.close = close
        // Locals first: an @Observable model can't read its own properties until all are set.
        var start = Snapshot(
            tiles: Array(photos.prefix(Photos.maxCount)).map(ComposedTile.photo), line: "", activity: nil,
            minutes: nil, startTime: nil)
        var posted: Workout?
        if case .edit(let checkIn) = purpose {
            start.tiles = ComposedTile.of(checkIn)
            start.line = checkIn.entry.line ?? ""
            if case .trained(let training) = checkIn.entry {
                start.activity = training.activity
                start.minutes = training.minutes
                start.startTime = training.startTime
                posted = training.workout
            }
        }
        tiles = start.tiles
        line = start.line
        activity = start.activity
        minutes = start.minutes
        startTime = start.startTime
        workout = posted
        initial = start
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

    var shareSquad: Squad? { if case .new(let squad) = purpose { squad } else { nil } }

    var currentActivity: Activity { activity ?? suggestedActivity }

    /// The photos in the row, without the workout's tile.
    var photos: [ComposedPhoto] { tiles.photos }

    var canAddPhoto: Bool { photos.count < Photos.maxCount }

    /// The 成绩条's cells: the workout's numbers, 时长 first.
    var scoreCells: [ScoreCell] { workout.map { ScoreCell.cells(of: $0.summary) } ?? [] }

    /// A 请假条 needs its words; the other kinds post with photos or words or neither.
    var canSave: Bool {
        guard !isPreparingPhotos else { return false }
        guard kind == .disclaimer else { return true }
        return (try? Disclaimer(line)) != nil
    }

    /// The most a line may hold: a caption's, or a 请假条's.
    var lineLimit: Int { kind == .disclaimer ? Disclaimer.maxLength : Caption.maxLength }

    /// What the member would lose by leaving: anything added to a new post, any change to an edit.
    var hasChanges: Bool {
        if isEditing {
            return Snapshot(tiles: tiles, line: line, activity: activity, minutes: minutes, startTime: startTime)
                != initial
                || !struck.isEmpty
        }
        return !photos.isEmpty || !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || day != nil || workout != nil
    }

    func add(_ picked: [PreparedPhoto]) {
        let room = Photos.maxCount - photos.count
        tiles += picked.prefix(max(room, 0)).map { .photo(.new($0)) }
    }

    /// Takes a tile off the row: a photo, or the workout's map or chart, which then isn't posted.
    func remove(_ tile: ComposedTile) {
        tiles.removeAll { $0 == tile }
    }

    /// Drag and drop: the tile `id` goes where `target` is; the first is the cover.
    func move(_ id: String, onto target: String) {
        tiles.move(id, onto: target)
    }

    /// Picks one of today's workouts for a new 训练: its sport, its minutes, its numbers on the
    /// 成绩条 with those 设置 doesn't share struck, and its map and chart first in the row.
    /// Picking the one already picked lets it go again; a posted one can't be picked.
    func pick(_ imported: ImportedWorkout) {
        guard !isEditing else { return }
        if workout?.source == imported.workout.source {
            letGoOfWorkout()
            return
        }
        guard !(healthWorkouts.first { $0.id == imported.id }?.isPosted ?? false) else { return }
        tiles.removeAll(where: \.isWorkout)
        workout = imported.workout
        struck = sharing.struck
        chartTakenAt = nil
        if let sport = imported.activity { activity = sport }
        minutes = imported.minutes
        startTime = nil
        let kept = sharing.keptTiles(of: imported.workout)
        tiles.insert(contentsOf: kept.map(ComposedTile.workout), at: 0)
        if !kept.contains(.chart), imported.workout.chartCell != nil {
            // 设置 struck what the chart shows; restoring that number brings the chart, after the map.
            chartTakenAt = kept.count
        }
    }

    /// Back to a 训练 made by hand: the sport, the 成绩条 and the tile go, the minutes' pills
    /// come back; the line and photos stay.
    func letGoOfWorkout() {
        tiles.removeAll(where: \.isWorkout)
        workout = nil
        struck = []
        chartTakenAt = nil
        activity = nil
        minutes = nil
        startTime = nil
    }

    /// Strikes a number out of the post, or brings it back. 时长 always goes.
    func toggle(_ cell: WorkoutCell) {
        guard cell != .duration else { return }
        if struck.contains(cell) { struck.remove(cell) } else { struck.insert(cell) }
        guard cell == workout?.chartCell else { return }
        // The chart shows the number struck, so it goes with it, and comes back where it was.
        if struck.contains(cell), let index = tiles.firstIndex(of: .workout(.chart)) {
            tiles.remove(at: index)
            chartTakenAt = index
        } else if let index = chartTakenAt {
            tiles.insert(.workout(.chart), at: min(index, tiles.count))
            chartTakenAt = nil
        }
    }

    /// The workout as it is to be posted: the numbers not struck, the tiles where the row has them.
    private var postedWorkout: Workout? {
        workout?.posting(struck: struck, positions: tiles.workoutTilePositions)
    }

    /// Starts this new post again from one the server refused: its photos with the workout's
    /// tiles, words, sport, minutes and squad as the member made it, and its day while that day
    /// can still be posted. A 请假条 has no page here.
    func restore(_ post: PendingCheckIn) {
        switch post.draft {
        case .trained(let sport, let length, let body):
            activity = sport
            minutes = length
            startTime = body.startTime
            apply(body)
        case .healthyMeal(let body), .cheatMeal(let body):
            apply(body)
        case .disclaimer:
            return
        }
        isShared = !post.audience.squads.isEmpty
        day = postableDays.contains(post.day) && post.day != postableDays.last ? post.day : nil
    }

    private func apply(_ body: PostBody) {
        tiles = ComposedTile.of(body)
        line = body.caption ?? ""
        workout = body.workout
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
        let trained = kind == .trained
        let body = PostBody(
            photos: picked, caption: line, workout: trained ? postedWorkout : nil,
            startTime: trained && workout == nil ? startTime : nil)
        return switch kind {
        case .trained: .trained(currentActivity, minutes, body)
        case .healthyMeal: .healthyMeal(body)
        case .cheatMeal, .disclaimer: .cheatMeal(body)
        }
    }

    /// The saved post as edited; nil for a new one.
    var edit: PostEdit? {
        guard case .edit(let checkIn) = purpose else { return nil }
        return PostEdit(
            original: checkIn, activity: currentActivity, minutes: minutes, line: line, photos: photos,
            workout: postedWorkout, startTime: workout == nil ? startTime : nil)
    }

    private struct Snapshot: Equatable {
        var tiles: [ComposedTile]
        var line: String
        var activity: Activity?
        var minutes: WorkoutMinutes?
        var startTime: StartTime?
    }
}

/// Saves edits of the member's own posts and deletes them. The app passes the home's store, so
/// the home counts again; previews pass the sample squad.
@MainActor
public protocol PostEditing: AnyObject {
    /// The sports a 训练's picker offers first.
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
