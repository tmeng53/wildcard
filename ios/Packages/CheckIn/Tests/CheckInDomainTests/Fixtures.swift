import Foundation
import Contracts

let tracy = MemberID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
let coco = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
let runners = SquadID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
let lifters = SquadID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
let swimmers = SquadID(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)

func day(_ text: String) -> LocalDay { try! LocalDay(text) }

/// A check-in on `on` with a fresh id. `kind` is trained, healthy, cheat or disclaimer.
func checkIn(
    _ kind: String, on dayText: String, by member: MemberID = tracy, to squads: [SquadID] = [runners]
) -> CheckIn {
    let id = CheckInID(UUID())
    let entry: CheckIn.Entry = switch kind {
    case "trained": .trained(try! Training(sport: .run, minutes: 30))
    case "healthy": .healthyMeal(Meal(slot: .lunch))
    case "cheat": .cheatMeal(Meal(slot: .dinner))
    default: .disclaimer(try! Disclaimer("加班到十点"))
    }
    return CheckIn(
        id: id, member: member, day: day(dayText), createdAt: Timestamp(millisecondsSince1970: 0),
        audience: try! Audience(squads), entry: entry
    )
}
