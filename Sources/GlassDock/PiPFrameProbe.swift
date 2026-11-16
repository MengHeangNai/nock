import CoreGraphics
import CoreVideo
import Foundation
import IOSurface

enum PiPFrameProbe {
    static let columns = 16
    static let rows = 9
    static let probeInterval: TimeInterval = 1
    static let sustainedProbes = 4
    static let blackLevel: UInt8 = 8
    static let note = "Part of this window looks black. Protected video (Netflix, Apple TV+, etc.) can't be copied by macOS."

    private static let minimumBlockCells = 18
    private static let maximumBlockPercent = 75
    private static let minimumLitPercent = 25
    private static let centralRange: ClosedRange<CGFloat> = 0.2...0.8
    private static let bytesPerPixel = 4

    /// Brightness (0...255, the brightest of red, green and blue) at the center of each cell of a 16 by 9 grid over the
    /// picture, row by row from the top, or nil when the surface is not readable 32-bit BGRA. Transparent pixels read as black.
    /// Locks the surface for reading, so call it off the main thread.
    static func samples(of surface: IOSurface) -> [UInt8]? {
        let width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface)
        guard width >= columns, height >= rows, IOSurfaceGetPixelFormat(surface) == kCVPixelFormatType_32BGRA,
              IOSurfaceLock(surface, .readOnly, nil) == kIOReturnSuccess else { return nil }
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(surface)
        let stride = IOSurfaceGetBytesPerRow(surface)
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let pixel = base.advanced(by: ((row * 2 + 1) * height / (rows * 2)) * stride
                                          + ((column * 2 + 1) * width / (columns * 2)) * bytesPerPixel)
                    .assumingMemoryBound(to: UInt8.self)
                return max(pixel[0], pixel[1], pixel[2])
            }
        }
    }

    /// Whether `samples` (16 by 9, from `samples(of:)`) show a large black block in the middle of a picture that is mostly
    /// lit, like a protected video player in a page. A window that is black as a whole (a dark app) never matches.
    static func looksLikeProtectedVideo(samples: [UInt8]) -> Bool {
        let cells = columns * rows
        guard samples.count == cells else { return false }
        let isBlack = samples.map { $0 <= blackLevel }
        guard let block = largestBlackBlock(isBlack) else { return false }
        let blockCells = block.width * block.height
        let litCells = isBlack.filter { !$0 }.count
        let centerX = (CGFloat(block.column) + CGFloat(block.width) / 2) / CGFloat(columns)
        let centerY = (CGFloat(block.row) + CGFloat(block.height) / 2) / CGFloat(rows)
        return blockCells >= minimumBlockCells && blockCells * 100 <= maximumBlockPercent * cells
            && litCells * 100 >= minimumLitPercent * cells
            && centralRange.contains(centerX) && centralRange.contains(centerY)
    }

    private static func largestBlackBlock(_ isBlack: [Bool]) -> (column: Int, row: Int, width: Int, height: Int)? {
        var best: (column: Int, row: Int, width: Int, height: Int)?
        for row in 0..<rows {
            for column in 0..<columns {
                var width = columns - column
                for height in 1...(rows - row) {
                    let run = (0..<width).prefix { isBlack[(row + height - 1) * columns + column + $0] }.count
                    width = min(width, run)
                    if width == 0 { break }
                    if width * height > (best.map { $0.width * $0.height } ?? 0) {
                        best = (column, row, width, height)
                    }
                }
            }
        }
        return best
    }
}
