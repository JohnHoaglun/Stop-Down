import AVFoundation
import CoreGraphics
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
    /// Called on the main actor whenever `isAvailable` (or its explanation)
    /// changes, including the initial state after `start()`.
    var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)? { get set }
    /// Begin emitting samples (no-op if already running).
    func start()
    /// Stop emitting samples.
    func stop()
    /// Apply the metering context (mode, spot point) to the feed. The real
    /// camera uses this to position its exposure point of interest (spec FR-3);
    /// fixture feeds ignore it.
    ///
    /// A protocol requirement (with a default implementation below) so calls
    /// through the `MeteringSource` existential dispatch dynamically to each
    /// conforming source instead of the no-op default.
    func applyConfiguration(_ configuration: MeterConfiguration)
}

/// Sources that can render the live camera preview behind the meter UI
/// (spec §4.7). Fixture feeds do not conform, so the UI falls back to a
/// plain backdrop.
@MainActor
public protocol PreviewProviding: MeteringSource {
    /// The session the preview layer renders.
    var previewSession: AVCaptureSession { get }
    /// Nominal session buffer size (sensor orientation), used to convert
    /// screen points into capture space for the Spot reticle (spec FR-3).
    var previewBufferSize: CGSize { get }
}

/// Sources that expose the lenses the current device supplies (spec FR-1).
@MainActor
public protocol LensProviding: MeteringSource {
    /// Display names of the selectable lenses, in display order.
    var availableLensNames: [String] { get }
}

extension MeteringSource {
    /// A short user-facing explanation of why the feed is unavailable;
    /// `nil` when the feed is available.
    public var availabilityNote: String? { nil }

    /// Default: fixture feeds (test sources, fakes) ignore the metering context.
    public func applyConfiguration(_ configuration: MeterConfiguration) {}
}
