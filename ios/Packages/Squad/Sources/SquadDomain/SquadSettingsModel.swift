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

/// 教练市场 while it reads the coaches.
public enum CoachMarketLoad: Hashable, Sendable {
    case loading
    case loaded([Coach])
    case failed(SquadError)
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

/// The line under this week's scene: who picks it, or who picked it.
public enum SceneLine: Hashable, Sendable {
    /// The member won last week's crown and may pick once.
    case youWon
    /// Last week's crown winners pick; these are their nicknames.
    case winnersPick([String])
    /// Nobody won the crown: the member is captain and may pick once.
    case youPickAsCaptain
    /// Nobody won the crown: the captain picks.
    case captainPicks
    /// Picked this week by the member: it stays until next week's winner.
    case youPicked
    /// Picked this week by the captain, with nobody holding the crown.
    case captainPicked
    /// Picked this week by a crown winner, by nickname (nil once they deleted their account).
    case winnerPicked(String?)
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
    /// 教练市场, read each time it opens.
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
    public func reload() async {
        do {
            let settings = try await service.settings()
            load = .loaded(settings)
            if !settings.scene.canPick { picker = nil }
        } catch {
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

    /// The captain's nickname, for 「5 人 · 队长 小林」.
    public var captainName: String? {
        settings.flatMap { settings in settings.squad.captain.flatMap { settings.characters[$0]?.nickname.text } }
    }

    /// How many more can join, for 「还能来 3 人」.
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

    public var sceneLine: SceneLine? {
        guard let settings else { return nil }
        let scene = settings.scene
        let isMe = scene.pickers.members.contains(settings.viewer)
        if let picked = scene.picked {
            if picked.picker == settings.viewer { return .youPicked }
            if case .captain = scene.pickers { return .captainPicked }
            return .winnerPicked(picked.picker.flatMap { settings.characters[$0]?.nickname.text })
        }
        switch scene.pickers {
        case .crown(let winners):
            return isMe ? .youWon : .winnersPick(winners.compactMap { settings.characters[$0]?.nickname.text })
        case .captain:
            return isMe ? .youPickAsCaptain : .captainPicks
        }
    }

    /// The member may pick this week's scene now (换场地 shows).
    public var canPickScene: Bool { settings?.scene.canPick ?? false }

    // MARK: 教练

    /// The squad's coach, once hired.
    public var coach: SquadCoach.Hire? { settings?.coach.hire }

    /// The member is the captain, who hires, changes and fires the coach (招聘, 换教练, 解雇);
    /// everyone else reads the 简历 only.
    public var canHireCoach: Bool { settings?.coach.canHire ?? false }

    /// 「执教第 N 周」: the week the squad hired it counts 1, weeks starting Monday on the
    /// member's clock.
    public var coachWeek: Int? {
        guard let settings, let hire = settings.coach.hire else { return nil }
        return settings.today.weekNumber(since: LocalDay(at: hire.since, in: settings.timeZone))
    }

    /// Reads 教练市场's coaches, each time it opens.
    public func loadMarket() async {
        market = .loading
        do {
            market = .loaded(try await service.coaches())
        } catch {
            market = .failed(error)
            if error == .signedOut { await signOut() }
        }
    }

    /// Hires `coach` (招聘), or swaps the squad's coach for it in one step (换教练). True once the
    /// squad has it, so the page goes back to 小队设置.
    @discardableResult
    public func hire(_ coach: CoachID) async -> Bool {
        guard let settings else { return false }
        await change { service throws(SquadError) in
            let hired = try await service.hire(coach, for: settings.squad.id)
            self.updateCoach(hired)
        }
        return !changeFailed
    }

    /// Fires the squad's coach (确认解雇). True once it is gone.
    @discardableResult
    public func fireCoach() async -> Bool {
        guard let settings else { return false }
        await change { service throws(SquadError) in
            let fired = try await service.fireCoach(of: settings.squad.id)
            self.updateCoach(fired)
        }
        return !changeFailed
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

    /// The coach changes nothing 今天 or 我 show, so nothing else reads the squad again.
    private func updateCoach(_ coach: SquadCoach) {
        guard case .loaded(var settings) = load else { return }
        settings.coach = coach
        load = .loaded(settings)
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
