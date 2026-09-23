import Foundation

/// The seam between a metering feed (real camera or DEBUG test fixtures) and the
/// rest of the app.
///
/// A source emits `MeterSample`s — the single, well-defined hardware boundary
/// (spec Phase 2). The pure `MeterEngine` consumes them; the UI never talks to
/// AVFoundation directly. The real camera and the DEBUG `TestMeterSource` both
/// conform to this, so the meter experience can be built and tested without a
/// camera, and the feed can be swapped without touching the UI (spec 8.5).
@MainActor
public protocol MeteringSource: AnyObject {
    /// Whether this feed can produce readings (e.g. camera authorized/available).
    var isAvailable: Bool { get }
    /// Called on the main actor for each sample.
    var onSample: (@MainActor (MeterSample) -> Void)? { get set }
    /// Begin emitting samples (no-op if already running).
    func start()
    /// Stop emitting samples.
    func stop()
}
