import APIContract
import Contracts
import Foundation
import MeDomain

// 意见反馈: a member's message to us, with its screenshots.
extension WildcardAPI {
    /// Sends a message whose screenshots are uploaded already, under the id the app picked: the
    /// same message again is a retry, and saves nothing new.
    public func sendFeedback(_ message: FeedbackMessage, screenshots: [PhotoRef]) async throws(APIError) {
        let kind: Components.Schemas.FeedbackDraft.KindPayload =
            switch message.kind {
            case .problem: .problem
            case .idea: .idea
            }
        let app = message.app
        try await call {
            switch try await client.sendFeedback(
                body: .json(
                    .init(
                        version: ._1, id: message.id.uuidString.lowercased(), kind: kind, body: message.text.text,
                        screenshots: screenshots.map(\.path),
                        app: .init(
                            appVersion: app.appVersion, build: app.build, os: app.system, device: app.device,
                            language: app.language))))
            {
            case .ok, .created: return
            default: throw APIError.unreadableResponse
            }
        }
    }
}

/// 意见反馈 over our API: each screenshot uploaded straight to storage, then the message.
public struct APIFeedbackService: FeedbackService {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func send(_ message: FeedbackMessage) async throws(FeedbackError) {
        do {
            var uploaded: [PhotoRef] = []
            for jpeg in message.screenshots { uploaded.append(try await api.upload(jpeg, as: .jpeg)) }
            try await api.sendFeedback(message, screenshots: uploaded)
        } catch .account(.signedOut), .account(.credentialRejected) {
            throw .signedOut
        } catch .refused(.feedbackLimit) {
            throw .limit
        } catch {
            throw .unavailable
        }
    }
}
