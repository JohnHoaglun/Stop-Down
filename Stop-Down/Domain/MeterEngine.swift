import Foundation

/// The deterministic metering engine.
///
/// It accepts `MeterSample`s (produced by the camera + luminance adapters) and a
/// `MeterConfiguration`, and emits a `MeterReading`. The camera's native
/// metadata is the EV authority; luminance only informs confidence and never
/// alters the EV (spec FR-2).
///
/// All time is taken from the samples themselves, so the engine is fully
/// deterministic and testable with fixture sample sequences. In production it is
/// owned by the camera service and driven on its serial session queue; the UI
/// reads the resulting value-type reading on MainActor.
public final class MeterEngine {

    public private(set) var configuration: MeterConfiguration

    /// The most recent reading, or `nil` before any valid sample.
    public private(set) var currentReading: MeterReading?

    // Rolling window of recent metadata EV samples (newest last).
    private var recentSamples: [(ev: Double, timestamp: Date)] = []
    // Timestamp of the last *processed* (rate-capped) sample.
    private var lastProcessedTimestamp: Date?

    public init(configuration: MeterConfiguration = MeterConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Configuration

    /// Update the configuration. Changes to mode, lens, or spot point reset the
    /// smoothing window and force a re-stabilization (spec FR-3). Changing only
    /// filter compensation does not reset the window.
    public func updateConfiguration(_ newConfiguration: MeterConfiguration) {
        let contextChanged =
            newConfiguration.mode != configuration.mode ||
            newConfiguration.lens != configuration.lens ||
            newConfiguration.spotPoint != configuration.spotPoint
        configuration = newConfiguration
        if contextChanged {
            resetSmoothing()
        }
    }

    /// Drop all accumulated samples (used internally on context changes).
    ///
    /// Also clears the rate-cap clock so the first sample after a context change
    /// is always applied (not throttled against the previous context).
    public func resetSmoothing() {
        recentSamples.removeAll()
        lastProcessedTimestamp = nil
    }

    /// Clear all state, including the last reading. Used when the feed source
    /// is swapped so the new feed starts from a clean slate and its first
    /// sample is never throttled against, or answered with, the old feed's
    /// reading (spec 8.5).
    public func reset() {
        resetSmoothing()
        currentReading = nil
    }

    // MARK: - Processing

    /// Process one sample and return the resulting reading.
    @discardableResult
    public func process(_ sample: MeterSample) -> MeterReading {
        // Enforce the sample/update rate cap: a sample closer than one update
        // interval to the last processed sample is not applied (spec FR-8).
        if let last = lastProcessedTimestamp,
           sample.timestamp.timeIntervalSince(last) < configuration.minimumSampleInterval - 1e-9 {
            if let current = currentReading {
                return current
            }
            return MeterReading(
                ev100: nil,
                timestamp: sample.timestamp,
                mode: configuration.mode,
                lens: configuration.lens,
                confidence: .unavailable,
                confidenceReason: "No reading yet.",
                filterCompensationEV: configuration.filterCompensationEV,
                centerLuma: sample.centerLuma,
                spotLuma: sample.spotLuma,
                clipping: sample.clipping,
                noise: sample.noise
            )
        }

        guard let ev = sample.metadataEV100 else {
            return handleMissingMetadata(from: sample)
        }

        lastProcessedTimestamp = sample.timestamp
        appendToWindow(ev: ev, at: sample.timestamp)
        let (confidence, reason) = classify(sample: sample)
        let reading = MeterReading(
            ev100: ev,
            timestamp: sample.timestamp,
            mode: configuration.mode,
            lens: configuration.lens,
            confidence: confidence,
            confidenceReason: reason,
            filterCompensationEV: configuration.filterCompensationEV,
            metadataEV100: ev,
            sourceISO: sample.metadataISO,
            sourceExposureDuration: sample.metadataExposureDuration,
            sourceAperture: sample.metadataAperture,
            centerLuma: sample.centerLuma,
            spotLuma: sample.spotLuma,
            clipping: sample.clipping,
            noise: sample.noise
        )
        currentReading = reading
        return reading
    }

    /// A sample with no usable metadata: preserve the last valid reading and
    /// mark it stale, or report unavailable if none exists (spec §4.4).
    private func handleMissingMetadata(from sample: MeterSample) -> MeterReading {
        if let last = currentReading, last.ev100 != nil {
            let stale = MeterReading(
                ev100: last.ev100,
                timestamp: last.timestamp,
                mode: configuration.mode,
                lens: configuration.lens,
                confidence: .stale,
                confidenceReason: "No valid sample data; preserving last reading.",
                filterCompensationEV: configuration.filterCompensationEV,
                metadataEV100: last.metadataEV100,
                sourceISO: last.sourceISO,
                sourceExposureDuration: last.sourceExposureDuration,
                sourceAperture: last.sourceAperture,
                centerLuma: last.centerLuma,
                spotLuma: last.spotLuma,
                clipping: last.clipping,
                noise: last.noise
            )
            currentReading = stale
            return stale
        }

        let unavailable = MeterReading(
            ev100: nil,
            timestamp: sample.timestamp,
            mode: configuration.mode,
            lens: configuration.lens,
            confidence: .unavailable,
            confidenceReason: "No valid meter data yet.",
            filterCompensationEV: configuration.filterCompensationEV,
            centerLuma: sample.centerLuma,
            spotLuma: sample.spotLuma,
            clipping: sample.clipping,
            noise: sample.noise
        )
        currentReading = unavailable
        return unavailable
    }

    // MARK: - Confidence

    /// Classify the current reading. Luminance checks (clipped, dark) take
    /// precedence over stability for the banner, but never change the EV.
    private func classify(sample: MeterSample) -> (ConfidenceLevel, String) {
        if sample.clipping >= configuration.maxClipping {
            return (.clipped, "Highlights are clipped (clip \(String(format: "%.2f", sample.clipping))).")
        }

        let judgeLuma: Double?
        switch configuration.mode {
        case .spot:
            judgeLuma = sample.spotLuma ?? sample.centerLuma
        case .centerWeighted:
            judgeLuma = sample.centerLuma
        }
        if (judgeLuma ?? .infinity) < configuration.minJudgeLuma || sample.noise >= configuration.maxNoise {
            return (.dark, "Scene is dark or noisy.")
        }

        if recentSamples.count >= configuration.stableSampleCount,
           evSpread(of: recentSamples) <= configuration.stableToleranceEV {
            return (.stable, "Stable: \(recentSamples.count) samples within \(configuration.stableToleranceEV) EV.")
        }
        return (.stabilizing, "Stabilizing: collecting consistent samples.")
    }

    // MARK: - Smoothing window

    private func appendToWindow(ev: Double, at timestamp: Date) {
        recentSamples.append((ev: ev, timestamp: timestamp))
        pruneWindow(reference: timestamp)
    }

    private func pruneWindow(reference: Date) {
        let cutoff = reference.addingTimeInterval(-configuration.stableTimeWindow)
        recentSamples.removeAll { $0.timestamp < cutoff }
    }

    private func evSpread(of window: [(ev: Double, timestamp: Date)]) -> Double {
        guard let first = window.first else { return 0 }
        var lo = first.ev
        var hi = first.ev
        for s in window {
            lo = Swift.min(lo, s.ev)
            hi = Swift.max(hi, s.ev)
        }
        return hi - lo
    }
}
