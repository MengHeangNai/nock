import XCTest
@testable import GlassDock

final class LyricsViewModeTests: XCTestCase {
    func testCyclingVisitsEveryModeThenWrapsAround() {
        XCTAssertEqual(LyricsViewMode.karaoke.next, .list)
        XCTAssertEqual(LyricsViewMode.list.next, .karaoke)
    }

    func testEveryModeSurvivesASaveAndLoad() {
        for mode in LyricsViewMode.allCases {
            XCTAssertEqual(LyricsViewMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertNil(LyricsViewMode(rawValue: "scroll"))
    }
}

final class KaraokeTimingTests: XCTestCase {
    private let lines = [
        LyricLine(id: 0, time: 10, text: "Hello world"),
        LyricLine(id: 1, time: 14, text: ""),
        LyricLine(id: 2, time: 20, text: "Goodbye"),
    ]

    func testWordsShareTheLineInProportionToTheirLength() {
        let words = KaraokeTiming.words(in: "aa bbbbbb", from: 0, to: 8)
        XCTAssertEqual(words.map(\.text), ["aa", "bbbbbb"])
        XCTAssertEqual(words[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(words[0].end, 2, accuracy: 0.0001)
        XCTAssertEqual(words[1].start, 2, accuracy: 0.0001)
        XCTAssertEqual(words[1].end, 8, accuracy: 0.0001)
    }

    func testWordsIgnoreExtraWhitespaceAndEmptyText() {
        XCTAssertEqual(KaraokeTiming.words(in: "  a \t b  ", from: 0, to: 2).map(\.text), ["a", "b"])
        XCTAssertTrue(KaraokeTiming.words(in: "   ", from: 0, to: 2).isEmpty)
        XCTAssertTrue(KaraokeTiming.words(in: "", from: 0, to: 2).isEmpty)
    }

    func testWordsKeepTheirOrderAndFillTheWholeSpan() {
        let words = KaraokeTiming.words(in: "one two three four", from: 5, to: 9)
        XCTAssertEqual(words.first?.start ?? 0, 5, accuracy: 0.0001)
        XCTAssertEqual(words.last?.end ?? 0, 9, accuracy: 0.0001)
        for (earlier, later) in zip(words, words.dropFirst()) {
            XCTAssertEqual(earlier.end, later.start, accuracy: 0.0001)
        }
    }

    func testWordProgressRisesFromZeroToOneAcrossTheWord() {
        let word = LyricWord(text: "la", start: 2, end: 4)
        XCTAssertEqual(word.progress(at: 1), 0)
        XCTAssertEqual(word.progress(at: 3), 0.5, accuracy: 0.0001)
        XCTAssertEqual(word.progress(at: 9), 1)
    }

    func testAWordWithNoLengthIsSungOnceItsStartPasses() {
        let word = LyricWord(text: "♪", start: 3, end: 3)
        XCTAssertEqual(word.progress(at: 2.9), 0)
        XCTAssertEqual(word.progress(at: 3), 1)
    }

    func testTheCurrentWordIsTheOneBeingFilled() {
        let words = KaraokeTiming.words(in: "aa bbbbbb", from: 0, to: 8)
        let progress = { (position: TimeInterval) in words.map { $0.progress(at: position) } }
        XCTAssertEqual(progress(1), [0.5, 0])
        XCTAssertEqual(progress(5), [1, 0.5])
        XCTAssertEqual(progress(8), [1, 1])
    }

    func testALineEndsAtTheNextLineWhenItIsShorterThanItsNaturalLength() {
        let line = LyricLine(id: 0, time: 10, text: String(repeating: "a", count: 40))
        let next = LyricLine(id: 1, time: 14, text: "b")
        XCTAssertEqual(KaraokeTiming.lineEnd(of: line, next: next, trackDuration: 200), 14, accuracy: 0.0001)
    }

    func testALineBeforeALongGapStopsAtItsNaturalLength() {
        let line = LyricLine(id: 0, time: 10, text: String(repeating: "a", count: 10))
        let next = LyricLine(id: 1, time: 40, text: "b")
        XCTAssertEqual(KaraokeTiming.lineEnd(of: line, next: next, trackDuration: 200), 13, accuracy: 0.0001)
    }

    func testAShortLineStillLastsAtLeastOneSecond() {
        let line = LyricLine(id: 0, time: 10, text: "oh")
        XCTAssertEqual(KaraokeTiming.lineEnd(of: line, next: nil, trackDuration: 0), 11, accuracy: 0.0001)
    }

    func testTheLastLineEndsWithTheTrack() {
        let line = LyricLine(id: 0, time: 10, text: String(repeating: "a", count: 40))
        XCTAssertEqual(KaraokeTiming.lineEnd(of: line, next: nil, trackDuration: 15), 15, accuracy: 0.0001)
    }

    func testAnEmptyLineIsShownAsANote() {
        let words = KaraokeTiming.words(of: lines, at: 1, trackDuration: 200)
        XCTAssertEqual(words.map(\.text), ["♪"])
    }

    func testTheWordsOfALineSpanItsStartToItsEnd() {
        let words = KaraokeTiming.words(of: lines, at: 0, trackDuration: 200)
        XCTAssertEqual(words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(words.first?.start ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(words.last?.end ?? 0, 13.3, accuracy: 0.0001)
    }
}

final class LyricLineLookupTests: XCTestCase {
    private let lines = [
        LyricLine(id: 0, time: 10, text: "a"),
        LyricLine(id: 1, time: 14, text: "b"),
        LyricLine(id: 2, time: 20, text: "c"),
    ]

    func testNoLineIsCurrentBeforeTheFirstOne() {
        XCTAssertNil(LyricsService.lineIndex(in: lines, at: 5))
    }

    func testTheLineStartsSlightlyEarlyToMatchTheHighlight() {
        XCTAssertNil(LyricsService.lineIndex(in: lines, at: 9.6))
        XCTAssertEqual(LyricsService.lineIndex(in: lines, at: 9.7), 0)
    }

    func testTheCurrentLineIsTheLastOneThatHasStarted() {
        XCTAssertEqual(LyricsService.lineIndex(in: lines, at: 12), 0)
        XCTAssertEqual(LyricsService.lineIndex(in: lines, at: 14), 1)
        XCTAssertEqual(LyricsService.lineIndex(in: lines, at: 500), 2)
    }

    func testNoLinesGiveNoCurrentLine() {
        XCTAssertNil(LyricsService.lineIndex(in: [], at: 10))
    }
}
