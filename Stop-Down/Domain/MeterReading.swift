import Foundation

/// The reliability of the current reading.
///
/// Only `.stable` is high-confidence. Every other case still reports the
/// latest metadata EV — the level only gates the low-confidence banner and
/// never alters the EV value (spec §4.4).
public enum ConfidenceLevel: String, Equatable, Hashable, Sendable, CaseIterable, Codable {
    /// Three consistent metadata samples across the stability window.
    case stable
    /// The camera is still settling / not yet consistent.
    case stabilizing
    /// The scene is very dark or noisy.
    case dark
    /// Highlights are clipped (overexposed).
    case clipped
    /// No current valid data; the last valid reading is preserved.
    case stale
    /// No valid data has ever been produced (camera unavailable).
    case unavailable

    public var isLowConfidence: Bool {
        self != .stable
    }

    /// User-facing guidance for low-confidence conditions (spec §4.4). `nil`
    /// when the reading is stable.
    public var guidance: String? {
        switch self {
        case .stable:
            nil
        case .stabilizing:
            "Stabilizing reading…"
        case .dark:
            "Too dark for a reliable meter reading. Use a tripod or a longer exposure."
        case .clipped:
            "Highlights are clipped. Meter a darker mid-tone area."
        case .stale:
            "Reading is stale."
        case .unavailable:
            "Camera unavailable. Choose another lens or try again."
        }
    }
}

/// A single meter reading produced by `MeterEngine`.
///
/// `ev100` is the final reported EV. In v1 it always equals `metadataEV100`
/// (luminance is confidence-only and never alters EV), but both are kept
/// observable to avoid a misleading black-box number (spec FR-2).
public struct MeterReading: Equatable, Sendable {
    /// The final reported EV at ISO 100. `nil` when no valid reading exists.
    public let ev100: Double?
    /// When this reading was produced.
    public let timestamp: Date
    /// The active metering mode.
    public let mode: MeteringMode
    /// The active lens display name.
    public let lens: String
    /// The reliability of this reading.
    public let confidence: ConfidenceLevel
    /// A short human-readable explanation of the confidence (for DEBUG/tests).
    public let confidenceReason: String
    /// Filter/ND compensation in stops (>= 0). Carried for context; it does not
    /// alter the measured `ev100` (it is applied to the target by the solver).
    public let filterCompensationEV: Double

    // MARK: Source diagnostics

    /// EV computed straight from the camera's native metadata.
    public let metadataEV100: Double?
    /// The metadata ISO that produced the EV.
    public let sourceISO: Double?
    /// The metadata exposure duration, in seconds.
    public let sourceExposureDuration: Double?
    /// The metadata aperture (f-number).
    public let sourceAperture: Double?
    /// Center-weighted normalized luma at capture.
    public let centerLuma: Double?
    /// Spot-region normalized luma at capture.
    public let spotLuma: Double?
    /// Highlight-clipping indicator (0...1).
    public let clipping: Double
    /// Noise indicator (0...1).
    public let noise: Double

    public init(
        ev100: Double?,
        timestamp: Date,
        mode: MeteringMode,
        lens: String,
        confidence: ConfidenceLevel,
        confidenceReason: String,
        filterCompensationEV: Double,
        metadataEV100: Double? = nil,
        sourceISO: Double? = nil,
        sourceExposureDuration: Double? = nil,
        sourceAperture: Double? = nil,
        centerLuma: Double? = nil,
        spotLuma: Double? = nil,
        clipping: Double = 0,
        noise: Double = 0
    ) {
        self.ev100 = ev100
        self.timestamp = timestamp
        self.mode = mode
        self.lens = lens
        self.confidence = confidence
        self.confidenceReason = confidenceReason
        self.filterCompensationEV = filterCompensationEV
        self.metadataEV100 = metadataEV100
        self.sourceISO = sourceISO
        self.sourceExposureDuration = sourceExposureDuration
        self.sourceAperture = sourceAperture
        self.centerLuma = centerLuma
        self.spotLuma = spotLuma
        self.clipping = clipping
        self.noise = noise
    }
}
