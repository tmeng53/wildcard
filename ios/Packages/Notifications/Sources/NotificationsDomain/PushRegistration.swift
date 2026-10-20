/// Gets this phone its pushes: asks for permission once the member has checked in for the first
/// time (never at sign-up, when they haven't seen what the app is for), asks APNs for a token on
/// every launch once allowed, and keeps the API's copy of it current while someone is signed in.
///
/// iOS hands over a token on every launch it is asked for, and the API takes the same one again
/// safely, so nothing here is stored: a registration that fails is made again on the next
/// launch.
public actor PushRegistration {
    private let system: any PushSystem
    private let environment: PushEnvironment
    private var token: DeviceToken?
    private var registry: (any DeviceRegistry)?

    public init(system: any PushSystem, environment: PushEnvironment) {
        self.system = system
        self.environment = environment
    }

    /// At launch: a phone that allows notifications asks APNs for its token again, since it can
    /// change (a restore, a reinstall).
    public func launched() async {
        if await system.authorization() == .allowed {
            await system.registerForRemoteNotifications()
        }
    }

    /// After a check-in is posted. The first one asks for permission; once the member has
    /// answered, iOS never shows the prompt again, so later ones do nothing.
    public func checkedIn() async {
        guard await system.authorization() == .notDetermined else { return }
        if await system.requestAuthorization() {
            await system.registerForRemoteNotifications()
        }
    }

    /// iOS handed over this install's token.
    public func received(_ token: DeviceToken) async throws(NotificationsError) {
        self.token = token
        try await registerIfSignedIn()
    }

    /// Someone signed in: their pushes come to this phone from now on.
    public func signedIn(_ registry: any DeviceRegistry) async throws(NotificationsError) {
        self.registry = registry
        try await registerIfSignedIn()
    }

    /// Before the session ends, while the API still takes it: this phone stops getting the
    /// member's pushes. If the API can't be reached they keep coming until someone signs in on
    /// this phone again, which moves the token to them.
    public func signingOut() async throws(NotificationsError) {
        guard let registry else { return }
        self.registry = nil
        if let token {
            try await registry.remove(token)
        }
    }

    private func registerIfSignedIn() async throws(NotificationsError) {
        guard let registry, let token else { return }
        try await registry.register(PushDevice(token: token, environment: environment))
    }
}
