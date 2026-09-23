import Foundation
import Observation

/// Drives the meter: owns the `MeterEngine` and a `MeteringSource`, applies the
/// user's configuration, keeps a live reading plus a frozen held reading, and
/// maintains the equivalent-exposure dial state for the UI.
///
/// The source emits samples on the main actor; the engine is driven here and the
/// resulting value-type `MeterReading` is what the UI observes. This keeps all
/// AVFoundation detail (a future source) behind the `MeteringSource` seam.
@MainActor
@Observable
public final class MeteringController {

    // MARK: Observables

    /// The engine's latest reading (updates while live).
    public private(set) var liveReading: MeterReading?
    /// The reading frozen when Hold is pressed.
    public private(set) var heldReading: MeterReading?
    /// Whether the meter is currently held.
    public private(set) var isHeld = false
    /// The equivalent-exposure dial state.
    public var exposure: ExposureState
    /// Whether the active feed is DEBUG test data (not a real camera).
    public let isTestFeed: Bool

    // MARK: Configuration

    public var mode: MeteringMode = .centerWeighted {
        didSet {
            if mode != oldValue {
                if mode == .spot, spotPoint == nil { spotPoint = NormalizedPoint(x: 0.5, y: 0.5) }
                pushConfig()
            }
        }
    }
    public var lens: String = "Back Wide" {
        didSet { pushConfig() }
    }
    public var spotPoint: NormalizedPoint?
    public var filterCompensationEV: Double = 0 {
        didSet {
            pushConfig()
            if let target = displayedReading?.ev100 {
                _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
            }
        }
    }
    public var increment: StopIncrement = .third {
        didSet {
            exposure.increment = increment
            if let target = displayedReading?.ev100 {
                _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
            }
        }
    }

    // MARK: Dependencies

    private let engine: MeterEngine
    private let source: MeteringSource

    // MARK: Init

    public init(source: MeteringSource) {
        self.source = source
        self.isTestFeed = source is TestMeterSource
        self.engine = MeterEngine()
        self.exposure = ExposureState()
        source.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
    }

    /// Convenience for the (DEBUG) default feed.
    public convenience init() {
        self.init(source: TestMeterSource())
    }

    // MARK: Derived

    /// The reading the UI shows: the frozen reading while held, else the live one.
    public var displayedReading: MeterReading? {
        isHeld ? heldReading : liveReading
    }

    // MARK: Lifecycle

    public func start() {
        engine.updateConfiguration(configuration())
        source.start()
        if let target = liveReading?.ev100 {
            _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
        }
    }

    public func stop() {
        source.stop()
    }

    // MARK: Reading

    private func handleSample(_ sample: MeterSample) {
        let reading = engine.process(sample)
        liveReading = reading
        // While held, do not auto-change the dial target (spec FR-4).
        guard !isHeld else { return }
        if let target = reading.ev100 {
            _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
        }
    }

    public func hold() {
        guard !isHeld, let live = liveReading else { return }
        heldReading = live
        isHeld = true
    }

    public func goLive() {
        isHeld = false
        heldReading = nil
    }

    public func toggleHold() {
        isHeld ? goLive() : hold()
    }

    // MARK: Exposure dials

    /// Turn a dial to `value`. Re-solves the solved axis for the current target EV.
    public func setDial(_ axis: ExposureAxis, to value: Double) {
        let target = displayedReading?.ev100 ?? 0
        _ = exposure.set(value, for: axis, targetEV100: target)
    }

    /// Lock a different axis. The previously locked axis becomes the pinned
    /// anchor (keeping its value); the new solved axis is recomputed.
    public func setLockedAxis(_ axis: ExposureAxis) {
        guard axis != exposure.lockedAxis else { return }
        exposure.anchorAxis = exposure.lockedAxis
        exposure.lockedAxis = axis
        if let target = displayedReading?.ev100 {
            _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
        }
    }

    #if DEBUG
    /// The test feed, when this controller is driven by `TestMeterSource`.
    public var testSource: TestMeterSource? { source as? TestMeterSource }
    public func setTestScenario(_ scenario: TestMeterSource.Scenario) {
        testSource?.scenario = scenario
    }
    public func stepTestSource() {
        testSource?.stepOnce()
    }
    #endif

    // MARK: Config

    private func configuration() -> MeterConfiguration {
        MeterConfiguration(
            mode: mode,
            lens: lens,
            spotPoint: mode == .spot ? spotPoint : nil,
            filterCompensationEV: filterCompensationEV
        )
    }

    private func pushConfig() {
        engine.updateConfiguration(configuration())
    }
}
