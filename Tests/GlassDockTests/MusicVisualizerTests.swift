import CoreGraphics
import XCTest
@testable import GlassDock

final class VisualizerStyleTests: XCTestCase {
    func testCyclingVisitsEveryStyleThenWrapsAround() {
        XCTAssertEqual(VisualizerStyle.bars.next, .wave)
        XCTAssertEqual(VisualizerStyle.wave.next, .rings)
        XCTAssertEqual(VisualizerStyle.rings.next, .bars)
    }

    func testEveryStyleSurvivesASaveAndLoad() {
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(VisualizerStyle(rawValue: style.rawValue), style)
        }
        XCTAssertNil(VisualizerStyle(rawValue: "spectrum"))
    }
}

final class LevelHistoryTests: XCTestCase {
    func testItKeepsOnlyTheNewestFrames() {
        let history = LevelHistory()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for index in 0..<(LevelHistory.capacity + 10) {
            history.record([CGFloat(index)], at: start.addingTimeInterval(Double(index) * 0.05))
        }
        XCTAssertEqual(history.frames.count, LevelHistory.capacity)
        XCTAssertEqual(history.frames.first, [10])
        XCTAssertEqual(history.frames.last, [CGFloat(LevelHistory.capacity + 9)])
    }

    func testAFrameRecordedTooSoonAfterTheLastIsIgnored() {
        let history = LevelHistory()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        history.record([0.1], at: start)
        history.record([0.2], at: start.addingTimeInterval(0.001))
        history.record([0.3], at: start.addingTimeInterval(0.033))
        XCTAssertEqual(history.frames, [[0.1], [0.3]])
    }
}

final class VisualizerShapeTests: XCTestCase {
    func testSilenceGivesNoMovementInAnyStyle() {
        let silent = [[CGFloat]](repeating: [0, 0, 0, 0], count: 20)
        XCTAssertEqual(VisualizerShape.bars(from: silent, count: 8), [CGFloat](repeating: 0, count: 8))
        XCTAssertEqual(VisualizerShape.wave(from: silent, count: 8), [CGFloat](repeating: 0, count: 8))
        XCTAssertEqual(VisualizerShape.rings(from: silent, count: 4), [CGFloat](repeating: 0, count: 4))
    }

    func testAnEmptyHistoryGivesZeros() {
        XCTAssertEqual(VisualizerShape.bars(from: [], count: 3), [0, 0, 0])
        XCTAssertEqual(VisualizerShape.wave(from: [], count: 3), [0, 0, 0])
        XCTAssertEqual(VisualizerShape.rings(from: [], count: 3), [0, 0, 0])
        XCTAssertEqual(VisualizerShape.bars(from: [[1]], count: 0), [])
    }

    func testBarsFollowTheBandsFromLowToHighPitch() {
        let bassHeavy = [[CGFloat]](repeating: [1, 0, 0, 0], count: 8)
        let bars = VisualizerShape.bars(from: bassHeavy, count: 12)
        XCTAssertEqual(bars.count, 12)
        XCTAssertGreaterThan(bars.first ?? 0, 0.9)
        XCTAssertEqual(bars.last ?? 1, 0, accuracy: 0.001)
        XCTAssertTrue(bars.allSatisfy { (0...1).contains($0) })
    }

    func testBarsPickTheBandValuesAtTheirOwnPositions() {
        let steady = [[CGFloat]](repeating: [0, 1, 0, 1], count: 8)
        let bars = VisualizerShape.bars(from: steady, count: 4)
        XCTAssertEqual(bars[0], 0, accuracy: 0.001)
        XCTAssertEqual(bars[1], 1, accuracy: 0.001)
        XCTAssertEqual(bars[2], 0, accuracy: 0.001)
        XCTAssertEqual(bars[3], 1, accuracy: 0.001)
    }

    func testNeighbouringBarsReadDifferentMoments() {
        let rising = (0..<10).map { [CGFloat($0) / 10, CGFloat($0) / 10] }
        let bars = VisualizerShape.bars(from: rising, count: 3)
        XCTAssertEqual(bars[0], 0.9, accuracy: 0.001)
        XCTAssertEqual(bars[1], 0.4, accuracy: 0.001)
    }

    func testWaveEndsWithTheNewestLoudnessAndPadsWithSilence() {
        let history: [[CGFloat]] = [[0.5, 0.5], [1, 1]]
        let wave = VisualizerShape.wave(from: history, count: 4)
        XCTAssertEqual(wave.count, 4)
        XCTAssertEqual(wave[0], 0, accuracy: 0.001)
        XCTAssertEqual(wave[1], 0.1667, accuracy: 0.001)
        XCTAssertEqual(wave[2], 0.5, accuracy: 0.001)
        XCTAssertEqual(wave[3], 0.75, accuracy: 0.001)
    }

    func testRingsPassTheBeatOutwardOneStepAtATime() {
        var history = [[CGFloat]](repeating: [0, 0], count: 20)
        history[history.count - 1 - VisualizerShape.ringDelay] = [1, 1]
        XCTAssertEqual(VisualizerShape.rings(from: history, count: 3), [0, 1, 0])
    }

    func testOverallIsTheMeanOfTheBandsKeptInRange() {
        XCTAssertEqual(VisualizerShape.overall([0.2, 0.4]), 0.3, accuracy: 0.001)
        XCTAssertEqual(VisualizerShape.overall([3, 3]), 1)
        XCTAssertEqual(VisualizerShape.overall([]), 0)
    }

    func testTheFallbackFrameStaysWithinRangeAndMoves() {
        let first = VisualizerShape.idleFrame(at: 0, bandCount: 4)
        let later = VisualizerShape.idleFrame(at: 1.3, bandCount: 4)
        XCTAssertEqual(first.count, 4)
        XCTAssertNotEqual(first, later)
        XCTAssertTrue((first + later).allSatisfy { (0...1).contains($0) })
    }
}

final class VisualizerPaletteTests: XCTestCase {
    private func pixels(side: Int, color: (Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        (0..<(side * side)).flatMap { index -> [UInt8] in
            let (red, green, blue, alpha) = color(index)
            return [red, green, blue, alpha]
        }
    }

    func testAPlainRedImageGivesRed() {
        let palette = VisualizerPalette(pixels: pixels(side: 4) { _ in (200, 20, 20, 255) }, side: 4)
        XCTAssertEqual(palette.primary.hue, 0, accuracy: 0.02)
        XCTAssertGreaterThan(palette.primary.red, palette.primary.green)
        XCTAssertGreaterThan(palette.primary.brightness, 0.84)
        XCTAssertNotEqual(palette.primary, palette.secondary)
    }

    func testTwoColorImageGivesBothAsPrimaryAndSecondary() {
        let palette = VisualizerPalette(pixels: pixels(side: 4) { index in
            index < 10 ? (20, 40, 220, 255) : (230, 200, 20, 255)
        }, side: 4)
        XCTAssertEqual(palette.primary.hue, 230.0 / 360, accuracy: 0.03)
        XCTAssertEqual(palette.secondary.hue, 50.0 / 360, accuracy: 0.03)
    }

    func testGrayDarkAndTransparentImagesGiveTheNeutralPalette() {
        XCTAssertEqual(VisualizerPalette(pixels: pixels(side: 4) { _ in (128, 128, 128, 255) }, side: 4), .neutral)
        XCTAssertEqual(VisualizerPalette(pixels: pixels(side: 4) { _ in (10, 2, 2, 255) }, side: 4), .neutral)
        XCTAssertEqual(VisualizerPalette(pixels: pixels(side: 4) { _ in (255, 0, 0, 0) }, side: 4), .neutral)
        XCTAssertEqual(VisualizerPalette(pixels: [], side: 4), .neutral)
    }

    func testPremultipliedPixelsGiveTheSameColorAsOpaqueOnes() {
        let opaque = VisualizerPalette(pixels: pixels(side: 4) { _ in (0, 200, 0, 255) }, side: 4)
        let halfClear = VisualizerPalette(pixels: pixels(side: 4) { _ in (0, 100, 0, 128) }, side: 4)
        XCTAssertEqual(opaque.primary.hue, halfClear.primary.hue, accuracy: 0.01)
    }

    func testASyntheticImageIsDownscaledAndReadFromItsColors() throws {
        let width = 64
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        let image = try XCTUnwrap(context.makeImage())
        let palette = try XCTUnwrap(VisualizerPalette(image: image))
        XCTAssertEqual(palette.primary.hue, 130.0 / 360, accuracy: 0.06)
    }
}
