import NotificationsDomain

/// iOS's permission and APNs registration, in memory. The prompt answers `answer`, and like iOS
/// only ever shows once.
actor FakeSystem: PushSystem {
    private(set) var state: PushAuthorization
    private let answer: Bool
    private(set) var prompts = 0
    private(set) var registrations = 0

    init(_ state: PushAuthorization, answers answer: Bool = true) {
        self.state = state
        self.answer = answer
    }

    func authorization() async -> PushAuthorization { state }

    func requestAuthorization() async -> Bool {
        guard state == .notDetermined else { return state == .allowed }
        prompts += 1
        state = answer ? .allowed : .denied
        return answer
    }

    func registerForRemoteNotifications() async { registrations += 1 }
}

/// The API's list of phones, recording every call.
actor FakeRegistry: DeviceRegistry {
    enum Call: Equatable {
        case register(PushDevice)
        case remove(DeviceToken)
    }

    private(set) var calls: [Call] = []
    private var failure: NotificationsError?

    init(failing failure: NotificationsError? = nil) { self.failure = failure }

    func recover() { failure = nil }

    func register(_ device: PushDevice) async throws(NotificationsError) {
        calls.append(.register(device))
        if let failure { throw failure }
    }

    func remove(_ token: DeviceToken) async throws(NotificationsError) {
        calls.append(.remove(token))
        if let failure { throw failure }
    }
}

let token = DeviceToken([0x0a, 0xff, 0x10] + Array(repeating: 0x01, count: 29))
let phone = PushDevice(token: token, environment: .sandbox)

/// The API's list of phones, where a registration stays on its way until `release()`.
actor SlowRegistry: DeviceRegistry {
    private(set) var calls: [FakeRegistry.Call] = []
    private var waiting: CheckedContinuation<Void, Never>?
    private var released = false

    func release() {
        released = true
        waiting?.resume()
        waiting = nil
    }

    func register(_ device: PushDevice) async throws(NotificationsError) {
        calls.append(.register(device))
        if !released { await withCheckedContinuation { waiting = $0 } }
    }

    func remove(_ token: DeviceToken) async throws(NotificationsError) {
        calls.append(.remove(token))
    }
}
