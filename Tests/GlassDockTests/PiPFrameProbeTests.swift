import IOSurface
import XCTest
@testable import GlassDock

final class PiPFrameProbeTests: XCTestCase {
    private let columns = PiPFrameProbe.columns
    private let rows = PiPFrameProbe.rows

    private func grid(lit: UInt8 = 200, black columnRange: Range<Int>, rows rowRange: Range<Int>) -> [UInt8] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in columnRange.contains(column) && rowRange.contains(row) ? 0 : lit }
        }
    }

    func testABlackBlockInTheMiddleOfALitPageLooksLikeProtectedVideo() {
        XCTAssertTrue(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 2..<11, rows: 1..<6)))
    }

    func testAFullWidthBlackPlayerBelowTheTopLooksLikeProtectedVideo() {
        XCTAssertTrue(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 0..<16, rows: 1..<7)))
    }

    func testAWindowBlackAsAWholeNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 0..<16, rows: 0..<9)))
    }

    func testAPictureWithNoBlackNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 0..<0, rows: 0..<0)))
    }

    func testASmallBlackBlockNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 6..<9, rows: 3..<5)))
    }

    func testABlackBlockAtTheEdgeNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 0..<4, rows: 0..<9)))
    }

    func testAMostlyBlackPictureWithAThinLitStripNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: grid(black: 0..<16, rows: 0..<8)))
    }

    func testDarkGrayIsNotBlack() {
        let gray = [UInt8](repeating: PiPFrameProbe.blackLevel + 1, count: columns * rows)
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: gray))
    }

    func testAnUnexpectedSampleCountNeverMatches() {
        XCTAssertFalse(PiPFrameProbe.looksLikeProtectedVideo(samples: [0, 255, 0]))
    }

    private func surface(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) -> IOSurface? {
        let surface = IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4,
                                             .pixelFormat: kCVPixelFormatType_32BGRA])
        guard let surface else { return nil }
        surface.lock(options: [], seed: nil)
        let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let bytes = pixel(x, y)
                for (index, byte) in bytes.enumerated() { base[y * surface.bytesPerRow + x * 4 + index] = byte }
            }
        }
        surface.unlock(options: [], seed: nil)
        return surface
    }

    func testSamplesReadTheCenterOfEachCellOfABGRAFrame() throws {
        let frame = try XCTUnwrap(surface(width: 320, height: 180) { x, _ in x < 160 ? [0, 0, 0, 0] : [10, 200, 30, 255] })
        let samples = try XCTUnwrap(PiPFrameProbe.samples(of: frame))
        XCTAssertEqual(samples.count, columns * rows)
        XCTAssertEqual(samples[0], 0)
        XCTAssertEqual(samples[columns - 1], 200)
        XCTAssertEqual(samples[columns * rows - 1], 200)
    }

    func testSamplesAreNilForAnUnreadableSurface() throws {
        let tiny = try XCTUnwrap(surface(width: 4, height: 4) { _, _ in [0, 0, 0, 0] })
        XCTAssertNil(PiPFrameProbe.samples(of: tiny))
    }
}
