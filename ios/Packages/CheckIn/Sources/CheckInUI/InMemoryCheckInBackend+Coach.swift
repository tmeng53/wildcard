import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

// The sample squad's coach: 毛头, or 帕帕 after 换教练 with the letter 毛头 left.
extension InMemoryCheckInBackend {
    /// 毛头, hired, or 帕帕 with 毛头's letter waiting, or none.
    static func sideline(_ hired: Bool, _ letter: Bool, _ now: Date, _ squad: SquadID) -> SidelineCoach? {
        if letter { return SidelineCoach(coach: papa, note: nil, letter: sampleLetter(in: squad, now: now)) }
        return hired ? sampleCoach(now: now) : nil
    }

    /// 毛头 with today's line, as the approved home shows it.
    static func sampleCoach(now: Date) -> SidelineCoach {
        let words = Bundle.module.inAppLanguage
        let coach = CoachSpeaker(id: "xiaohun", name: words.localizedString(forKey: "毛头", value: nil, table: nil))
        let line = words.localizedString(forKey: "昨天三个人上场，我光在场边记笔记就累了。今天随缘，来了就算。", value: nil, table: nil)
        let note = CoachNote(
            day: LocalDay(at: now, in: CoachNote.timeZone), text: line, coach: coach,
            writtenAt: now.addingTimeInterval(-3600))
        return SidelineCoach(coach: coach, note: note)
    }

    /// 帕帕, the coach a squad changes to in the samples.
    static var papa: CoachSpeaker {
        CoachSpeaker(
            id: "papa", name: Bundle.module.inAppLanguage.localizedString(forKey: "帕帕", value: nil, table: nil))
    }

    /// 毛头's letter to 帕帕, as the approved 教练交接信 shows it.
    static func sampleLetter(in squad: SquadID, now: Date) -> CoachLetter {
        let words = Bundle.module.inAppLanguage
        return CoachLetter(
            id: 1, squad: squad,
            from: CoachSpeaker(id: "xiaohun", name: words.localizedString(forKey: "毛头", value: nil, table: nil)),
            to: papa, day: LocalDay(at: now, in: CoachNote.timeZone),
            text: words.localizedString(
                forKey:
                    "这队交给你了，我先撤。\n小美周三雷打不动去游泳，周五一定请假，别问，问就是加班。\n阿杰在备战半马，跑完要人夸，夸具体点，他听得出来是不是敷衍。\n大鹏不爱说话，练完只发图，回个表情就够了。\n这队周日晚上最热闹，战报一出全在线。\n器材室那条毯子留给你，午觉在那儿睡最舒服。",
                value: nil, table: nil))
    }
}
