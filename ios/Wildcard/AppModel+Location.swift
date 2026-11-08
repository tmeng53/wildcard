import Backend
import LocationDomain
import LocationUI

extension AppModel {
    /// The phone's approximate location for the coach's weather, one for the app: sign-up's
    /// 打开大概位置 and 设置 › 位置 ask with it, and it follows whoever is signed in.
    static let location = LocationSharing(reader: CoreLocationReader(), sent: DefaultsSentPlace())

    /// Registers this phone for push, and its approximate location for the coach's weather.
    func registerDevice() async {
        try? await Push.registration.signedIn(APIDeviceRegistry(api: api))
        await Self.location.signedIn(APILocationRegistry(api: api))
    }
}
