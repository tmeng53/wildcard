import Contracts
import Testing

struct SquadRulesTests {
    @Test func squadNameIsTrimmed() throws {
        #expect(try SquadName("  周三不练腿俱乐部 ").text == "周三不练腿俱乐部")
    }

    @Test func squadNameTakesTwentyCharactersAndNoMore() throws {
        #expect(try SquadName(String(repeating: "练", count: 20)).text.count == 20)
        #expect(throws: ContractsError.squadNameLength(21)) { try SquadName(String(repeating: "练", count: 21)) }
        #expect(throws: ContractsError.squadNameLength(0)) { try SquadName("   ") }
    }

    @Test func squadNameIsOneVisibleLine() {
        #expect(throws: ContractsError.multilineSquadName) { try SquadName("周三\n不练腿") }
        #expect(throws: ContractsError.invisibleSquadName) { try SquadName("小\u{202E}队") }
    }

    @Test func inviteCodeIsReadAsTheAPIReadsIt() throws {
        #expect(try InviteCode("k7m2-qx9p").text == "K7M2QX9P")
        #expect(try InviteCode(" K7M2 QX9P ").text == "K7M2QX9P")
        #expect(InviteCode.normalized("k7 m2-") == "K7M2")
    }

    @Test(arguments: ["K7M2QX9", "K7M2QX9PP", "K7M2QX0P", "K7M2QXIP", "K7M2QXLP", "K7M2QXOP", "练练练练练练练练"])
    func inviteCodeRefusesWhatCantBeOne(typed: String) {
        #expect(throws: ContractsError.invalidInviteCode(typed)) { try InviteCode(typed) }
    }
}
