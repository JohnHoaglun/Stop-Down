import CoreVideo
import Foundation

/// Low-cost luminance diagnostics for one camera frame (spec FR-1 #2).
///
/// Confidence-only: these values inform confidence judgments (dark/clipped)
/// and must never alter the metadata-derived EV (spec FR-2).
/// `nonisolated`: consumed off the main actor by the frame coordinator.
nonisolated struct LuminanceSample: Equatable, Sendable {
    /// False when the frame could not be read as a biplanar Y frame.
    var hasLuma: Bool
    /// Center-weighted normalized luma (0...1).
    var centerLuma: Double
    /// Spot-region normalized luma (0...1); nil in Average mode.
    var spotLuma: Double?
    /// Fraction of center-region samples clipped at the highlight (0...1).
    var clipping: Double
    /// High-frequency luma indicator (0...1).
    var noise: Double
}

/// One downsampled Y sample.
private struct LumaGridSample {
    var col: Int
    var row: Int
    var value: UInt8
}

/// A downsampled, hardware-free luma statistics pass over camera frames.
///
/// It reads only the Y plane of a biplanar 4:2:0 buffer and samples every
/// `sampleStride` pixels, so a full-resolution frame is never processed
/// whole (spec FR-1 #2: "sample low-cost luma values … without retaining full
/// frames"). It takes a `CVPixelBuffer` and returns a value type, so it is
/// unit-testable with synthetic frames.
/// `nonisolated`: pure computation, invoked from the frame coordinator's
/// analysis queue (never the main actor).
nonisolated enum LuminanceAnalyzer {

    /// Pixels skipped between samples in each direction.
    static let sampleStride = 8
    /// Luma at or above this (0...255) counts as clipped.
    static let clippingThreshold: UInt8 = 250
    /// Spot box edge as a fraction of the frame's shorter side.
    static let spotFraction = 0.12
    /// Half-size (fraction of width/height) of the center region used for
    /// clipping and noise statistics.
    static let judgeRegionHalf = 0.3
    /// Mean 1-pixel luma difference (in levels) considered heavy noise.
    static let heavyNoiseDiff: Double = 16

    static func analyze(
        _ buffer: CVPixelBuffer,
        mode: MeteringMode,
        spotPoint: NormalizedPoint?
    ) -> LuminanceSample {
        let empty = LuminanceSample(hasLuma: false, centerLuma: 0, spotLuma: nil, clipping: 0, noise: 0)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard
            let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self)
        else { return empty }
        // Non-planar formats (e.g. BGRA) still expose a plane-0 base address;
        // only biplanar (or more) Y planes are readable as luma here.
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return empty }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowsPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width >= 2, height >= 2, rowsPerRow > 0 else { return empty }

        func luma(_ row: Int, _ col: Int) -> UInt8 {
            yBase[row &* rowsPerRow + col]
        }

        // Downsampled grid of Y samples.
        var grid: [LumaGridSample] = []
        grid.reserveCapacity((width / sampleStride + 1) &* (height / sampleStride + 1))
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                grid.append(LumaGridSample(col: col, row: row, value: luma(row, col)))
                col += sampleStride
            }
            row += sampleStride
        }
        guard !grid.isEmpty else { return empty }

        var weightedSum = 0.0
        var weightTotal = 0.0
        var clippedCount = 0
        var judgeCount = 0
        var noiseSum = 0.0
        var noiseCount = 0

        for s in grid {
            let dx = (Double(s.col) + 0.5) / Double(width) - 0.5
            let dy = (Double(s.row) + 0.5) / Double(height) - 0.5
            let weight = max(0, 1 - abs(2 * dx)) * max(0, 1 - abs(2 * dy))
            weightedSum += Double(s.value) * weight
            weightTotal += weight

            if abs(dx) <= judgeRegionHalf, abs(dy) <= judgeRegionHalf {
                judgeCount += 1
                if s.value >= clippingThreshold { clippedCount += 1 }
            }

            if s.col + 1 < width {
                noiseSum += abs(Double(s.value) - Double(luma(s.row, s.col + 1)))
                noiseCount += 1
            }
        }

        let centerLuma = weightTotal > 0 ? (weightedSum / weightTotal) / 255 : 0
        let clipping = judgeCount > 0 ? Double(clippedCount) / Double(judgeCount) : 0
        let noise = noiseCount > 0 ? min(1, (noiseSum / Double(noiseCount)) / heavyNoiseDiff) : 0

        let spotLuma: Double?
        switch mode {
        case .centerWeighted:
            spotLuma = nil
        case .spot:
            let point = (spotPoint ?? NormalizedPoint(x: 0.5, y: 0.5)).clamped()
            spotLuma = Self.spotValue(grid: grid, spot: point, width: width, height: height)
        }

        return LuminanceSample(
            hasLuma: true,
            centerLuma: centerLuma,
            spotLuma: spotLuma,
            clipping: clipping,
            noise: noise
        )
    }

    /// Mean luma of grid samples inside a clamped box centered on `spot`.
    private static func spotValue(
        grid: [LumaGridSample],
        spot: NormalizedPoint,
        width: Int,
        height: Int
    ) -> Double? {
        let side = spotFraction * Double(min(width, height))
        let centerX = spot.x * Double(width)
        let centerY = spot.y * Double(height)
        let minC = max(0, centerX - side / 2)
        let maxC = min(Double(width), centerX + side / 2)
        let minR = max(0, centerY - side / 2)
        let maxR = min(Double(height), centerY + side / 2)

        var total = 0.0
        var count = 0
        for s in grid {
            let px = Double(s.col) + 0.5
            let py = Double(s.row) + 0.5
            if px >= minC, px < maxC, py >= minR, py < maxR {
                total += Double(s.value)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Double(count) / 255
    }
}
