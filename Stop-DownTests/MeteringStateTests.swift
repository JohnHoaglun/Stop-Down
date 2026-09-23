import Foundation
import Testing
@testable import Stop_Down

// MARK: - ExposureState

@Suite("ExposureState")
struct ExposureStateTests {

    /// Default: ISO 100 locked, aperture 5.6 anchored, shutter solved.
    private func state() -> ExposureState {
        ExposureState()
    }

    @Test("Solved axis is the third axis (default: shutter)")
    func solvedAxisDerivation() {
        let s = state()
        #expect(s.lockedAxis == .iso)
        #expect(s.anchorAxis == .aperture)
        #expect(s.solvedAxis == .shutter)
    }

    @Test("Turning a dial keeps the anchor and re-solves the third axis")
    func turningDialReSolves() {
        var s = state()
        s.set(11.0, for: .aperture, targetEV100: 10)
        #expect(s.anchorAxis == .aperture)
        #expect(abs(s.value(of: .aperture) - 11.0) < 1e-9)
        #expect(abs(s.value(of: .shutter) - 0.125) < 1e-9) // 1/8 s
        #expect(s.solvedAxis == .shutter)
    }

    @Test("Solved axis tracks locked and anchored axes")
    func lockMovesSolvedAxis() {
        var s = state()
        s.lockedAxis = .shutter
        s.anchorAxis = .iso
        #expect(s.solvedAxis == .aperture)
    }

    @Test("Resolve snaps the solved value to the table")
    func resolveSnapsToTable() {
        var s = state()
        s.resolve(targetEV100: 10, compensationStops: 0)
        // 10 - 4.97 (f/5.6) - 0 (ISO 100) ≈ 5.03 shutter stops → nearest 1/30.
        #expect(abs(s.value(of: .shutter) - 1.0 / 30.0) < 1e-9)
        #expect(s.lastSolve != nil)
        #expect(s.lastSolve?.inRange == true)
        #expect(s.display(for: .shutter) == "1/30")
        #expect(s.display(for: .aperture) == "f/5.6")
    }

    @Test("Filter compensation solves one stop slower")
    func compensationShiftsSolve() {
        var s = state()
        s.resolve(targetEV100: 10, compensationStops: 1)
        // 10 - 1 - 4.97 (f/5.6) ≈ 4.03 shutter stops → nearest 1/15.
        #expect(abs(s.value(of: .shutter) - 1.0 / 15.0) < 1e-9)
        #expect(s.lastSolve?.compensationStops == 1)
    }
}

// MARK: - MeteringController

@MainActor
@Suite("MeteringController")
struct MeteringControllerTests {

    /// Deterministic feed: emits fixture samples on demand.
    @MainActor
    private final class FakeSource: MeteringSource {
        var onSample: (@MainActor (MeterSample) -> Void)?
        var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var isAvailable: Bool { true }

        /// Advances 150 ms per emit so samples clear the engine's 10 Hz rate cap.
        private var now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        func start() { startCount += 1 }
        func stop() { stopCount += 1 }

        func emit(ev: Double, luma: Double = 0.5, clipping: Double = 0, noise: Double = 0.05) {
            now = now.addingTimeInterval(0.15)
            let aperture = 5.6
            let duration = (aperture * aperture) / pow(2.0, ev)
            onSample?(
                MeterSample(
                    timestamp: now,
                    metadataISO: 100,
                    metadataExposureDuration: duration,
                    metadataAperture: aperture,
                    centerLuma: luma,
                    spotLuma: luma,
                    clipping: clipping,
                    noise: noise
                )
            )
        }
    }

    @Test("No reading before the first sample")
    func noReadingInitially() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()
        #expect(controller.liveReading == nil)
        #expect(controller.displayedReading == nil)
        controller.stop()
    }

    @Test("Samples update the live reading and solve the dials")
    func sampleUpdatesReadingAndDials() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()
        #expect(source.startCount == 1)

        source.emit(ev: 10)
        #expect(abs((controller.liveReading?.ev100 ?? -1) - 10) < 1e-6)
        #expect(controller.exposure.solvedAxis == .shutter)
        #expect(abs(controller.exposure.value(of: .shutter) - 1.0 / 30.0) < 1e-9)

        controller.stop()
        #expect(source.stopCount == 1)
    }

    @Test("Hold freezes the reading and stops dial tracking")
    func holdFreezesReading() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        controller.hold()
        #expect(controller.isHeld)
        #expect(abs((controller.displayedReading?.ev100 ?? -1) - 10) < 1e-6)
        let shutterWhileHeld = controller.exposure.value(of: .shutter)

        source.emit(ev: 12)
        #expect(abs((controller.liveReading?.ev100 ?? -1) - 12) < 1e-6)
        #expect(abs((controller.displayedReading?.ev100 ?? -1) - 10) < 1e-6)
        #expect(controller.exposure.value(of: .shutter) == shutterWhileHeld)
    }

    @Test("Going live resumes tracking")
    func goLiveResumes() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        controller.hold()
        source.emit(ev: 12)
        controller.goLive()

        #expect(!controller.isHeld)
        #expect(abs((controller.displayedReading?.ev100 ?? -1) - 12) < 1e-6)
    }

    @Test("Locking a different axis moves the solved axis")
    func lockingMovesSolvedAxis() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        controller.setLockedAxis(.shutter)

        #expect(controller.exposure.lockedAxis == .shutter)
        #expect(controller.exposure.solvedAxis == .aperture)
        #expect(abs(controller.exposure.value(of: .aperture) - 5.6) < 1e-9)
    }

    @Test("Filter compensation re-solves the dials")
    func compensationReSolves() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        controller.filterCompensationEV = 1
        #expect(abs(controller.exposure.value(of: .shutter) - 1.0 / 15.0) < 1e-9)
    }

    @Test("Turning a dial while Live auto-enters Hold (spec §4.3)")
    func dialEditAutoHolds() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        #expect(!controller.isHeld)

        controller.setDial(.aperture, to: 8.0)
        #expect(controller.isHeld)
        // The edit is applied against the frozen reading, so the solve keeps
        // the EV-10 target: f/8 @ ISO 100 → 4 shutter stops → 1/15 s
        // (nearest 1/3-stop table value).
        #expect(abs((controller.displayedReading?.ev100 ?? -1) - 10) < 1e-6)
        #expect(abs(controller.exposure.value(of: .aperture) - 8.0) < 1e-9)
        #expect(abs(controller.exposure.value(of: .shutter) - 1.0 / 15.0) < 1e-9)
    }

    @Test("Turning a dial with no reading does not enter Hold")
    func dialEditWithoutReadingStaysLive() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        controller.setDial(.aperture, to: 8.0)
        #expect(!controller.isHeld)
    }

    @Test("Nearby combinations are empty before any reading")
    func combinationsEmptyWithoutReading() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()
        #expect(controller.nearbyCombinations.isEmpty)
    }

    @Test("Applying a nearby combination row sets the anchor and re-solves")
    func applyCombinationRow() {
        let source = FakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        source.emit(ev: 10)
        let rows = controller.nearbyCombinations
        #expect(!rows.isEmpty)
        let row = rows[0]

        controller.applyCombination(row)

        // The anchor dial takes the row's value and the third axis re-solves
        // for the same target EV; the edit auto-entered Hold.
        #expect(controller.isHeld)
        #expect(abs(controller.exposure.value(of: row.settings.aperture.axis) - row.settings.aperture.value) < 1e-9)
        #expect(abs(controller.exposure.value(of: row.settings.shutter.axis) - row.settings.shutter.value) < 1e-9)
        #expect(abs((controller.displayedReading?.ev100 ?? -1) - 10) < 1e-6)
    }

    #if DEBUG
    @Test("Default convenience init uses the real camera feed")
    func defaultFeedIsCamera() {
        // Constructing the source does not request permission; the feed is
        // never started here (camera behavior is device/UI-verified).
        let controller = MeteringController()
        #expect(controller.isTestFeed == false)
        #expect(controller.feed == .camera)
        #expect(controller.testSource == nil)
    }
    #endif
}
