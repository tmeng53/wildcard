import Foundation
import Sentry

/// Crash, hang and MetricKit reports to Sentry, for builds whose settings name a DSN (Release,
/// through Info.plist's `WildcardSentryDSN`). Without one, as in Debug builds and UI tests, it
/// never starts and the app runs as before.
///
/// A report carries the device, the OS, the build and the stack, never who the member is: no
/// member id, no screenshots or view hierarchy, no session replay, no network breadcrumbs or
/// failed-request events (their URLs hold squad ids and invite codes) and no performance tracing.
/// The privacy manifest and wildcardsquad.com/privacy declare Crash Data and Performance Data, not
/// linked to the member; change them together.
enum CrashReports {
    /// Starts reporting, first thing at launch, so a crash during launch is caught.
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "WildcardSentryDSN") as? String, !dsn.isEmpty
        else { return }
        // Options built here and handed over, not a configure closure: a closure written in the
        // main actor's init would inherit its isolation, and Swift 6 traps if the SDK calls it
        // elsewhere.
        let options = Options()
        options.dsn = dsn
        options.sendDefaultPii = false
        // What we want: crashes (on by default), hangs, MetricKit's hang, CPU and disk-write
        // diagnostics, and launches the system ended for using too much memory.
        options.enableAppHangTracking = true
        options.enableMetricKit = true
        options.enableWatchdogTerminationTracking = true
        // What we never send.
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        SentrySDK.start(options: options)
    }
}
