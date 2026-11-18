import XCTest
@testable import GlassDock

final class MenuBarGapsTests: XCTestCase {
    private let builtIn = CGRect(x: 132, y: 1440, width: 2056, height: 1329)
    private let builtInNotch: ClosedRange<CGFloat> = 1050...1270
    private let external = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let externalPill: ClosedRange<CGFloat> = 1205...1355

    private func item(_ minX: CGFloat, _ width: CGFloat, on display: CGRect) -> CGRect {
        CGRect(x: minX, y: display.minY, width: width, height: 38)
    }

    func testTheGapsRunFromTheLastMenuAndTheFirstStatusItemToTheNotch() {
        let items = MenuBarItems(menus: [item(132, 40, on: builtIn), item(172, 300, on: builtIn)],
                                 statusItems: [item(1400, 30, on: builtIn), item(1330, 60, on: builtIn)],
                                 displays: [external, builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn), MenuBarGaps(left: 578, right: 60))
    }

    func testItemsHiddenBehindTheNotchAreIgnored() {
        let items = MenuBarItems(menus: [item(132, 100, on: builtIn)],
                                 statusItems: [item(1100, 30, on: builtIn), item(1500, 30, on: builtIn)],
                                 displays: [builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn), MenuBarGaps(left: 818, right: 230))
    }

    func testAnEmptySideReachesTheDisplayEdge() {
        let items = MenuBarItems(menus: [], statusItems: [item(1500, 30, on: builtIn)], displays: [builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn).left, 1050 - 132)
    }

    func testItemsReadOnAnotherDisplayKeepTheirDistanceFromItsEdges() {
        let items = MenuBarItems(menus: [item(0, 300, on: external)],
                                 statusItems: [item(2400, 30, on: external)],
                                 displays: [external, builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn), MenuBarGaps(left: 618, right: 758))
    }

    func testMenusRunningUnderThePillGiveANegativeGap() {
        let items = MenuBarItems(menus: [item(0, 1250, on: external)], statusItems: [], displays: [external])
        XCTAssertEqual(items.gaps(beside: externalPill, on: external).left, -45)
    }

    func testMenusPushedPastTheNotchCountOnTheRightSide() {
        let items = MenuBarItems(menus: [item(132, 900, on: builtIn), item(1280, 50, on: builtIn)],
                                 statusItems: [item(1500, 30, on: builtIn)],
                                 displays: [builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn), MenuBarGaps(left: 18, right: 10))
    }

    func testItemsOffEveryDisplayAreIgnored() {
        let items = MenuBarItems(menus: [], statusItems: [item(5000, 30, on: builtIn)], displays: [builtIn])
        XCTAssertEqual(items.gaps(beside: builtInNotch, on: builtIn).right, 2188 - 1270)
    }
}
