import Contracts
import Foundation
import Observation

/// What the member picked on 意见反馈: 出问题了 or 提个建议.
public enum FeedbackKind: String, CaseIterable, Hashable, Sendable {
    case problem
    case idea
}

/// Which app a message came from, so whoever fixes it knows where to look. Never who sent it.
public struct FeedbackApp: Hashable, Sendable {
    public let appVersion: String
    public let build: String
    public let system: String
    public let device: String
    public let language: String

    public init(appVersion: String, build: String, system: String, device: String, language: String) {
        (self.appVersion, self.build, self.system, self.device, self.language) = (
            appVersion, build, system, device, language
        )
    }
}

/// A screenshot added to a message: a JPEG, with an id to remove it by.
public struct FeedbackScreenshot: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let jpeg: Data

    public init(id: UUID, jpeg: Data) {
        self.id = id
        self.jpeg = jpeg
    }
}

/// One message to us, as it is sent. Its id stays the same across retries, so it is saved once.
public struct FeedbackMessage: Hashable, Sendable {
    public let id: UUID
    public let kind: FeedbackKind
    public let text: FeedbackText
    public let screenshots: [Data]
    public let app: FeedbackApp
}

/// Why a message didn't go, by what the member can do about it.
public enum FeedbackError: Error, Hashable, Sendable {
    /// No connection, or the server is down: what they wrote stays, to send again.
    case unavailable
    /// They sent as many as a day allows: they can email us instead.
    case limit
    /// The session ended: sign in again.
    case signedOut
}

/// How a message reaches us. An adapter uploads the screenshots and sends it to the API.
public protocol FeedbackService: Sendable {
    func send(_ message: FeedbackMessage) async throws(FeedbackError)
}

/// Feedback kept in memory and never sent anywhere: the sample member's, and previews'.
public actor KeptFeedback: FeedbackService {
    public private(set) var sent: [FeedbackMessage] = []

    public init() {}

    public func send(_ message: FeedbackMessage) async throws(FeedbackError) {
        sent.append(message)
    }
}

/// 意见反馈 on screen: the kind, the words, up to 3 screenshots, and sending them. What was
/// written stays on the page until it is sent; a send that fails says why and keeps it all.
@MainActor @Observable
public final class FeedbackModel {
    public enum Phase: Hashable, Sendable {
        case writing
        case sending
        case sent
        case failed(FeedbackError)
    }

    public var kind: FeedbackKind = .problem
    /// What the member wrote; never longer than `FeedbackText.maxLength` characters.
    public var text = "" {
        didSet {
            if text.count > FeedbackText.maxLength { text = String(text.prefix(FeedbackText.maxLength)) }
        }
    }
    public private(set) var screenshots: [FeedbackScreenshot] = []
    public private(set) var phase: Phase = .writing

    @ObservationIgnored private let service: any FeedbackService
    @ObservationIgnored private let app: FeedbackApp
    @ObservationIgnored private let newID: () -> UUID
    /// The message last tried, so trying the same one again sends it with the same id.
    @ObservationIgnored private var tried: (id: UUID, draft: Draft)?

    /// What was written and picked, to tell a retry from a new message.
    private struct Draft: Equatable {
        let kind: FeedbackKind
        let text: String
        let shots: [UUID]
    }

    /// `app` says which app this is; `newID` makes each message's and screenshot's id.
    public init(service: any FeedbackService, app: FeedbackApp, newID: @escaping () -> UUID) {
        self.service = service
        self.app = app
        self.newID = newID
    }

    /// How many characters are written, as the counter shows it.
    public var count: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    public var canAddScreenshot: Bool { screenshots.count < FeedbackText.maxScreenshots && phase != .sending }

    /// 发送 works once something is written, and not while it is going.
    public var canSend: Bool { (try? FeedbackText(text)) != nil && phase != .sending && phase != .sent }

    public func add(screenshot jpeg: Data) {
        guard canAddScreenshot else { return }
        screenshots.append(FeedbackScreenshot(id: newID(), jpeg: jpeg))
    }

    public func remove(screenshot id: FeedbackScreenshot.ID) {
        screenshots.removeAll { $0.id == id }
    }

    public func send() async {
        guard canSend, let words = try? FeedbackText(text) else { return }
        let shots = screenshots.map(\.id)
        let id: UUID
        let draft = Draft(kind: kind, text: words.text, shots: shots)
        if let tried, tried.draft == draft {
            id = tried.id
        } else {
            id = newID()
        }
        tried = (id, draft)
        phase = .sending
        do {
            try await service.send(
                FeedbackMessage(id: id, kind: kind, text: words, screenshots: screenshots.map(\.jpeg), app: app))
            phase = .sent
        } catch {
            phase = .failed(error)
        }
    }
}
