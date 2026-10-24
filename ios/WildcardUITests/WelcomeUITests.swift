import CoreGraphics
import UIKit
import XCTest

/// The open screen with the real Sign in with Apple button, as the hosted app shows it: still
/// once WILDCARD breaks the tape.
@MainActor
final class WelcomeUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The floor (and the squad standing on it) never moves while the sprint plays, when the
    /// tape breaks, when the slogan and button come up, or when the sprint ends, at launch and
    /// again when the app comes back from the background. Measured from screenshots taken as
    /// fast as the simulator allows: the first row of the floor at the screen's left edge, and,
    /// for the log, the top of the middle character's head.
    func testTheFloorStaysStillThroughTheSprint() {
        let app = launchFresh()
        var shots = sample(for: 7)
        let crowd = app.buttons.matching(identifier: "signup.crowd").allElementsBoundByIndex.map(\.frame)
        let signIn = app.descendants(matching: .any)["signup.signIn"].frame
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        // Sample only once the app is back on screen: frames of the system's switch back show
        // the home screen, not the floor.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.wait))
        XCTAssertTrue(app.buttons["signup.crowd"].firstMatch.waitForExistence(timeout: Self.wait))
        Thread.sleep(forTimeInterval: 0.6)
        shots += sample(for: 7, after: (shots.last?.time ?? 0) + 3)
        let biggest = crowd.max { $0.width < $1.width }
        let measured = shots.map { shot in
            let bitmap = Bitmap(shot.shot)
            let floor = bitmap?.floorTop()
            let head = biggest.flatMap { frame in bitmap?.firstInk(around: frame.midX, from: frame.minY, to: floor) }
            return (time: shot.time, floor: floor, head: head)
        }
        let rows = measured.compactMap(\.floor)
        XCTAssertGreaterThan(rows.count, 10, "too few screenshots showed the floor")
        let log =
            measured.map { each in
                let floor = each.floor.map { "\($0)" } ?? "-"
                let head = each.head.map { "\($0)" } ?? "-"
                return "\(String(format: "%.2f", each.time))s: floor \(floor) head \(head)"
            } + ["sign-in \(signIn)", "crowd \(crowd)"]
        print("welcome floor and head top (pt) by time:\n" + log.joined(separator: "\n"))
        // Keep a frame every second, and the frames around each move of the floor, for review.
        var kept = -1.0
        for (index, each) in measured.enumerated() {
            if each.time - kept >= 1 {
                kept = each.time
                keep(shots[index].shot, named: "45-welcome-\(String(format: "%05.2f", each.time))s")
            }
            if index > 0, let floor = each.floor, let before = measured[index - 1].floor, floor != before {
                keep(shots[index - 1].shot, named: "45-welcome-before-move-\(index)")
                keep(shots[index].shot, named: "45-welcome-after-move-\(index)")
            }
        }
        XCTAssertEqual(Set(rows).count, 1, "the floor moved:\n" + log.joined(separator: "\n"))
    }

    private struct Shot {
        let time: TimeInterval
        let shot: XCUIScreenshot
    }

    private func sample(for seconds: TimeInterval, after offset: TimeInterval = 0) -> [Shot] {
        let start = Date()
        var shots: [Shot] = []
        while Date().timeIntervalSince(start) < seconds {
            shots.append(Shot(time: offset + Date().timeIntervalSince(start), shot: XCUIScreen.main.screenshot()))
        }
        return shots
    }

    /// A screenshot's pixels, RGBA, read in points.
    private struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: Double

        init?(_ shot: XCUIScreenshot) {
            let image = shot.image
            guard let bitmap = image.cgImage else { return nil }
            let (width, height) = (bitmap.width, bitmap.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            (self.pixels, self.width, self.height, scale) = (pixels, width, height, image.scale)
        }

        /// Whether the pixel differs from the page's colour (the brand sky, #F2F3F5).
        private func isInk(column: Int, row: Int) -> Bool {
            let index = (row * width + column) * 4
            let distance =
                abs(Int(pixels[index]) - 0xF2) + abs(Int(pixels[index + 1]) - 0xF3) + abs(Int(pixels[index + 2]) - 0xF5)
            return distance > 12
        }

        /// The first row from the middle of the screen down whose left-edge pixel isn't the
        /// page's colour, in points; nil when the column never changes.
        func floorTop() -> Double? {
            for row in (height / 2)..<height where isInk(column: 4, row: row) { return Double(row) / scale }
            return nil
        }

        /// The first row from `top` down to `bottom` (points) with ink within 12 points of `middle`.
        func firstInk(around middle: Double, from top: Double, to bottom: Double?) -> Double? {
            let columns = max(0, Int((middle - 12) * scale))...min(width - 1, Int((middle + 12) * scale))
            let first = max(0, Int(top * scale))
            let last = min(height, Int((bottom ?? Double(height) / scale) * scale))
            guard first < last else { return nil }
            for row in first..<last where columns.contains(where: { isInk(column: $0, row: row) }) {
                return Double(row) / scale
            }
            return nil
        }
    }

    /// The open screen in Chinese, with the real Apple button.
    private func launchFresh() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-onboarding", "-apple-sign-in",
            "-uitest-monday",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func keep(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
