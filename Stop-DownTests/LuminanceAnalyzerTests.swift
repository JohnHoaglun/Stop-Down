import CoreVideo
import Foundation
import Testing
@testable import Stop_Down

@Suite("LuminanceAnalyzer")
struct LuminanceAnalyzerTests {

    /// A biplanar 4:2:0 frame whose Y plane is filled with `pattern(row, col)`.
    private func makeBuffer(
        width: Int = 64,
        height: Int = 48,
        pattern: (Int, Int) -> UInt8
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            nil,
            &buffer
        )
        #expect(status == kCVReturnSuccess)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
            .assumingMemoryBound(to: UInt8.self)
        let yRowsPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        for row in 0..<height {
            for col in 0..<width {
                yBase[row &* yRowsPerRow + col] = pattern(row, col)
            }
        }
        let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
        let uvRowsPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        memset(uvBase, 128, uvRowsPerRow &* (height / 2))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    @Test("Uniform mid-gray reads ~0.5 luma with no clipping and no noise")
    func uniformMidGray() {
        let buffer = makeBuffer { _, _ in 128 }
        let sample = LuminanceAnalyzer.analyze(buffer, mode: .centerWeighted, spotPoint: nil)
        #expect(sample.hasLuma)
        #expect(abs(sample.centerLuma - 128.0 / 255.0) < 0.01)
        #expect(sample.clipping == 0)
        #expect(sample.noise == 0)
        #expect(sample.spotLuma == nil)
    }

    @Test("Uniform near-black reads below the dark-judge threshold")
    func uniformDark() {
        let buffer = makeBuffer { _, _ in 8 }
        let sample = LuminanceAnalyzer.analyze(buffer, mode: .centerWeighted, spotPoint: nil)
        #expect(sample.centerLuma < 0.06)
    }

    @Test("Uniform white is fully clipped")
    func uniformWhite() {
        let buffer = makeBuffer { _, _ in 255 }
        let sample = LuminanceAnalyzer.analyze(buffer, mode: .centerWeighted, spotPoint: nil)
        #expect(sample.clipping == 1.0)
        #expect(abs(sample.centerLuma - 1.0) < 0.01)
    }

    @Test("Spot mode reports the region's luma; average mode does not")
    func spotRegion() {
        // Left half black, right half white.
        let buffer = makeBuffer { row, col in col < 32 ? 0 : 255 }

        let average = LuminanceAnalyzer.analyze(buffer, mode: .centerWeighted, spotPoint: nil)
        #expect(average.spotLuma == nil)
        #expect(abs(average.centerLuma - 0.5) < 0.15)

        let spotLeft = LuminanceAnalyzer.analyze(
            buffer, mode: .spot, spotPoint: NormalizedPoint(x: 0.25, y: 0.5)
        )
        // nil means "no samples in the spot box"; fail cleanly instead of
        // trapping the test host with a force-unwrap.
        #expect((spotLeft.spotLuma ?? 1) < 0.1)

        let spotRight = LuminanceAnalyzer.analyze(
            buffer, mode: .spot, spotPoint: NormalizedPoint(x: 0.75, y: 0.5)
        )
        #expect((spotRight.spotLuma ?? -1) > 0.9)
    }

    @Test("Out-of-bounds spot points clamp inside the frame")
    func clampedSpot() {
        let buffer = makeBuffer { _, _ in 200 }
        // Out of bounds on both axes; clamps to the top-left corner, whose
        // spot box contains the (0,0) grid sample. (The bottom/right corners
        // can be sample-free at the 8-px stride on this small frame, so use a
        // corner guaranteed to contain a sample.)
        let sample = LuminanceAnalyzer.analyze(
            buffer, mode: .spot, spotPoint: NormalizedPoint(x: -0.5, y: -0.5)
        )
        #expect(sample.hasLuma)
        #expect((sample.spotLuma ?? 0) > 0.5)
    }

    @Test("A high-frequency pattern reads as noisy; a flat frame does not")
    func noiseIndicator() {
        // Checkerboard (odd multipliers flip parity per pixel): adjacent
        // pixels always differ by 32 levels.
        let noisy = makeBuffer { row, col in
            (row &* 31 &+ col &* 17) % 2 == 0 ? 112 : 144
        }
        let flat = makeBuffer { _, _ in 128 }
        let noisySample = LuminanceAnalyzer.analyze(noisy, mode: .centerWeighted, spotPoint: nil)
        let flatSample = LuminanceAnalyzer.analyze(flat, mode: .centerWeighted, spotPoint: nil)
        #expect(noisySample.noise > 0.5)
        #expect(flatSample.noise == 0)
    }

    @Test("Non-biplanar frames report no luma instead of failing")
    func unsupportedFormat() {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            48,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        #expect(status == kCVReturnSuccess)
        let sample = LuminanceAnalyzer.analyze(buffer!, mode: .centerWeighted, spotPoint: nil)
        #expect(!sample.hasLuma)
    }
}
