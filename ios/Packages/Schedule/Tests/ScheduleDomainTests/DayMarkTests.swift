import Contracts
import ScheduleDomain
import Testing

/// What a day's row says and whether it is ticked, from its plan and how it went.
struct DayMarkTests {
    private let strength = Activity.sport("strength")
    private let play = Activity.sport("play")

    @Test func aPlannedSportTrainedIsTicked() {
        let face = DayMark.trained([play, strength]).face(of: .train(strength))
        #expect(face.shown == .train(strength))
        #expect(face.mark == .trained([play, strength]))
    }

    @Test func aPlannedSportNotTrainedIsShownUnticked() {
        let face = DayMark.trained([play]).face(of: .train(strength))
        #expect(face.shown == .train(strength))
        #expect(face.mark == .none)
    }

    @Test func aRestOrOpenDayTrainedShowsTheLatestSportTicked() {
        #expect(DayMark.trained([strength, play]).face(of: .rest).shown == .train(play))
        #expect(DayMark.trained([strength, play]).face(of: .rest).mark == .trained([strength, play]))
        #expect(DayMark.trained([strength]).face(of: .train(nil)).shown == .train(strength))
    }

    @Test func otherDaysShowThePlanAsTheyWent() {
        #expect(DayMark.disclaimer.face(of: .train(strength)) == (.train(strength), .disclaimer))
        #expect(DayMark.none.face(of: .rest) == (.rest, .none))
    }
}
