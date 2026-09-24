import Foundation

/// Tunable inputs to `MeterEngine`.
///
/// Defaults follow the spec's performance and confidence rules (FR-8): a 10 Hz
/// sample/update cap and a reading marked stable after three consistent samples
/// across 300 ms within ±0.1 EV. Individual fields are overridable for tests.
public struct MeterConfiguration: Equatable, Sendable {
    // MARK: Context — changes to these reset the smoothing window (FR-3)

    public var mode: MeteringMode
    public var lens: String
    /// Normalized spot point in capture (buffer) space, as converted by
    /// `SpotPointConverter` from the tapped screen point; `nil` when not in
    /// Spot mode.
    public var spotPoint: NormalizedPoint?

    // MARK: Compensation — carried onto readings; does not reset the window

    /// Filter/ND compensation in stops (>= 0).
    public var filterCompensationEV: Double

    // MARK: Stability

    /// Minimum number of recent samples required to be stable.
    public var stableSampleCount: Int
    /// The rolling window (seconds) over which recent samples must be consistent.
    public var stableTimeWindow: TimeInterval
    /// Maximum EV spread among the recent window for the reading to be stable.
    public var stableToleranceEV: Double

    // MARK: Rate cap

    /// Upper bound on processed samples / visible updates per second.
    public var maxSamplesPerSecond: Double

    // MARK: Confidence thresholds (normalized 0...1)

    /// Below this center/spot luma the scene is judged "dark".
    public var minJudgeLuma: Double
    /// At or above this clipping fraction the reading is judged "clipped".
    public var maxClipping: Double
    /// At or above this noise level the reading is judged "dark" — but only
    /// when the judging luma is also below `noiseJudgeLumaCeiling`.
    public var maxNoise: Double
    /// The noise criterion applies only when the judging luma is below this
    /// level. Noise in a bright scene does not compromise the metadata EV
    /// (which stays authoritative), so it must not flag the scene as dark.
    public var noiseJudgeLumaCeiling: Double

    public init(
        mode: MeteringMode = .centerWeighted,
        lens: String = "Wide",
        spotPoint: NormalizedPoint? = nil,
        filterCompensationEV: Double = 0,
        stableSampleCount: Int = 3,
        stableTimeWindow: TimeInterval = 0.30,
        stableToleranceEV: Double = 0.1,
        maxSamplesPerSecond: Double = 10,
        minJudgeLuma: Double = 0.06,
        maxClipping: Double = 0.10,
        maxNoise: Double = 0.50,
        noiseJudgeLumaCeiling: Double = 0.50
    ) {
        self.mode = mode
        self.lens = lens
        self.spotPoint = spotPoint
        self.filterCompensationEV = filterCompensationEV
        self.stableSampleCount = stableSampleCount
        self.stableTimeWindow = stableTimeWindow
        self.stableToleranceEV = stableToleranceEV
        self.maxSamplesPerSecond = maxSamplesPerSecond
        self.minJudgeLuma = minJudgeLuma
        self.maxClipping = maxClipping
        self.maxNoise = maxNoise
        self.noiseJudgeLumaCeiling = noiseJudgeLumaCeiling
    }

    /// Minimum interval (seconds) between processed samples implied by the cap.
    var minimumSampleInterval: TimeInterval {
        maxSamplesPerSecond > 0 ? 1.0 / maxSamplesPerSecond : 0
    }
}
