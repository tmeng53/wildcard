import AvatarArt
import CheckInDomain
import Testing

/// While its page has news the coach whistles every `newsWhistlePeriod`: each coach's whistle
/// ends with a rest before the next, so one never cuts the last short.
@Test(arguments: CoachCharacter.bundled)
func everyCoachsWhistleFitsBetweenItsNewsWhistles(coach: String) throws {
    let whistle = try CoachCharacter.clip(.whistle, coach: coach)
    #expect(whistle.duration < CoachCue.newsWhistlePeriod)
}
