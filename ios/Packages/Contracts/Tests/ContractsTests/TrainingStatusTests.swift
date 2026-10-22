import Contracts
import Testing

@Test func aDisclaimerIsOnlyOfferedBeforeTrainingAndOnceADay() {
    #expect(TrainingStatus.notCheckedIn.allowsDisclaimer)
    #expect(!TrainingStatus.trained.allowsDisclaimer)
    #expect(!TrainingStatus.disclaimer.allowsDisclaimer)
}
