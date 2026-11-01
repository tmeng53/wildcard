import Contracts
import Testing

@Test func aDisclaimerIsOfferedUntilTheDayIsTrained() {
    #expect(TrainingStatus.notCheckedIn.allowsDisclaimer)
    #expect(!TrainingStatus.trained.allowsDisclaimer)
    #expect(TrainingStatus.disclaimer.allowsDisclaimer)
}
