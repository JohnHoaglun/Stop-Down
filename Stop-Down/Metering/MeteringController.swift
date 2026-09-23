import AVFoundation
import CoreGraphics
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
    public private(set) var isTestFeed: Bool
    /// Whether the active feed can produce readings right now.
    public private(set) var isAvailable = true
    /// Why the feed is unavailable, when applicable (drives the recovery UI).
    public private(set) var unavailableNote: String?

    // MARK: Configuration

    public var mode: MeteringMode = .centerWeighted {
        didSet {
            if mode != oldValue {
                if mode == .spot, spotPoint == nil { spotPoint = NormalizedPoint(x: 0.5, y: 0.5) }
                pushConfig()
            }
        }
    }
    /// Display name of the active lens (spec FR-1). Switching lenses pushes a
    /// new config, which resets the engine's smoothing window and reconfigures
    /// the camera session (spec FR-1).
    public var lens: String = "Wide" {
        didSet { pushConfig() }
    }
    public var spotPoint: NormalizedPoint? {
        didSet {
            if spotPoint != oldValue { pushConfig() }
        }
    }
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
    private var source: MeteringSource

    // MARK: Init

    public init(source: MeteringSource) {
        self.source = source
        self.isTestFeed = source is TestMeterSource
        self.engine = MeterEngine()
        self.exposure = ExposureState()
        wire(source)
    }

    /// Convenience for the product default feed (the real camera).
    public convenience init() {
        self.init(source: CameraMeteringSource())
    }

    private func wire(_ newSource: MeteringSource) {
        newSource.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        newSource.onAvailability = { [weak self] available, note in
            self?.isAvailable = available
            self?.unavailableNote = note
        }
    }

    // MARK: Derived

    /// The reading the UI shows: the frozen reading while held, else the live one.
    public var displayedReading: MeterReading? {
        isHeld ? heldReading : liveReading
    }

    /// The live camera session for the preview layer (spec §4.7); `nil` for
    /// fixture feeds, which show a plain backdrop instead.
    public var previewSession: AVCaptureSession? {
        (source as? PreviewProviding)?.previewSession
    }

    /// Nominal session buffer size (sensor orientation) for the Spot reticle
    /// screen→capture conversion (spec FR-3).
    public var previewBufferSize: CGSize {
        (source as? PreviewProviding)?.previewBufferSize
            ?? CGSize(width: 1920, height: 1080)
    }

    /// The lenses the current feed offers, in display order (spec FR-1);
    /// empty for fixture feeds.
    public var availableLensNames: [String] {
        (source as? LensProviding)?.availableLensNames ?? []
    }

    // MARK: Lifecycle

    public func start() {
        let config = configuration()
        engine.updateConfiguration(config)
        source.applyConfiguration(config)
        source.start()
        if let target = liveReading?.ev100 {
            _ = exposure.resolve(targetEV100: target, compensationStops: filterCompensationEV)
        }
    }

    public func stop() {
        source.stop()
    }

    /// Swap the active feed: stop the old source, clear readings, wire the new
    /// source, and start it with the current context (DEBUG feed switch and
    /// the test seam for source-level unit tests).
    public func replaceSource(_ newSource: MeteringSource) {
        let oldSource = source
        oldSource.stop()
        oldSource.onSample = nil
        oldSource.onAvailability = nil
        source = newSource
        isTestFeed = newSource is TestMeterSource
        liveReading = nil
        heldReading = nil
        isHeld = false
        wire(newSource)
        let config = configuration()
        engine.reset()
        engine.updateConfiguration(config)
        newSource.applyConfiguration(config)
        newSource.start()
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

    /// Nearby equivalent combinations for the displayed target EV (spec
    /// §4.3): the compact list shown below the wheels. Empty until a reading
    /// exists.
    public var nearbyCombinations: [EquivalentCombination] {
        guard let ev = displayedReading?.ev100 else { return [] }
        return EquivalentCombinationFinder.nearbyCombinations(
            state: exposure,
            targetEV100: ev,
            compensationStops: filterCompensationEV
        )
    }

    /// Apply a nearby combination row (spec §4.3): the anchor dial takes the
    /// row's anchor value and the engine re-solves the third axis for the
    /// same target EV.
    public func applyCombination(_ combination: EquivalentCombination) {
        setDial(exposure.anchorAxis, to: combination.settings[exposure.anchorAxis].value)
    }

    /// Turn a dial to `value`. Re-solves the solved axis for the current
    /// target EV. Turning a wheel while Live freezes the reading first so the
    /// edit is applied against a stable target (spec §4.3).
    public func setDial(_ axis: ExposureAxis, to value: Double) {
        if !isHeld, liveReading?.ev100 != nil {
            hold()
        }
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
        let config = configuration()
        engine.updateConfiguration(config)
        source.applyConfiguration(config)
    }

    #if DEBUG
    /// The DEBUG feed selection (spec 8.5): the real camera or the fixture feed.
    public enum Feed: String, CaseIterable, Identifiable, Sendable {
        case camera
        case test

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .camera: "Camera"
            case .test: "Test data"
            }
        }
    }

    /// The active feed (derived from the source).
    public var feed: Feed {
        source is TestMeterSource ? .test : .camera
    }

    /// Switch the active feed, swapping the source (DEBUG only).
    public func setFeed(_ newFeed: Feed) {
        guard newFeed != feed else { return }
        switch newFeed {
        case .camera: replaceSource(CameraMeteringSource())
        case .test: replaceSource(TestMeterSource())
        }
    }
    #endif
}
