import XCTest
@testable import GlassDock

final class NotificationQueueTests: XCTestCase {
    private func info(_ id: String) -> IslandNotification {
        IslandNotification(id: id, symbol: "bell", title: id)
    }

    private func warning(_ id: String, style: NotificationStyle = .warning) -> IslandNotification {
        IslandNotification(id: id, symbol: "bell", title: id, style: style)
    }

    func testTheFirstNotificationShowsRightAway() {
        var queue = NotificationQueue()
        queue.post(info("a"))
        XCTAssertEqual(queue.current?.id, "a")
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testNotificationsShowOneAfterAnotherInArrivalOrder() {
        var queue = NotificationQueue()
        ["a", "b", "c"].forEach { queue.post(info($0)) }
        XCTAssertEqual(queue.current?.id, "a")
        queue.finishCurrent()
        XCTAssertEqual(queue.current?.id, "b")
        queue.finishCurrent()
        XCTAssertEqual(queue.current?.id, "c")
        queue.finishCurrent()
        XCTAssertNil(queue.current)
    }

    func testAWaitingNotificationIsReplacedByTheSameIdAndMovesToTheBack() {
        var queue = NotificationQueue()
        ["a", "b", "c"].forEach { queue.post(info($0)) }
        var newer = info("b")
        newer.title = "b again"
        queue.post(newer)
        queue.post(info("d"))
        XCTAssertEqual(queue.pending.map(\.title), ["c", "b again", "d"])
    }

    func testPostingTheShowingIdUpdatesItAndRestartsItsTimer() {
        var queue = NotificationQueue()
        queue.post(info("wifi"))
        let revision = queue.revision
        var update = info("wifi")
        update.title = "Wi-Fi off"
        queue.post(update)
        XCTAssertEqual(queue.current?.title, "Wi-Fi off")
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertGreaterThan(queue.revision, revision)
    }

    func testOnlyAFewNotificationsWait() {
        var queue = NotificationQueue()
        (0..<10).forEach { queue.post(info("n\($0)")) }
        XCTAssertEqual(queue.pending.count, NotificationQueue.maxPending)
        XCTAssertEqual(queue.pending.map(\.id), ["n7", "n8", "n9"])
        XCTAssertEqual(queue.current?.id, "n0")
    }

    func testTheOldestInfoIsDroppedWhenTheQueueIsFull() {
        var queue = NotificationQueue()
        ["now", "a", "b", "c", "d"].forEach { queue.post(info($0)) }
        XCTAssertEqual(queue.pending.map(\.id), ["b", "c", "d"])
    }

    func testWarningsWaitAheadOfInfoButBehindEarlierWarnings() {
        var queue = NotificationQueue()
        queue.post(info("now"))
        queue.post(info("a"))
        queue.post(warning("w1"))
        queue.post(warning("w2"))
        XCTAssertEqual(queue.pending.map(\.id), ["w1", "w2", "a"])
    }

    func testCriticalOutranksWarning() {
        var queue = NotificationQueue()
        queue.post(info("now"))
        queue.post(warning("w"))
        queue.post(warning("c", style: .critical))
        XCTAssertEqual(queue.pending.map(\.id), ["c", "w"])
    }

    func testAFullQueueKeepsWarningsAndDropsInfo() {
        var queue = NotificationQueue()
        queue.post(info("now"))
        ["a", "b", "c"].forEach { queue.post(info($0)) }
        queue.post(warning("w"))
        XCTAssertEqual(queue.pending.map(\.id), ["w", "b", "c"])
    }

    func testAShowingNotificationIsNotInterruptedByAWarning() {
        var queue = NotificationQueue()
        queue.post(info("now"))
        queue.post(warning("w"))
        XCTAssertEqual(queue.current?.id, "now")
    }

    func testDurationsAreShortAndWarningsStayLonger() {
        XCTAssertEqual(info("a").duration, IslandNotification.infoSeconds)
        XCTAssertEqual(warning("a").duration, IslandNotification.warningSeconds)
        XCTAssertTrue((2.5...3.0).contains(IslandNotification.infoSeconds))
        XCTAssertGreaterThan(IslandNotification.warningSeconds, IslandNotification.infoSeconds)
    }

    func testTheHUDHidesTheShowingNotificationAndItReturnsAfterwards() {
        var queue = NotificationQueue()
        queue.post(info("a"))
        queue.setSuppressed(true)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.pending.map(\.id), ["a"])
        let revision = queue.revision
        queue.setSuppressed(false)
        XCTAssertEqual(queue.current?.id, "a")
        XCTAssertGreaterThan(queue.revision, revision)
    }

    func testNothingShowsWhileTheHUDIsUpEvenForWarnings() {
        var queue = NotificationQueue()
        queue.setSuppressed(true)
        queue.post(warning("w"))
        queue.post(info("a"))
        XCTAssertNil(queue.current)
        queue.setSuppressed(false)
        XCTAssertEqual(queue.current?.id, "w")
        XCTAssertEqual(queue.pending.map(\.id), ["a"])
    }

    func testTheHUDDoesNotLetAnInterruptedNotificationJumpTheQueue() {
        var queue = NotificationQueue()
        queue.post(warning("w"))
        queue.post(warning("w2"))
        queue.setSuppressed(true)
        XCTAssertEqual(queue.pending.map(\.id), ["w", "w2"])
    }

    func testFinishingWhileSuppressedShowsNothing() {
        var queue = NotificationQueue()
        queue.post(info("a"))
        queue.setSuppressed(true)
        queue.finishCurrent()
        XCTAssertNil(queue.current)
    }

    func testResetClearsEverything() {
        var queue = NotificationQueue()
        ["a", "b"].forEach { queue.post(info($0)) }
        queue.reset()
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.pending.isEmpty)
    }
}

final class BatteryAlertTrackerTests: XCTestCase {
    private func discharging(_ tracker: inout BatteryAlertTracker, _ levels: [Int]) -> [BatteryAlert] {
        levels.compactMap { tracker.observe(level: $0, isPluggedIn: false) }
    }

    func testTheStartingStateNeverAlerts() {
        var tracker = BatteryAlertTracker()
        XCTAssertNil(tracker.observe(level: 8, isPluggedIn: false))
        XCTAssertNil(tracker.observe(level: 8, isPluggedIn: false))
        var charging = BatteryAlertTracker()
        XCTAssertNil(charging.observe(level: 100, isPluggedIn: true))
    }

    func testEachThresholdAlertsOncePerDischarge() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 40, isPluggedIn: false)
        let alerts = discharging(&tracker, [30, 21, 20, 20, 19, 15, 11, 10, 10, 9, 5])
        XCTAssertEqual(alerts, [.low(threshold: 20, level: 20), .low(threshold: 10, level: 10)])
    }

    func testJumpingPastBothThresholdsAlertsOnlyForTheLowest() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 40, isPluggedIn: false)
        XCTAssertEqual(tracker.observe(level: 9, isPluggedIn: false), .low(threshold: 10, level: 9))
        XCTAssertNil(tracker.observe(level: 8, isPluggedIn: false))
    }

    func testAlertCarriesTheActualLevel() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 25, isPluggedIn: false)
        XCTAssertEqual(tracker.observe(level: 18, isPluggedIn: false), .low(threshold: 20, level: 18))
    }

    func testAlertsRearmAfterPluggingIn() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 25, isPluggedIn: false)
        XCTAssertNotNil(tracker.observe(level: 20, isPluggedIn: false))
        XCTAssertNil(tracker.observe(level: 20, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: 40, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: 30, isPluggedIn: false))
        XCTAssertEqual(tracker.observe(level: 20, isPluggedIn: false), .low(threshold: 20, level: 20))
    }

    func testUnpluggingAlreadyLowAlertsBecauseItIsARealChange() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 15, isPluggedIn: true)
        XCTAssertEqual(tracker.observe(level: 15, isPluggedIn: false), .low(threshold: 20, level: 15))
    }

    func testNoLowAlertWhilePluggedIn() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 30, isPluggedIn: true)
        XCTAssertNil(tracker.observe(level: 9, isPluggedIn: true))
    }

    func testFullyChargedAlertsOnceWhenChargingReachesTheTop() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 98, isPluggedIn: true)
        XCTAssertNil(tracker.observe(level: 99, isPluggedIn: true))
        XCTAssertEqual(tracker.observe(level: 100, isPluggedIn: true), .fullyCharged)
        XCTAssertNil(tracker.observe(level: 100, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: 99, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: 100, isPluggedIn: true))
    }

    func testFullyChargedAlertsAgainOnTheNextChargeCycle() {
        var tracker = BatteryAlertTracker()
        _ = tracker.observe(level: 99, isPluggedIn: true)
        XCTAssertEqual(tracker.observe(level: 100, isPluggedIn: true), .fullyCharged)
        _ = tracker.observe(level: 70, isPluggedIn: false)
        _ = tracker.observe(level: 90, isPluggedIn: true)
        XCTAssertEqual(tracker.observe(level: 100, isPluggedIn: true), .fullyCharged)
    }

    func testPluggingInAtFullAndStartingFullAreNotAlerts() {
        var tracker = BatteryAlertTracker()
        XCTAssertNil(tracker.observe(level: 100, isPluggedIn: true))
        _ = tracker.observe(level: 90, isPluggedIn: false)
        XCTAssertNil(tracker.observe(level: 100, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: 100, isPluggedIn: true))
    }

    func testAMacWithoutABatteryNeverAlerts() {
        var tracker = BatteryAlertTracker()
        XCTAssertNil(tracker.observe(level: nil, isPluggedIn: true))
        XCTAssertNil(tracker.observe(level: nil, isPluggedIn: false))
    }
}

final class WiFiTrackerTests: XCTestCase {
    func testTheStartingStateNeverNotifies() {
        var tracker = WiFiTracker()
        XCTAssertNil(tracker.observe(.connected))
        XCTAssertNil(tracker.observe(.connected))
    }

    func testEachChangeNotifiesOnce() {
        var tracker = WiFiTracker()
        _ = tracker.observe(.connected)
        XCTAssertEqual(tracker.observe(.disconnected)?.title, "Wi-Fi disconnected")
        XCTAssertNil(tracker.observe(.disconnected))
        XCTAssertEqual(tracker.observe(.connected)?.title, "Wi-Fi connected")
        XCTAssertEqual(tracker.observe(.off)?.title, "Wi-Fi off")
        XCTAssertNil(tracker.observe(.off))
    }

    func testTurningWiFiBackOnSaysSoUntilItJoinsANetwork() {
        var tracker = WiFiTracker()
        _ = tracker.observe(.off)
        XCTAssertEqual(tracker.observe(.disconnected)?.title, "Wi-Fi on")
        XCTAssertEqual(tracker.observe(.connected)?.title, "Wi-Fi connected")
    }

    func testAllWiFiNotificationsShareOneIdSoTheLatestStateWins() {
        XCTAssertEqual(Set([WiFiState.off, .disconnected, .connected].map { IslandNotification.wifi($0, from: .connected).id }), ["wifi"])
    }
}

final class BluetoothTests: XCTestCase {
    func testADeviceAlreadyConnectedIsNotReportedAsNew() {
        var tracker = BluetoothConnectionTracker()
        tracker.seed(["aa"])
        XCTAssertFalse(tracker.didConnect("aa"))
        XCTAssertTrue(tracker.didDisconnect("aa"))
    }

    func testConnectAndDisconnectAreReportedOnceEach() {
        var tracker = BluetoothConnectionTracker()
        XCTAssertTrue(tracker.didConnect("bb"))
        XCTAssertFalse(tracker.didConnect("bb"))
        XCTAssertTrue(tracker.didDisconnect("bb"))
        XCTAssertFalse(tracker.didDisconnect("bb"))
    }

    func testADeviceNeverSeenConnectedCannotDisconnect() {
        var tracker = BluetoothConnectionTracker()
        XCTAssertFalse(tracker.didDisconnect("cc"))
    }

    func testClassOfDeviceChoosesTheKind() {
        XCTAssertEqual(BluetoothDeviceKind(name: "WH-1000XM5", major: 4, minor: 6), .headphones)
        XCTAssertEqual(BluetoothDeviceKind(name: "Headset", major: 4, minor: 1), .headphones)
        XCTAssertEqual(BluetoothDeviceKind(name: "JBL Flip", major: 4, minor: 5), .speaker)
        XCTAssertEqual(BluetoothDeviceKind(name: "Magic Keyboard", major: 5, minor: 0x10), .keyboard)
        XCTAssertEqual(BluetoothDeviceKind(name: "Combo", major: 5, minor: 0x30), .keyboard)
        XCTAssertEqual(BluetoothDeviceKind(name: "MX Master", major: 5, minor: 0x20), .mouse)
        XCTAssertEqual(BluetoothDeviceKind(name: "Controller", major: 5, minor: 0x22), .gamepad)
        XCTAssertEqual(BluetoothDeviceKind(name: "Thing", major: 0, minor: 0), .generic)
    }

    func testNamesPickAirPodsAndTrackpads() {
        XCTAssertEqual(BluetoothDeviceKind(name: "Sam's AirPods Pro", major: 4, minor: 6), .airPodsPro)
        XCTAssertEqual(BluetoothDeviceKind(name: "AirPods Max", major: 4, minor: 6), .airPodsMax)
        XCTAssertEqual(BluetoothDeviceKind(name: "AirPods", major: 4, minor: 6), .airPods)
        XCTAssertEqual(BluetoothDeviceKind(name: "Magic Trackpad", major: 5, minor: 0x20), .trackpad)
    }

    func testDeviceNotificationsCarryTheNameAndStatePerDevice() {
        let connected = IslandNotification.bluetooth(address: "aa", name: "Keys", kind: .keyboard, isConnected: true)
        let disconnected = IslandNotification.bluetooth(address: "aa", name: "Keys", kind: .keyboard, isConnected: false)
        XCTAssertEqual(connected.title, "Keys")
        XCTAssertEqual(connected.subtitle, "Connected")
        XCTAssertEqual(disconnected.subtitle, "Disconnected")
        XCTAssertEqual(connected.id, disconnected.id)
        XCTAssertNotEqual(connected.id, IslandNotification.bluetooth(address: "bb", name: "Keys", kind: .keyboard, isConnected: true).id)
    }
}

final class BatteryNotificationTests: XCTestCase {
    func testLowBatteryStylesGetMoreUrgent() {
        XCTAssertEqual(IslandNotification.battery(.low(threshold: 20, level: 19)).style, .warning)
        XCTAssertEqual(IslandNotification.battery(.low(threshold: 10, level: 9)).style, .critical)
        XCTAssertEqual(IslandNotification.battery(.fullyCharged).style, .info)
    }

    func testLowBatteryShowsTheLevelAndSharesOneId() {
        let twenty = IslandNotification.battery(.low(threshold: 20, level: 19))
        let ten = IslandNotification.battery(.low(threshold: 10, level: 9))
        XCTAssertEqual(twenty.subtitle, "19% remaining")
        XCTAssertEqual(twenty.id, ten.id)
        XCTAssertEqual(twenty.announcement, "Low battery, 19% remaining")
    }
}
