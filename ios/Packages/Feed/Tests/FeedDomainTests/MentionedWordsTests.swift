import Contracts
import Testing

@testable import FeedDomain

@Test func eachAtOfSomeoneBecomesTheirTagAndTheRestStaysPlain() {
    let (mia, leo) = (member(1), member(2))
    let words = MentionedWords(
        "@Mia @毛头 今天和@Leo 一起跑", people: [(.member(mia), "Mia"), (.member(leo), "Leo"), (.coach("xiaohun"), "毛头")])
    #expect(
        words.runs == [
            .tag("@Mia", .member(mia)), .plain(" "), .tag("@毛头", .coach("xiaohun")), .plain(" 今天和"),
            .tag("@Leo", .member(leo)), .plain(" 一起跑"),
        ])
}

@Test func twoTeammatesOfTheSameNameEachGetTheirOwnAtInTheOrderWritten() {
    let (first, second) = (member(1), member(2))
    let words = MentionedWords("@Mia 和 @Mia 都来", people: [(.member(first), "Mia"), (.member(second), "Mia")])
    #expect(
        words.runs == [.tag("@Mia", .member(first)), .plain(" 和 "), .tag("@Mia", .member(second)), .plain(" 都来")])
}

@Test func aLongerNameIsNotTakenForAShorterOne() {
    let (short, long) = (member(1), member(2))
    let words = MentionedWords("@毛毛头 @毛毛", people: [(.member(short), "毛毛"), (.member(long), "毛毛头")])
    #expect(words.runs == [.tag("@毛毛头", .member(long)), .plain(" "), .tag("@毛毛", .member(short))])
}

@Test func anAtOfNoOneOrANameNotWrittenStaysPlain() {
    let words = MentionedWords("@路人 早", people: [(.member(member(1)), "Mia")])
    #expect(words.runs == [.plain("@路人 早")])
}

@Test func someoneTheAppCantNameIsGreyedUpToTheSpaceAfterTheirName() {
    let (mia, left) = (member(1), member(2))
    let words = MentionedWords("@Mia 和 @老王 今天都来了", people: [(.member(mia), "Mia")], unnamed: [left])
    #expect(
        words.runs == [
            .tag("@Mia", .member(mia)), .plain(" 和 "), .tag("@老王", .unnamed(left)), .plain(" 今天都来了"),
        ])
}

@Test func anAtLongerThanANicknameIsNotTakenForSomeoneWhoLeft() {
    let words = MentionedWords("@这一段字比任何昵称都要长得多了吧 早", people: [], unnamed: [member(2)])
    #expect(words.runs == [.plain("@这一段字比任何昵称都要长得多了吧 早")])
}
