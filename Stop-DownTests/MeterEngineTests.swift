import Foundation
import Testing
@testable import Stop_Down

// MARK: - Fixtures

private extension Date {
    static func at(_ t: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: t) }
}

/// A valid metadata sample at time `t` (defaults give a clean, non-extreme scene).
private func sample(
    _ t: TimeInterval,
    iso: Double = 100,
    shutter: Double = 1.0 / 125.0,
    aperture: Double = 2.8,
    centerLuma: Double = 0.5,
    spotLuma: Double? = nil,
    clipping: Double = 0,
    noise: Double = 0
) -> MeterSample {
    MeterSample(
        timestamp: .at(t),
        metadataISO: iso,
        metadataExposureDuration: shutter,
        metadataAperture: aperture,
        centerLuma: centerLuma,
        spotLuma: spotLuma,
        clipping: clipping,
        noise: noise
    )
}

/// A sample with no usable metadata (camera gave nothing).
private func noData(_ t: TimeInterval) -> MeterSample {
    MeterSample(timestamp: .at(t))
}

private let ev125 = ExposureMath.ev100(iso: 100, aperture: 2.8, shutterSeconds: 1.0 / 125.0)

// MARK: - MeterSample

@Suite("MeterSample")
struct MeterSampleTests {

    @Test("metadata EV100 agrees with ExposureMath")
    func metadataEVAgrees() {
        let s = sample(0)
        #expect(abs((s.metadataEV100 ?? .infinity) - ev125) < 1e-9)
        #expect(s.hasMetadata)
    }

    @Test("incomplete metadata reports no EV")
    func incompleteMetadata() {
        #expect(!noData(0).hasMetadata)
        #expect(noData(0).metadataEV100 == nil)
        let bad = sample(0, shutter: 0)
        #expect(bad.metadataEV100 == nil)
    }
}

// MARK: - NormalizedPoint

@Suite("NormalizedPoint")
struct NormalizedPointTests {

    @Test("clamps to the 0...1 unit square")
    func clamps() {
        #expect(NormalizedPoint(x: -0.5, y: 2).clamped() == NormalizedPoint(x: 0, y: 1))
        #expect(NormalizedPoint(x: 0.5, y: 0.5).clamped() == NormalizedPoint(x: 0.5, y: 0.5))
    }
}

// MARK: - MeterEngine

@Suite("MeterEngine")
struct MeterEngineTests {

    @Test("metadata is the EV authority and luminance never alters it")
    func metadataIsAuthority() {
        let engine = MeterEngine()
        // Bright, noisy-ish but within thresholds; EV must equal the metadata EV.
        let reading = engine.process(sample(0, centerLuma: 0.9, noise: 0.4))
        #expect(abs((reading.ev100 ?? .infinity) - ev125) < 1e-9)
        #expect(abs((reading.metadataEV100 ?? .infinity) - ev125) < 1e-9)
        #expect(reading.ev100 == reading.metadataEV100)
    }

    @Test("three consistent samples across 300 ms become stable")
    func becomesStable() {
        let engine = MeterEngine()
        #expect(engine.process(sample(0)).confidence == .stabilizing)
        #expect(engine.process(sample(0.15)).confidence == .stabilizing)
        let reading = engine.process(sample(0.30))
        #expect(reading.confidence == .stable)
        #expect(reading.confidence.isLowConfidence == false)
        #expect(abs((reading.ev100 ?? .infinity) - ev125) < 1e-9)
    }

    @Test("inconsistent samples stay stabilizing")
    func staysStabilizingWhenUnstable() {
        let engine = MeterEngine()
        engine.process(sample(0, shutter: 1.0 / 125.0))
        engine.process(sample(0.15, shutter: 1.0 / 60.0))
        let reading = engine.process(sample(0.30, shutter: 1.0 / 30.0))
        #expect(reading.confidence == .stabilizing)
        #expect(reading.confidence.isLowConfidence)
    }

    @Test("a dark/noisy scene is low confidence (dark)")
    func darkScene() {
        let engine = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = engine.process(sample(t, centerLuma: 0.02))
        }
        let reading = engine.currentReading!
        #expect(reading.confidence == .dark)
        #expect(reading.confidence.isLowConfidence)
        #expect(reading.confidence.guidance?.isEmpty == false)
    }

    @Test("a bright noisy scene is NOT flagged dark (outdoor false positive)")
    func brightNoisyIsNotDark() {
        let engine = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = engine.process(sample(t, centerLuma: 0.9, noise: 0.9))
        }
        let reading = engine.currentReading!
        // Luma 0.9 is above the noise ceiling, so high noise must not count.
        #expect(reading.confidence == .stable)
        #expect(reading.confidence.isLowConfidence == false)
        #expect(abs((reading.ev100 ?? .infinity) - ev125) < 1e-9)
    }

    @Test("a dim noisy scene IS flagged dark")
    func dimNoisyIsDark() {
        let engine = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = engine.process(sample(t, centerLuma: 0.3, noise: 0.9))
        }
        let reading = engine.currentReading!
        // Luma 0.3 is above the dark-luma threshold but below the noise
        // ceiling, and noise 0.9 is at/over maxNoise → dark.
        #expect(reading.confidence == .dark)
        #expect(reading.confidence.isLowConfidence)
    }

    @Test("noise gating boundary: exactly at the luma ceiling or noise floor")
    func noiseGatingBoundary() {
        // Luma exactly at the ceiling (0.5): noise no longer counts → stable.
        let atCeiling = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = atCeiling.process(sample(t, centerLuma: 0.5, noise: 0.9))
        }
        #expect(atCeiling.currentReading!.confidence == .stable)

        // Noise exactly at maxNoise (0.5) in a dim scene → dark.
        let atNoiseFloor = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = atNoiseFloor.process(sample(t, centerLuma: 0.3, noise: 0.5))
        }
        #expect(atNoiseFloor.currentReading!.confidence == .dark)
    }

    @Test("a clipped scene is low confidence (clipped)")
    func clippedScene() {
        let engine = MeterEngine()
        for t in [0.0, 0.15, 0.30] {
            _ = engine.process(sample(t, clipping: 0.2))
        }
        let reading = engine.currentReading!
        #expect(reading.confidence == .clipped)
        #expect(reading.confidence.isLowConfidence)
    }

    @Test("clipping takes precedence over darkness")
    func clipPrecedence() {
        let engine = MeterEngine()
        let reading = engine.process(sample(0, centerLuma: 0.02, clipping: 0.2))
        #expect(reading.confidence == .clipped)
    }

    @Test("Spot mode judges darkness from the spot region")
    func spotUsesSpotLuma() {
        var config = MeterConfiguration()
        config.mode = .spot
        config.spotPoint = NormalizedPoint(x: 0.5, y: 0.5)
        let engine = MeterEngine(configuration: config)
        // Bright center, dark spot → Spot should read dark.
        let reading = engine.process(sample(0, centerLuma: 0.9, spotLuma: 0.02))
        #expect(reading.confidence == .dark)
    }

    @Test("a metadata-less sample after a valid one is stale and preserves the reading")
    func stalePreservesLastReading() {
        let engine = MeterEngine()
        _ = engine.process(sample(0))
        _ = engine.process(sample(0.15))
        let lastValid = engine.process(sample(0.30))
        #expect(lastValid.confidence == .stable)

        let stale = engine.process(noData(0.50))
        #expect(stale.confidence == .stale)
        #expect(abs((stale.ev100 ?? .infinity) - (lastValid.ev100 ?? .infinity)) < 1e-9)
        #expect(stale.timestamp == lastValid.timestamp)
    }

    @Test("a metadata-less sample with no prior reading is unavailable")
    func unavailableWhenNoData() {
        let engine = MeterEngine()
        let reading = engine.process(noData(0))
        #expect(reading.confidence == .unavailable)
        #expect(reading.ev100 == nil)
        #expect(reading.confidence.guidance?.isEmpty == false)
    }

    @Test("samples faster than the 10 Hz cap are not applied")
    func rateCap() {
        let engine = MeterEngine()
        let first = engine.process(sample(0, shutter: 1.0 / 125.0))
        // 50 ms later (within the 100 ms interval) → throttled; reading unchanged.
        let throttled = engine.process(sample(0.05, shutter: 1.0 / 60.0))
        #expect(throttled.ev100 == first.ev100)
        #expect(throttled.timestamp == first.timestamp)
        #expect(engine.currentReading?.timestamp == first.timestamp)
    }

    @Test("a mode, lens, or spot-point change resets smoothing to stabilizing")
    func contextChangeResets() {
        let engine = MeterEngine()
        _ = engine.process(sample(0))
        _ = engine.process(sample(0.15))
        _ = engine.process(sample(0.30))
        #expect(engine.currentReading?.confidence == .stable)

        var config = MeterConfiguration()
        config.lens = "Telephoto"
        engine.updateConfiguration(config)
        let after = engine.process(sample(0.45))
        #expect(after.confidence == .stabilizing)
    }

    @Test("changing only filter compensation does not reset smoothing")
    func compensationDoesNotReset() {
        var config = MeterConfiguration()
        config.stableTimeWindow = 1.0   // widen so all four samples stay in-window
        let engine = MeterEngine(configuration: config)
        _ = engine.process(sample(0))
        _ = engine.process(sample(0.15))
        _ = engine.process(sample(0.30))

        var updated = config
        updated.filterCompensationEV = 2
        engine.updateConfiguration(updated)
        let after = engine.process(sample(0.45))
        // Window retained: four consistent samples → stable.
        #expect(after.confidence == .stable)
        #expect(after.filterCompensationEV == 2)
        #expect(abs((after.ev100 ?? .infinity) - ev125) < 1e-9)
    }

    @Test("filter compensation is carried on the reading but does not change EV")
    func compensationCarriedNotApplied() {
        var config = MeterConfiguration()
        config.filterCompensationEV = 2
        let engine = MeterEngine(configuration: config)
        let reading = engine.process(sample(0))
        #expect(reading.filterCompensationEV == 2)
        #expect(abs((reading.ev100 ?? .infinity) - ev125) < 1e-9)
    }

    @Test("confidence guidance is nil only when stable")
    func guidanceMatchesConfidence() {
        for level in ConfidenceLevel.allCases {
            #expect((level.guidance == nil) == (level == .stable))
        }
    }
}
