import XCTest
@testable import GlassDock

final class PiPKeepLiveTests: XCTestCase {
    private let hidden = CGRect(x: 2560, y: 25, width: 2560, height: 1415)

    private func block(isEnabled: Bool = true, isOwnApp: Bool = false, isFullScreen: Bool = false, isMinimized: Bool = false,
                       isHidden: Bool = false, isPositionSettable: Bool = true, isOnHiddenDisplay: Bool = false) -> PiPKeepLive.Block? {
        PiPKeepLive.block(isEnabled: isEnabled, isOwnApp: isOwnApp, isFullScreen: isFullScreen, isMinimized: isMinimized,
                          isHidden: isHidden, isPositionSettable: isPositionSettable, isOnHiddenDisplay: isOnHiddenDisplay)
    }

    func testAWindowThatFitsKeepsItsSizeAtTheTopLeft() {
        let target = PiPKeepLive.targetFrame(original: CGRect(x: 100, y: 200, width: 1200, height: 800), in: hidden)
        XCTAssertEqual(target, CGRect(x: 2560, y: 25, width: 1200, height: 800))
    }

    func testAWindowLargerThanTheDisplayShrinksToIt() {
        let target = PiPKeepLive.targetFrame(original: CGRect(x: 0, y: 0, width: 4000, height: 2000), in: hidden)
        XCTAssertEqual(target, hidden)
    }

    func testTargetFrameFollowsADisplayWithANegativeOrigin() {
        let left = CGRect(x: -2560, y: 25, width: 2560, height: 1415)
        let target = PiPKeepLive.targetFrame(original: CGRect(x: 10, y: 10, width: 900, height: 600), in: left)
        XCTAssertEqual(target, CGRect(x: -2560, y: 25, width: 900, height: 600))
    }

    func testTargetFrameOfADisplayAboveTheMainOneIsConvertedFromScreenCoordinates() {
        let above = DisplayArea(cocoaFrame: CGRect(x: 0, y: 900, width: 2560, height: 1440),
                                cocoaVisibleFrame: CGRect(x: 0, y: 900, width: 2560, height: 1415), primaryHeight: 900)
        XCTAssertEqual(above.visibleFrame.minY, -1440 + 25)
        let target = PiPKeepLive.targetFrame(original: CGRect(x: 50, y: 50, width: 800, height: 500), in: above.visibleFrame)
        XCTAssertEqual(target, CGRect(x: 0, y: -1415, width: 800, height: 500))
        XCTAssertTrue(PiPKeepLive.isOn(target, display: above.frame))
    }

    func testAWindowIsOnADisplayWhenItsMiddleIs() {
        XCTAssertTrue(PiPKeepLive.isOn(CGRect(x: 2500, y: 100, width: 400, height: 300), display: hidden))
        XCTAssertFalse(PiPKeepLive.isOn(CGRect(x: 2000, y: 100, width: 400, height: 300), display: hidden))
    }

    func testAnEligibleWindowIsNotBlocked() {
        XCTAssertNil(block())
    }

    func testEachConditionBlocksTheMove() {
        XCTAssertEqual(block(isEnabled: false), .disabled)
        XCTAssertEqual(block(isOwnApp: true), .ownApp)
        XCTAssertEqual(block(isFullScreen: true), .fullScreen)
        XCTAssertEqual(block(isMinimized: true), .minimized)
        XCTAssertEqual(block(isHidden: true), .hidden)
        XCTAssertEqual(block(isPositionSettable: false), .notMovable)
        XCTAssertEqual(block(isOnHiddenDisplay: true), .onHiddenDisplay)
    }

    func testTheSettingBeingOffWinsOverEveryOtherReason() {
        XCTAssertEqual(block(isEnabled: false, isFullScreen: true, isPositionSettable: false), .disabled)
    }

    func testOnlyWindowsThatCannotBeKeptLiveGetANote() {
        XCTAssertNil(PiPKeepLive.Block.disabled.note)
        XCTAssertNil(PiPKeepLive.Block.ownApp.note)
        XCTAssertNil(PiPKeepLive.Block.onHiddenDisplay.note)
        for reason in [PiPKeepLive.Block.fullScreen, .minimized, .hidden, .notMovable] {
            XCTAssertEqual(reason.note, PiPKeepLive.cannotKeepNote)
        }
    }

    func testRestoreGoesToTheOriginalFrameWhileItsDisplayExists() {
        let original = CGRect(x: 3000, y: 100, width: 1000, height: 700)
        let frame = PiPKeepLive.restoreFrame(original: original, originalDisplay: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
                                             fallback: CGRect(x: 0, y: 25, width: 1512, height: 920))
        XCTAssertEqual(frame, original)
    }

    func testRestoreMovesIntoTheMainDisplayWhenTheOriginalDisplayIsGone() {
        let fallback = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let frame = PiPKeepLive.restoreFrame(original: CGRect(x: 3000, y: 100, width: 1000, height: 700),
                                             originalDisplay: nil, fallback: fallback)
        XCTAssertEqual(frame, CGRect(x: 512, y: 100, width: 1000, height: 700))
    }

    func testRestoreShrinksAWindowThatIsLargerThanTheMainDisplay() {
        let fallback = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let frame = PiPKeepLive.restoreFrame(original: CGRect(x: 3000, y: 100, width: 2500, height: 1300),
                                             originalDisplay: nil, fallback: fallback)
        XCTAssertEqual(frame, fallback)
    }

    func testTheLimiterMovesFirstThenWaitsOutTheMinimumInterval() {
        var limiter = PiPKeepLiveLimiter()
        let start = Date()
        XCTAssertEqual(limiter.next(now: start), .move)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(0.5)), .wait)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(1)), .move)
    }

    func testTheLimiterGivesUpAfterThreeMovesInARow() {
        var limiter = PiPKeepLiveLimiter()
        let start = Date()
        XCTAssertEqual(limiter.next(now: start), .move)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(1)), .move)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(2)), .move)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(3)), .giveUp)
        XCTAssertEqual(limiter.next(now: start.addingTimeInterval(4)), .giveUp)
    }

    func testMovesFarApartDoNotCountAsInARow() {
        var limiter = PiPKeepLiveLimiter()
        let start = Date()
        for step in 0..<6 {
            XCTAssertEqual(limiter.next(now: start.addingTimeInterval(Double(step) * PiPKeepLiveLimiter.settleInterval)), .move)
        }
    }
}
