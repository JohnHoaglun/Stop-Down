import CoreGraphics
import Testing
import Stop_Down

/// Pure-math coverage for the Spot screen↔capture conversion (spec FR-3,
/// orientation). All cases use the back camera in portrait (`.right`).
@Suite("SpotPointConverter")
struct SpotPointConverterTests {

    /// 4:3 buffer (sensor orientation) and a portrait view that matches it
    /// exactly after rotation → no crop.
    private let buffer43 = CGSize(width: 1200, height: 900)
    private let view43 = CGSize(width: 900, height: 1200)
    /// 4:3 buffer in a 9:19.5 phone view → aspect-fill crops the sides.
    private let phoneView = CGSize(width: 390, height: 844)
    /// The real 1080p session buffer.
    private let buffer169 = CGSize(width: 1920, height: 1080)

    @Test("center maps to center for any sizes")
    func centerIsCenter() {
        let p = SpotPointConverter.bufferPoint(
            viewPoint: CGPoint(x: 0.5, y: 0.5),
            viewSize: phoneView,
            bufferSize: buffer43
        )
        #expect(abs(p.x - 0.5) < 1e-9)
        #expect(abs(p.y - 0.5) < 1e-9)
    }

    @Test("corners map to the rotated buffer corners without crop")
    func cornersNoCrop() {
        // 90° clockwise: buffer top-left displays at the view's top-right.
        let cases: [(CGPoint, NormalizedPoint)] = [
            (CGPoint(x: 0, y: 0), NormalizedPoint(x: 0, y: 1)),
            (CGPoint(x: 1, y: 0), NormalizedPoint(x: 0, y: 0)),
            (CGPoint(x: 0, y: 1), NormalizedPoint(x: 1, y: 1)),
            (CGPoint(x: 1, y: 1), NormalizedPoint(x: 1, y: 0))
        ]
        for (view, expected) in cases {
            let p = SpotPointConverter.bufferPoint(viewPoint: view, viewSize: view43, bufferSize: buffer43)
            #expect(abs(p.x - expected.x) < 1e-9, "x for \(view)")
            #expect(abs(p.y - expected.y) < 1e-9, "y for \(view)")
        }
    }

    @Test("a top-center tap on a cropped phone view meters the buffer's left edge")
    func topTapCropped() {
        // With side cropping, the view's top edge still spans the full
        // displayed buffer height: the tap lands at buffer (0, 0.5).
        let p = SpotPointConverter.bufferPoint(
            viewPoint: CGPoint(x: 0.5, y: 0),
            viewSize: phoneView,
            bufferSize: buffer169
        )
        #expect(abs(p.x - 0) < 1e-9)
        #expect(abs(p.y - 0.5) < 1e-9)
    }

    @Test("view and buffer points round-trip exactly")
    func roundTrip() {
        let points = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.1, y: 0.2),
            CGPoint(x: 0.9, y: 0.8),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0.25, y: 0.75)
        ]
        for view in points {
            let buffer = SpotPointConverter.bufferPoint(viewPoint: view, viewSize: phoneView, bufferSize: buffer169)
            let back = SpotPointConverter.viewPoint(
                bufferPoint: buffer,
                viewSize: phoneView,
                bufferSize: buffer169
            )
            #expect(abs(back.x / phoneView.width - view.x) < 1e-9, "x for \(view)")
            #expect(abs(back.y / phoneView.height - view.y) < 1e-9, "y for \(view)")
        }
    }

    @Test("out-of-bounds view points clamp into the buffer unit square")
    func clamps() {
        let p = SpotPointConverter.bufferPoint(
            viewPoint: CGPoint(x: -0.4, y: 1.4),
            viewSize: phoneView,
            bufferSize: buffer169
        )
        #expect(p.x >= 0 && p.x <= 1)
        #expect(p.y >= 0 && p.y <= 1)
    }

    @Test("degenerate sizes fall back to the center")
    func degenerate() {
        let p = SpotPointConverter.bufferPoint(
            viewPoint: CGPoint(x: 0.1, y: 0.2),
            viewSize: .zero,
            bufferSize: buffer169
        )
        #expect(abs(p.x - 0.5) < 1e-9)
        #expect(abs(p.y - 0.5) < 1e-9)
        let q = SpotPointConverter.viewPoint(
            bufferPoint: NormalizedPoint(x: 0.3, y: 0.6),
            viewSize: .zero,
            bufferSize: buffer169
        )
        #expect(q == .zero)
    }
}
