import Foundation

/// One frame of metering inputs produced by the camera + luminance adapters.
///
/// This is the single seam between the hardware adapters and the pure
/// `MeterEngine`. It carries the *metadata authority* inputs (the camera's
/// native auto-exposure) separately from the *luminance diagnostics* (luma,
/// clipping, noise), so the two can be observed and tested independently.
/// Luminance never alters the EV — it only informs confidence (spec FR-2).
public struct MeterSample: Equatable, Sendable {
    /// The sample's capture time. This is the engine's notion of "now".
    public var timestamp: Date

    // MARK: Metadata authority (the camera's native auto-exposure)

    /// Live ISO sensitivity from camera metadata.
    public var metadataISO: Double?
    /// Live exposure duration, in seconds, from camera metadata.
    public var metadataExposureDuration: Double?
    /// Live lens aperture (f-number) for the active format.
    public var metadataAperture: Double?

    // MARK: Luminance diagnostics (normalized 0...1; confidence-only)

    /// Center-weighted normalized luma.
    public var centerLuma: Double?
    /// Spot-region normalized luma.
    public var spotLuma: Double?
    /// Fraction of the sampled region clipped at the highlight (0...1).
    public var clipping: Double
    /// Noise indicator for the sampled region (0...1).
    public var noise: Double

    public init(
        timestamp: Date,
        metadataISO: Double? = nil,
        metadataExposureDuration: Double? = nil,
        metadataAperture: Double? = nil,
        centerLuma: Double? = nil,
        spotLuma: Double? = nil,
        clipping: Double = 0,
        noise: Double = 0
    ) {
        self.timestamp = timestamp
        self.metadataISO = metadataISO
        self.metadataExposureDuration = metadataExposureDuration
        self.metadataAperture = metadataAperture
        self.centerLuma = centerLuma
        self.spotLuma = spotLuma
        self.clipping = clipping
        self.noise = noise
    }

    /// True when the sample carries a usable metadata exposure.
    public var hasMetadata: Bool {
        (metadataISO ?? 0) > 0 && (metadataExposureDuration ?? 0) > 0 && (metadataAperture ?? 0) > 0
    }

    /// The metadata-only EV100, or `nil` when the metadata is incomplete.
    ///
    /// This is the EV authority (spec FR-2):
    /// `EV100 = log2(aperture^2 / duration) - log2(ISO / 100)`.
    public var metadataEV100: Double? {
        guard let iso = metadataISO,
              let duration = metadataExposureDuration,
              let aperture = metadataAperture,
              iso > 0, duration > 0, aperture > 0
        else { return nil }
        return ExposureMath.ev100(iso: iso, aperture: aperture, shutterSeconds: duration)
    }
}
