import Contracts
import DesignSystem
import Foundation
import Observation
import ScenePickDomain

/// Where 小队设置 is while it reads the squad.
public enum SquadLoad: Hashable, Sendable {
    case loading
    case loaded(SquadSettings)
    case failed(SquadError)
}

/// 教练招聘会 while it reads the coaches.
public enum CoachMarketLoad: Hashable, Sendable {
    case loading
    case loaded([Coach])
    case failed(SquadError)
}

/// How a coach change (招聘, 换教练, 确认解雇) ended, for the coach's pages.
public enum CoachChange: Hashable, Sendable {
    /// The squad has the change: the pages close onto 小队设置.
    case done
    /// The squad changed under it (a retired coach, a new captain): the page has read it again,
    /// and the pages close onto it.
    case outdated
    /// It never got through: the page says so and may try again.
    case unavailable
}

/// A member on the page's list, in the order they joined.
public struct SquadMemberRow: Hashable, Sendable, Identifiable {
    public let id: MemberID
    /// Nil until they make their character.
    public let character: MemberCharacter?
    public let isMe: Bool
    public let isCaptain: Bool
    /// Won last week's crown (上周冠军).
    public let hasCrown: Bool
    /// The captain may remove them or hand them the captaincy: everyone but the captain.
    public let isManageable: Bool
}

/// 小队设置 on screen: the squad, its members and this week's scene. The captain renames the
/// squad, removes members and hands the captaincy on; everyone invites and can leave; last
/// week's crown winner, or the captain when nobody won, picks the scene once.
@MainActor @Observable
public final class SquadSettingsModel {
    public private(set) var load: SquadLoad = .loading
    /// A change is on its way; the page holds still until it lands.
    public private(set) var isSaving = false
    /// The last change didn't go through; the page says so until the next one.
    public private(set) var changeFailed = false
    /// The member left the squad: the app takes them back to sign-up's squad step.
    public private(set) var hasLeft = false
    /// The scene picker, while the member may pick and has opened it (换场地).
    public private(set) var picker: ScenePicker?
    /// 教练招聘会, read each time it opens.
    public private(set) var market: CoachMarketLoad = .loading

    @ObservationIgnored private let service: any SquadSettingsService
    @ObservationIgnored private let signOut: @MainActor () async -> Void
    @ObservationIgnored private let changed: @MainActor () -> Void

    /// `changed` is called after the squad's name or scene changes, so 今天 and 我 read it again;
    /// `signOut` signs out on this phone when the session ended.
    public init(
        service: any SquadSettingsService, changed: @escaping @MainActor () -> Void = {},
        signOut: @escaping @MainActor () async -> Void = {}
    ) {
        self.service = service
        self.changed = changed
        self.signOut = signOut
    }

    public var settings: SquadSettings? {
        if case .loaded(let settings) = load { settings } else { nil }
    }

    /// Reads the squad, again each time the page opens or a change was refused.
    /// A try after a failure shows the loader again, never the failure while it waits.
    public func reload() async {
        if case .failed = load { load = .loading }
        do {
            let settings = try await service.settings()
            load = .loaded(settings)
            if !settings.scene.canPick { picker = nil }
        } catch {
            // A read cut short (the page closed, the app went to the background) didn't fail.
            guard !Task.isCancelled else { return }
            if error == .noSquad { hasLeft = true }
            if settings == nil { load = .failed(error) }
            if error == .signedOut { await signOut() }
        }
    }

    // MARK: What the page shows

    public var isCaptain: Bool {
        guard let settings else { return false }
        return settings.squad.captain == settings.viewer
    }

    /// How many more can join, for 「还剩 3 个名额」.
    public var openSpots: Int {
        max(SquadSize.memberLimit - (settings?.squad.members.count ?? 0), 0)
    }

    public var members: [SquadMemberRow] {
        guard let settings else { return [] }
        let crown: [MemberID] =
            if case .crown(let winners) = settings.scene.pickers { winners } else { [] }
        let captain = settings.squad.captain
        return settings.squad.members.map { member in
            SquadMemberRow(
                id: member, character: settings.characters[member], isMe: member == settings.viewer,
                isCaptain: member == captain, hasCrown: crown.contains(member),
                isManageable: captain == settings.viewer && member != settings.viewer)
        }
    }

    /// This week's scene, as the app draws it.
    public var scene: SceneTheme {
        settings.flatMap { SceneTheme(rawValue: $0.scene.scene.rawValue) } ?? .gym
    }

    /// The member may pick this week's scene now (换场地 shows).
    public var canPickScene: Bool { settings?.scene.canPick ?? false }

    // MARK: 每周目标

    /// The squad's weekly goal, as last read or as the captain just set it.
    public var goal: SquadWeeklyGoal? { settings?.goal }

    /// The captain sets the goal; everyone else reads it.
    public var canChangeGoal: Bool { isCaptain && settings?.goal.canChange == true }

    /// The captain picks 人均 `daysPerMember` 天 for next week. The pill moves at once and moves
    /// back if the change doesn't go through.
    public func setGoal(_ daysPerMember: Int) async {
        guard let settings, canChangeGoal, SquadWeeklyGoal.choices.contains(daysPerMember),
            daysPerMember != settings.goal.nextDaysPerMember
        else { return }
        let before = settings.goal
        update { $0.goal.nextDaysPerMember = daysPerMember }
        await change { service throws(SquadError) in
            let goal = try await service.setWeeklyGoal(of: settings.squad.id, to: daysPerMember)
            self.update { $0.goal = goal }
        }
        if changeFailed, case .loaded(let now) = load, now.goal.nextDaysPerMember == daysPerMember {
            update { $0.goal = before }
        }
    }

    // MARK: 比赛时区

    /// The squad's time zone, as last read or as the captain just set it.
    public var matchTimeZone: SquadTimeZone? { settings?.matchTimeZone }

    /// The captain sets the zone; everyone else reads it.
    public var canChangeTimeZone: Bool { isCaptain && settings?.matchTimeZone.canChange == true }

    /// The captain picks the squad's zone, which counts at once (Tracy, 2026-11-08). The row shows
    /// it at once and goes back if the change doesn't go through.
    public func setTimeZone(_ identifier: String) async {
        guard let settings, canChangeTimeZone, TimeZone(identifier: identifier) != nil,
            identifier != settings.matchTimeZone.timeZone
        else { return }
        let before = settings.matchTimeZone
        update { $0.matchTimeZone.timeZone = identifier }
        await change { service throws(SquadError) in
            let zone = try await service.setTimeZone(of: settings.squad.id, to: identifier)
            self.update { $0.matchTimeZone = zone }
        }
        if changeFailed, case .loaded(let now) = load, now.matchTimeZone.timeZone == identifier {
            update { $0.matchTimeZone = before }
        }
    }

    // MARK: 小队语言

    /// The squad's language, as last read or as the captain just set it.
    public var language: SquadLanguage? { settings?.language }

    /// The captain sets the language; everyone else reads it.
    public var canChangeLanguage: Bool { isCaptain && settings?.language.canChange == true }

    /// The captain picks the squad's language, which counts at once. The row says so at once and
    /// goes back if the change doesn't go through. Picking the language shown is saved too: until
    /// the captain picks, the squad only follows the captain's app language, which can change.
    public func setLanguage(_ language: SquadLanguage.Language) async {
        guard let settings, canChangeLanguage else { return }
        let before = settings.language
        update { $0.language.language = language }
        await change { service throws(SquadError) in
            let saved = try await service.setLanguage(of: settings.squad.id, to: language)
            self.update { $0.language = saved }
        }
        if changeFailed, case .loaded(let now) = load, now.language.language == language {
            update { $0.language = before }
        }
    }

    // MARK: 教练

    /// The squad's coach, once hired.
    public var coach: SquadCoach.Hire? { settings?.coach.hire }

    /// The member is the captain, who hires, changes and fires the coach (招聘, 换教练, 解雇);
    /// everyone else reads the 简历 only.
    /// Only the captain hires; a captain who just handed the captaincy on no longer can, before
    /// the squad is read again.
    public var canHireCoach: Bool { isCaptain && settings?.coach.canHire == true }

    /// 「执教第 N 周」: the week the squad hired it counts 1, weeks starting Monday on the
    /// member's clock.
    public var coachWeek: Int? {
        guard let settings, let hire = settings.coach.hire else { return nil }
        return settings.today.weekNumber(since: LocalDay(at: hire.since, in: settings.timeZone))
    }

    /// Reads 教练招聘会's coaches, each time it opens, and again on coming back from a 简历. A list
    /// already shown stays up while it is read again (and when that read fails), so the page keeps
    /// its place instead of falling back to the spinner and the top.
    public func loadMarket() async {
        if case .loaded = market {} else { market = .loading }
        do {
            market = .loaded(try await service.coaches())
        } catch {
            // Closed before the coaches came, it didn't fail.
            guard !Task.isCancelled else { return }
            if case .loaded = market, error != .signedOut { return }
            market = .failed(error)
            if error == .signedOut { await signOut() }
        }
    }

    /// Hires `coach` (招聘), or swaps the squad's coach for it in one step (换教练).
    public func hire(_ coach: CoachID) async -> CoachChange {
        guard let settings else { return .outdated }
        return await changeCoach { service throws(SquadError) in
            try await service.hire(coach, for: settings.squad.id)
        }
    }

    /// Fires the squad's coach (确认解雇).
    public func fireCoach() async -> CoachChange {
        guard let settings else { return .outdated }
        return await changeCoach { service throws(SquadError) in
            try await service.fireCoach(of: settings.squad.id)
        }
    }

    // MARK: Changes

    /// Renames the squad. A name the rules refuse is the field's to say; this returns false for it.
    @discardableResult
    public func rename(to typed: String) async -> Bool {
        guard let settings, let name = try? SquadName(typed) else { return false }
        guard name.text != settings.squad.name else { return true }
        await change { service throws(SquadError) in
            let squad = try await service.rename(settings.squad.id, to: name)
            self.update { $0.squad = squad }
        }
        return !changeFailed
    }

    public func handCaptaincy(to member: MemberID) async {
        guard let settings else { return }
        await change { service throws(SquadError) in
            let squad = try await service.handCaptaincy(of: settings.squad.id, to: member)
            self.update { $0.squad = squad }
        }
    }

    public func remove(_ member: MemberID) async {
        guard let settings else { return }
        await change { service throws(SquadError) in
            try await service.remove(member, from: settings.squad.id)
            await self.reload()
            self.changed()
        }
    }

    /// Leaves the squad. The app then goes back to sign-up's squad step.
    public func leave() async {
        guard let settings else { return }
        await change { service throws(SquadError) in
            try await service.remove(settings.viewer, from: settings.squad.id)
            self.hasLeft = true
        }
    }

    /// Opens the scene picker (换场地), with the scenes as tiles.
    public func openPicker() {
        guard let settings, settings.scene.canPick else { return }
        picker = ScenePicker(
            options: SceneOption.options(from: settings.scene.history),
            service: SettingsScenePick(service: service, squad: settings.squad.id, week: settings.scene.week))
    }

    /// The pick landed (确认): the page shows the new scene, locked until next week.
    public func picked() async {
        picker = nil
        await reload()
        changed()
    }

    /// The pick was refused: someone else picked this week first, or the week moved on. The
    /// page closes the picker and reads the squad's scene again, and so does the app.
    public func pickRefused() async {
        picker = nil
        await reload()
        changed()
    }

    /// A coach change, which the coach's pages answer themselves: the squad-wide `changeFailed`
    /// stays as it was. The coach changes nothing 今天 or 我 show, so nothing else reads the
    /// squad again.
    private func changeCoach(
        _ body: (any SquadSettingsService) async throws(SquadError) -> SquadCoach
    ) async -> CoachChange {
        guard !isSaving else { return .unavailable }
        isSaving = true
        defer { isSaving = false }
        do {
            let coach = try await body(service)
            if case .loaded(var settings) = load {
                settings.coach = coach
                load = .loaded(settings)
            }
            return .done
        } catch {
            switch error {
            case .signedOut: await signOut()
            case .noSquad: hasLeft = true
            case .outdated: await reload()
            case .unavailable: return .unavailable
            }
            return .outdated
        }
    }

    private func update(_ edit: (inout SquadSettings) -> Void) {
        guard case .loaded(var settings) = load else { return }
        edit(&settings)
        load = .loaded(settings)
        changed()
    }

    private func change(_ body: (any SquadSettingsService) async throws(SquadError) -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        changeFailed = false
        defer { isSaving = false }
        do {
            try await body(service)
        } catch {
            changeFailed = true
            switch error {
            case .signedOut: await signOut()
            case .noSquad: hasLeft = true
            case .outdated: await reload()
            case .unavailable: break
            }
        }
    }
}

/// The picker's port, saving through 小队设置's service for the week the page read.
struct SettingsScenePick: ScenePickService {
    let service: any SquadSettingsService
    let squad: SquadID
    let week: LocalDay

    func pick(_ scene: SceneTheme) async throws(ScenePickError) {
        guard let id = SceneID(rawValue: scene.rawValue) else { throw .notAllowed }
        do {
            _ = try await service.pick(id, for: squad, week: week)
        } catch .unavailable {
            throw .unavailable
        } catch {
            throw .notAllowed
        }
    }
}
