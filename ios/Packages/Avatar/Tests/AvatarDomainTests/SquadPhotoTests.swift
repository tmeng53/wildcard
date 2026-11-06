import Testing

@testable import AvatarDomain

struct SquadPhotoTests {
    @Test func threeStandInARowAsBigAsTheBoxAllows() {
        let photo = SquadPhoto(count: 3, width: 360, height: 190)
        // 360 / 3 = 120 wide, so 160 tall: the width limits them, not the height.
        #expect(photo.figureWidth == 120)
        #expect(photo.figureHeight == 160)
        #expect(photo.spots.map(\.left) == [0, 120, 240])
        #expect(photo.spots.map(\.top) == [30, 30, 30])
    }

    @Test func oneStandsCenteredAtTheBoxsHeight() {
        let photo = SquadPhoto(count: 1, width: 360, height: 120)
        #expect(photo.figureHeight == 120)
        #expect(photo.spots == [SquadPhoto.Spot(member: 0, left: 135, top: 0)])
    }

    @Test func sevenStandInTwoRowsTheBackRowBetweenTheFront() {
        let photo = SquadPhoto(count: 7, width: 360, height: 280)
        // Front row of 4 → 90 wide, 120 tall; the box allows 280 / 1.4 = 200, so width limits.
        #expect(photo.figureWidth == 90)
        #expect(photo.figureHeight == 120)
        #expect(photo.spots.map(\.member) == [4, 5, 6, 0, 1, 2, 3])
        #expect(photo.spots.map(\.left) == [45, 135, 225, 0, 90, 180, 270])
        #expect(photo.spots.map(\.top) == [112, 112, 112, 160, 160, 160, 160])
    }

    @Test func eightStandInTwoRowsHalfAFigureApart() {
        let photo = SquadPhoto(count: 8, width: 360, height: 280)
        // 4.5 figures across → 80 wide.
        #expect(photo.figureWidth == 80)
        #expect(photo.spots.map(\.left) == [40, 120, 200, 280, 0, 80, 160, 240])
    }

    @Test(arguments: 1...8) func everyoneFitsInsideTheBox(count: Int) {
        let photo = SquadPhoto(count: count, width: 370, height: 190)
        #expect(photo.spots.count == count)
        #expect(Set(photo.spots.map(\.member)) == Set(0..<count))
        for spot in photo.spots {
            #expect(spot.left >= -0.001)
            #expect(spot.left + photo.figureWidth <= 370.001)
            #expect(spot.top >= -0.001)
            #expect(spot.top + photo.figureHeight <= 190.001)
        }
    }

    @Test func theWaveRunsLeftToRightAcrossBothRows() {
        #expect(SquadPhoto.leftToRight(count: 3) == [0, 1, 2])
        // Front 0 1 2 3, back 4 5 6 between them.
        #expect(SquadPhoto.leftToRight(count: 7) == [0, 4, 1, 5, 2, 6, 3])
        // Front 0 1 2 3, back 4 5 6 7 half a figure to the right.
        #expect(SquadPhoto.leftToRight(count: 8) == [0, 4, 1, 5, 2, 6, 3, 7])
    }
}
