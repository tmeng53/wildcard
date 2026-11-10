import CheckInDomain
import Contracts
import Testing

@MainActor @Test func aCharacterSavedInTheEditorIsWornOnTheHomeAtOnce() async throws {
    let today = store(ScriptedBackend())
    await today.load()
    let dressed = MemberCharacter(
        nickname: try Nickname("小米"), look: CharacterLook(persona: "drama", variants: ["body": "cat"]))
    today.wear(dressed)
    #expect(today.home?.mine?.character == dressed)
    // Only the member's own character changes.
    #expect(today.home?.today.members.filter { $0.character == dressed }.count == 1)
}
