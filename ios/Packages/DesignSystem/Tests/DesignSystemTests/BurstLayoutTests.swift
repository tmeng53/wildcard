import Testing

@testable import DesignSystem

struct BurstLayoutTests {
    /// English words on the smallest phone with large text: no two capsules, nor a capsule and
    /// the button, touch, and every capsule stays on the screen.
    @Test(arguments: [
        ([100.0, 130, 130, 120], 390.0), ([100.0, 130, 130, 120], 320.0), ([160.0, 200, 190, 180], 320.0),
        ([74.0, 84, 84, 90], 320.0), ([300.0, 300, 300, 300], 320.0),
    ])
    func capsulesNeverTouch(widths: [Double], screen: Double) {
        let height = Sizing.control
        let button = (width: 130.0, height: Sizing.primaryControl)
        let spots = BurstLayout.positions(widths: widths, height: height, button: button, available: screen)
        let boxes = zip(spots, widths).map {
            BurstLayout.Box(midX: $0.0.x, midY: $0.0.y, width: $0.1, height: height)
        }
        let buttonBox = BurstLayout.Box(midX: 0, midY: 0, width: button.width, height: button.height)
        for (index, box) in boxes.enumerated() {
            #expect(!box.collides(with: buttonBox))
            #expect(abs(box.midX) + box.width / 2 <= screen / 2 + 0.001)
            for other in boxes.dropFirst(index + 1) { #expect(!box.collides(with: other)) }
        }
    }

    /// With room to spare the capsules stay on the approved arc.
    @Test func wideScreensKeepTheArc() {
        let spots = BurstLayout.positions(
            widths: [74, 84, 84, 90], height: Sizing.control, button: (width: 100, height: Sizing.primaryControl),
            available: 390)
        #expect(spots.map { ($0.x * 10).rounded() / 10 } == [-121.7, -60.1, 60.1, 121.7])
    }
}
