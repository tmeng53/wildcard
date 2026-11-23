#if DEBUG
import Darwin
import Foundation
import Synchronization
import os

/// While the UI tests run (a Debug build with no debugger attached), notes the main thread's stack
/// in the log each time it stays busy 5 seconds or more, and again at 10, 20, 40 and 80 seconds,
/// so a screen that froze on a slow CI Mac says what held it (#924: the compose page froze for
/// minutes after the line was typed). `scripts/ios-test.sh` prints the notes after the run.
/// Never in Release builds.
enum StallLog {
    /// Starts watching; call it on the main thread, first thing at launch.
    static func start() {
        guard !isDebuggerAttached, mainThread == nil else { return }
        mainThread = pthread_self()
        // Made now, never first in the handler, where a lazy static's first use isn't safe.
        frames.initialize(repeating: nil, count: capacity)
        taken.store(0, ordering: .releasing)
        var action = sigaction()
        // Only async-signal-safe work here: `backtrace` into memory allocated before any signal.
        action.__sigaction_u.__sa_handler = { _ in
            StallLog.taken.store(Int(backtrace(StallLog.frames, Int32(StallLog.capacity))), ordering: .releasing)
        }
        action.sa_flags = SA_RESTART
        action.sa_mask = 0
        sigaction(SIGUSR2, &action, nil)
        let watcher = Thread { watch() }
        watcher.name = "StallLog"
        watcher.qualityOfService = .userInteractive
        watcher.start()
    }

    private static let capacity = 256
    nonisolated(unsafe) private static let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>
        .allocate(capacity: capacity)
    nonisolated(unsafe) private static var mainThread: pthread_t?
    /// How many frames the last sample took; -1 while one is asked for.
    private static let taken = Atomic<Int>(0)
    /// Counted up by the main thread each time it gets to a ping.
    private static let beats = Atomic<Int>(0)
    private static let log = Logger(subsystem: "com.wildcardsquad.wildcard", category: "stall")

    private static func watch() {
        var stalled = 0
        var nextSample = 5
        var stall = 0
        while true {
            let before = beats.load(ordering: .acquiring)
            DispatchQueue.main.async { StallLog.beats.add(1, ordering: .releasing) }
            Thread.sleep(forTimeInterval: 1)
            guard beats.load(ordering: .acquiring) == before else {
                stalled = 0
                nextSample = 5
                continue
            }
            stalled += 1
            if stalled == 5 { stall += 1 }
            guard stalled >= nextSample else { continue }
            nextSample *= 2
            sample(stall: stall, seconds: stalled)
        }
    }

    /// Asks the main thread for its stack and writes it to the log, a frame a line, so no line is
    /// cut short.
    private static func sample(stall: Int, seconds: Int) {
        guard let mainThread else { return }
        taken.store(-1, ordering: .releasing)
        pthread_kill(mainThread, SIGUSR2)
        var waited = 0
        while taken.load(ordering: .acquiring) < 0, waited < 100 {
            Thread.sleep(forTimeInterval: 0.01)
            waited += 1
        }
        let count = taken.load(ordering: .acquiring)
        guard count > 0, let symbols = backtrace_symbols(frames, Int32(count)) else {
            log.error("stall \(stall) at \(seconds)s: no stack")
            return
        }
        defer { free(symbols) }
        log.error("stall \(stall) at \(seconds)s: main thread busy, \(count) frames")
        for index in 0..<count {
            let line = symbols[index].map { String(cString: $0) } ?? "?"
            log.error("stall \(stall) at \(seconds)s #\(index): \(line, privacy: .public)")
        }
    }

    private static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}
#endif
