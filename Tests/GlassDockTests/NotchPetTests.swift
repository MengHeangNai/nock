import XCTest
@testable import GlassDock

final class PetMoodTests: XCTestCase {
    private func mood(idle: TimeInterval = 0, music: Bool = false, battery: Int? = 80,
                      onBattery: Bool = false, celebrating: Bool = false) -> PetMood {
        PetMood.decide(idleSeconds: idle, isMusicPlaying: music, batteryLevel: battery,
                       isOnBattery: onBattery, isCelebrating: celebrating)
    }

    func testAnEverydayMacLeavesThePetIdle() {
        XCTAssertEqual(mood(), .idle)
    }

    func testThePetFallsAsleepAfterTwoMinutesWithoutInput() {
        XCTAssertEqual(mood(idle: 119), .idle)
        XCTAssertEqual(mood(idle: 120), .sleeping)
        XCTAssertEqual(mood(idle: 900), .sleeping)
    }

    func testMusicMakesThePetDanceEvenWhenYouAreAway() {
        XCTAssertEqual(mood(music: true), .dancing)
        XCTAssertEqual(mood(idle: 600, music: true), .dancing)
    }

    func testThePetGetsTiredOnlyOnALowBattery() {
        XCTAssertEqual(mood(battery: 20, onBattery: true), .tired)
        XCTAssertEqual(mood(battery: 5, onBattery: true), .tired)
        XCTAssertEqual(mood(battery: 21, onBattery: true), .idle)
        XCTAssertEqual(mood(battery: 10, onBattery: false), .idle)
    }

    func testAMacWithoutABatteryIsNeverTired() {
        XCTAssertEqual(mood(battery: nil, onBattery: true), .idle)
    }

    func testCelebratingWinsOverEveryOtherMood() {
        XCTAssertEqual(mood(idle: 600, music: true, battery: 5, onBattery: true, celebrating: true), .happy)
    }

    func testSleepingBeatsTiredWhenBothApply() {
        XCTAssertEqual(mood(idle: 300, battery: 10, onBattery: true), .sleeping)
    }
}

final class PetStageTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func stage(afterDays days: Int, hours: Int = 0) -> PetStage {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let now = first.addingTimeInterval(TimeInterval(days * 86_400 + hours * 3_600))
        return PetStage(firstLaunch: first, now: now, calendar: calendar)
    }

    func testANewPetIsABaby() {
        XCTAssertEqual(stage(afterDays: 0), .baby)
        XCTAssertEqual(stage(afterDays: 6), .baby)
    }

    func testThePetIsYoungFromTheSeventhDay() {
        XCTAssertEqual(stage(afterDays: 7), .young)
        XCTAssertEqual(stage(afterDays: 29), .young)
    }

    func testThePetIsGrownFromTheThirtiethDay() {
        XCTAssertEqual(stage(afterDays: 30), .grown)
        XCTAssertEqual(stage(afterDays: 400), .grown)
    }

    func testAClockSetBeforeTheFirstLaunchKeepsABaby() {
        XCTAssertEqual(stage(afterDays: -3), .baby)
    }

    func testDaysCountCalendarDaysNotTwentyFourHourBlocks() {
        let calendar = calendar
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 30))!
        let sevenDaysLater = calendar.date(from: DateComponents(year: 2026, month: 1, day: 8, hour: 0, minute: 10))!
        XCTAssertEqual(PetStage(firstLaunch: first, now: sevenDaysLater, calendar: calendar), .young)
    }
}
