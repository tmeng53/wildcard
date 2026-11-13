import Contracts
import Foundation
import Testing

private let squadA = SquadID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
private let squadB = SquadID(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)

@Test func disclaimerLengthCountsCharactersPeopleSee() throws {
    #expect(try Disclaimer(String(repeating: "累", count: 80)).text.count == 80)
    #expect(throws: ContractsError.disclaimerLength(81)) { try Disclaimer(String(repeating: "累", count: 81)) }
    #expect(throws: ContractsError.disclaimerLength(0)) { try Disclaimer("   ") }
    #expect(try Disclaimer("  腿还在酸\n明天一定  ").text == "腿还在酸\n明天一定")
}

@Test func emptyPhotoPathIsRejected() {
    #expect(throws: ContractsError.emptyPhotoPath) { try PhotoRef(path: "") }
}

@Test func idsPrintLowercase() {
    let upper = CheckInID(UUID(uuidString: "ABCDEF01-ABCD-ABCD-ABCD-ABCDEF012345")!)
    #expect(upper.description == "abcdef01-abcd-abcd-abcd-abcdef012345")
}

@Test func audienceIsDistinctSquads() throws {
    #expect(try Audience([squadA, squadB]).squads == [squadA, squadB])
    #expect(try Audience([]).squads == [])
    #expect(throws: ContractsError.repeatedSquad) { try Audience([squadA, squadA]) }
}

@Test func captionIsOneLineOfUpToSixtyCharacters() throws {
    #expect(try Caption(String(repeating: "爽", count: 60)).text.count == 60)
    #expect(throws: ContractsError.captionLength(61)) { try Caption(String(repeating: "爽", count: 61)) }
    #expect(throws: ContractsError.captionLength(0)) { try Caption(" ") }
    #expect(throws: ContractsError.multilineCaption) { try Caption("第一行\n第二行") }
    #expect(try Caption("  雨中五公里 ").text == "雨中五公里")
}

@Test func catchphraseIsOneLineOfUpToTenCharacters() throws {
    #expect(try Catchphrase("今天也冲冲冲的一天👍🏽").text.count == 10)
    #expect(throws: ContractsError.catchphraseLength(11)) { try Catchphrase(String(repeating: "冲", count: 11)) }
    #expect(throws: ContractsError.catchphraseLength(0)) { try Catchphrase(" ") }
    #expect(throws: ContractsError.multilineCatchphrase) { try Catchphrase("冲\n冲") }
    #expect(try Catchphrase("  冲就完了🔥 ").text == "冲就完了🔥")
}

@Test func customSportNameMustFitOnOneLine() throws {
    #expect(throws: ContractsError.customSportLength(21)) { try CustomSport(String(repeating: "练", count: 21)) }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\n高尔夫") }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\t高尔夫") }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\u{0}") }
    #expect(try CustomSport("飞盘 高尔夫 🏃‍♀️").name == "飞盘 高尔夫 🏃‍♀️")
}

@Test(arguments: ["\u{200D}", "\u{200C}", "\u{2060}", "\u{FEFF}", "\u{00AD}", "\u{200D} \u{200D}"])
func customSportNameMustShowSomething(name: String) {
    #expect(throws: ContractsError.invisibleCustomSport) { try CustomSport(name) }
}

@Test(arguments: ["\u{202E}", "\u{202A}", "\u{2066}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{061C}"])
func customSportNameHasNoDirectionControls(control: String) {
    #expect(throws: ContractsError.invisibleCustomSport) { try CustomSport("飞盘\(control)golf") }
}

@Test func photosAreOneToThreeDistinctWithTheFirstAsCover() throws {
    let first = try PhotoRef(path: "m/a.jpg")
    let second = try PhotoRef(path: "m/b.jpg")
    let third = try PhotoRef(path: "m/c.jpg")
    let photos = try Photos([first, second, third])
    #expect(photos.cover == first)
    #expect(throws: ContractsError.photoCount(0)) { try Photos([]) }
    #expect(throws: ContractsError.photoCount(4)) { try Photos([first, second, third, try PhotoRef(path: "m/d.jpg")]) }
    #expect(throws: ContractsError.repeatedPhoto) { try Photos([first, first]) }
}

@Test func thePhotoNotItsViewURLMakesItARepeat() throws {
    let saved = try PhotoRef(path: "m/a.jpg", viewURL: URL(string: "https://example.com/a?token=1"))
    let again = try PhotoRef(path: "m/a.jpg", viewURL: URL(string: "https://example.com/a?token=2"))
    #expect(throws: ContractsError.repeatedPhoto) { try Photos([saved, again]) }
}

@Test func aPhotoIsTheSameWhateverURLItWasListedWith() throws {
    let listed = try PhotoRef(path: "m/a.jpg", viewURL: URL(string: "https://example.com/a?token=1"))
    let relisted = try PhotoRef(path: "m/a.jpg", viewURL: URL(string: "https://example.com/a?token=2"))
    let sent = try PhotoRef(path: "m/a.jpg")
    #expect(listed == relisted)
    #expect(listed == sent)
    #expect(Set([listed, relisted, sent]).count == 1)
    #expect(try PhotoRef(path: "m/b.jpg", viewURL: listed.viewURL) != listed)
}

@Test func nicknameIsOneLineOfUpToTwelveCharacters() throws {
    #expect(try Nickname("  早八跑团的小周同学👍🏽冲 ").text == "早八跑团的小周同学👍🏽冲")
    #expect(throws: ContractsError.nicknameLength(13)) { try Nickname(String(repeating: "周", count: 13)) }
    #expect(throws: ContractsError.nicknameLength(0)) { try Nickname(" \u{3000} ") }
    #expect(throws: ContractsError.multilineNickname) { try Nickname("小\n周") }
    #expect(throws: ContractsError.multilineNickname) { try Nickname("小\t周") }
    #expect(throws: ContractsError.invisibleNickname) { try Nickname("\u{200D}") }
    #expect(throws: ContractsError.invisibleNickname) { try Nickname("小\u{202E}周") }
    #expect(try Nickname("Ann Lee").text == "Ann Lee")
}

@Test func startTimeIsATimeOfDayToTheMinute() throws {
    #expect(try StartTime(hour: 0, minute: 0).wire == "00:00")
    #expect(try StartTime(hour: 23, minute: 59).wire == "23:59")
    #expect(try StartTime(wire: "07:30") == StartTime(hour: 7, minute: 30))
    #expect(throws: ContractsError.startTime("24:0")) { try StartTime(hour: 24, minute: 0) }
    #expect(throws: ContractsError.startTime("7:30")) { try StartTime(wire: "7:30") }
    #expect(throws: ContractsError.startTime("07:60")) { try StartTime(wire: "07:60") }
    #expect(try StartTime(hour: 6, minute: 59) < StartTime(hour: 7, minute: 0))
}

@Test func aPlaceKeepsToTheAPIsRules() throws {
    let place = try Place(name: "  Equinox Flatiron ", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
    #expect(place.name == "Equinox Flatiron")
    #expect(place.category == "fitnessCenter")
    #expect(try Place(name: "x", category: "fitness_center", latitude: 0, longitude: 0).category == nil)
    #expect(try Place(name: "x", appleID: "", latitude: 0, longitude: 0).appleID == nil)
    #expect(throws: ContractsError.placeName(0)) { try Place(name: "   ", latitude: 0, longitude: 0) }
    #expect(throws: ContractsError.placeName(101)) {
        try Place(name: String(repeating: "店", count: 101), latitude: 0, longitude: 0)
    }
    #expect(throws: ContractsError.placeCoordinate(latitude: 91, longitude: 0)) {
        try Place(name: "x", latitude: 91, longitude: 0)
    }
}
