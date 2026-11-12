#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// A post going out behind the scene once its page closed, told on 打卡's spot: 正在发送… with
/// how far it is, then 已发出 with 查看, or 没网 when it has to wait. A post the server refuses
/// is told by the home's refusal banner instead.
extension TodayModel {
    enum Outgoing: Equatable {
        /// Going out now.
        case sending(CheckInID)
        /// The server saved it; 查看 opens it.
        case sent(CheckIn)
        /// It couldn't go out; it waits on the phone and goes out with the next send.
        case waiting
    }

    /// How long 已发出 or 没网 stays before 打卡 comes back.
    static let outgoingHold: Duration = .seconds(3)

    /// How far the post going out is, from 0 to 1; nil when none is.
    var outgoingProgress: Double? {
        guard case .sending(let id) = outgoing else { return nil }
        return store.progress(of: id) ?? 1
    }

    /// Sends the queued post `id` and tells how it went. A newer post takes the spot over.
    func deliver(_ id: CheckInID) {
        outgoing = .sending(id)
        Task {
            let delivery = await store.deliver(id)
            guard outgoing == .sending(id) else { return }
            switch delivery {
            case .posted(let saved):
                outgoing = .sent(saved)
            case .waiting:
                outgoing = .waiting
            case .refused:
                outgoing = nil
                return
            }
            let told = outgoing
            try? await Task.sleep(for: Self.outgoingHold)
            if outgoing == told { outgoing = nil }
        }
    }

    /// Puts 打卡 back at once, as a tap on 没网 does.
    func dismissOutgoing() {
        if outgoing == .waiting { outgoing = nil }
    }
}
#endif
