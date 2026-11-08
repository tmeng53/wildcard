import Contracts
import Foundation
import Testing

@testable import MeDomain

private actor RecordingFeedback: FeedbackService {
    private(set) var sent: [FeedbackMessage] = []
    private var failures: [FeedbackError]

    init(failing failures: [FeedbackError] = []) { self.failures = failures }

    func send(_ message: FeedbackMessage) async throws(FeedbackError) {
        sent.append(message)
        if !failures.isEmpty { throw failures.removeFirst() }
    }
}

@MainActor
struct FeedbackModelTests {
    private let app = FeedbackApp(
        appVersion: "1.0", build: "180", system: "iOS 26.1", device: "iPhone17,3", language: "zh-Hans")

    private func ids() -> () -> UUID {
        var next = 0
        return {
            next += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", next)) ?? UUID()
        }
    }

    @Test func sendsTheTrimmedWordsWithScreenshotsAndTheApp() async {
        let service = RecordingFeedback()
        let model = FeedbackModel(service: service, app: app, newID: ids())
        #expect(!model.canSend)
        model.kind = .idea
        model.text = "  深色模式？ \n"
        model.add(screenshot: Data([1]))
        #expect(model.canSend)
        await model.send()
        #expect(model.phase == .sent)
        let sent = await service.sent
        #expect(sent.map(\.text.text) == ["深色模式？"])
        #expect(sent.map(\.kind) == [.idea])
        #expect(sent.map(\.screenshots) == [[Data([1])]])
        #expect(sent.map(\.app) == [app])
        #expect(!model.canSend)
    }

    @Test func keepsWhatWasWrittenWhenItFailsAndRetriesWithTheSameID() async {
        let service = RecordingFeedback(failing: [.unavailable])
        let model = FeedbackModel(service: service, app: app, newID: ids())
        model.text = "照片一直在转"
        await model.send()
        #expect(model.phase == .failed(.unavailable))
        #expect(model.text == "照片一直在转")
        await model.send()
        #expect(model.phase == .sent)
        let sent = await service.sent
        #expect(sent.count == 2)
        #expect(sent[0].id == sent[1].id)
    }

    @Test func anEditAfterAFailureIsANewMessage() async {
        let service = RecordingFeedback(failing: [.unavailable])
        let model = FeedbackModel(service: service, app: app, newID: ids())
        model.text = "照片一直在转"
        await model.send()
        model.text = "照片一直在转，退出重进才好"
        await model.send()
        let sent = await service.sent
        #expect(sent[0].id != sent[1].id)
    }

    @Test func takesThreeScreenshotsAndAThousandCharacters() {
        let model = FeedbackModel(service: RecordingFeedback(), app: app, newID: ids())
        for byte in 1...4 { model.add(screenshot: Data([UInt8(byte)])) }
        #expect(model.screenshots.map(\.jpeg) == [Data([1]), Data([2]), Data([3])])
        if let first = model.screenshots.first { model.remove(screenshot: first.id) }
        #expect(model.screenshots.map(\.jpeg) == [Data([2]), Data([3])])
        model.text = String(repeating: "字", count: 1001)
        #expect(model.text.count == FeedbackText.maxLength)
        #expect(model.count == 1000)
    }
}
