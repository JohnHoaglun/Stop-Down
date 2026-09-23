import Foundation
import Testing
@testable import Stop_Down

@Suite("MeteringController source seam")
@MainActor
struct MeteringSourceSeamTests {

    /// Scriptable feed: records configuration, emits on demand, and can
    /// change its availability to drive the controller's recovery state.
    @MainActor
    private final class SeamFakeSource: MeteringSource {
        var onSample: (@MainActor (MeterSample) -> Void)?
        var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var applied: [MeterConfiguration] = []
        private var available: Bool
        /// Advances 150 ms per emit so samples clear the engine's 10 Hz rate cap.
        private var now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        init(isAvailable: Bool = true) {
            self.available = isAvailable
        }

        var isAvailable: Bool { available }

        func start() {
            startCount += 1
            onAvailability?(available, available ? nil : "Camera access is off in Settings.")
        }

        func stop() {
            stopCount += 1
        }

        func applyConfiguration(_ configuration: MeterConfiguration) {
            applied.append(configuration)
        }

        func emit(ev: Double) {
            now = now.addingTimeInterval(0.15)
            let aperture = 5.6
            let duration = (aperture * aperture) / pow(2.0, ev)
            onSample?(
                MeterSample(
                    timestamp: now,
                    metadataISO: 100,
                    metadataExposureDuration: duration,
                    metadataAperture: aperture,
                    centerLuma: 0.5,
                    spotLuma: 0.5
                )
            )
        }

        func setAvailability(_ value: Bool) {
            available = value
            onAvailability?(value, value ? nil : "Camera access is off in Settings.")
        }
    }

    @Test("start applies the current configuration to the source")
    func startAppliesConfig() {
        let source = SeamFakeSource()
        let controller = MeteringController(source: source)
        controller.start()
        #expect(source.startCount == 1)
        #expect(source.applied.count >= 1)
        #expect(source.applied.last?.mode == .centerWeighted)
        controller.stop()
    }

    @Test("Mode and spot changes reach the source")
    func configReachesSource() {
        let source = SeamFakeSource()
        let controller = MeteringController(source: source)
        controller.start()

        controller.mode = .spot
        #expect(source.applied.last?.mode == .spot)
        #expect(source.applied.last?.spotPoint == NormalizedPoint(x: 0.5, y: 0.5))

        controller.spotPoint = NormalizedPoint(x: 0.2, y: 0.8)
        #expect(source.applied.last?.spotPoint == NormalizedPoint(x: 0.2, y: 0.8))

        controller.mode = .centerWeighted
        #expect(source.applied.last?.mode == .centerWeighted)
        #expect(source.applied.last?.spotPoint == nil)
        controller.stop()
    }

    @Test("Replacing the source swaps the feed and clears state")
    func replaceSource() {
        let first = SeamFakeSource()
        let controller = MeteringController(source: first)
        controller.start()
        first.emit(ev: 10)
        #expect(controller.liveReading?.ev100 != nil)

        let second = SeamFakeSource()
        controller.replaceSource(second)
        #expect(first.stopCount == 1)
        #expect(second.startCount == 1)
        #expect(controller.liveReading == nil)
        #expect(controller.isHeld == false)
        #expect(second.applied.last?.mode == .centerWeighted)

        second.emit(ev: 8)
        #expect(abs((controller.liveReading?.ev100 ?? 100) - 8) < 0.5)
        controller.stop()
    }

    @Test("Availability changes surface on the controller")
    func availabilitySurfaced() {
        let source = SeamFakeSource(isAvailable: false)
        let controller = MeteringController(source: source)
        #expect(controller.isAvailable)
        controller.start()
        #expect(controller.isAvailable == false)
        #expect(controller.unavailableNote == "Camera access is off in Settings.")

        source.setAvailability(true)
        #expect(controller.isAvailable)
        #expect(controller.unavailableNote == nil)
        controller.stop()
    }

    #if DEBUG
    @Test("The DEBUG feed switch swaps the source")
    func debugFeedSwitch() {
        // Only the fixture-feed direction is exercised here: the camera
        // direction instantiates the real AVCaptureDevice (permission
        // request), which belongs to physical-device/UI verification.
        let source = SeamFakeSource()
        let controller = MeteringController(source: source)
        controller.start()
        #expect(controller.feed == .camera)

        controller.setFeed(.test)
        #expect(controller.isTestFeed)
        #expect(controller.feed == .test)
        #expect(source.stopCount == 1)
        #expect(controller.testSource?.isRunning == true)

        controller.setFeed(.test)
        #expect(controller.feed == .test)
        #expect(controller.testSource?.isRunning == true)

        controller.stop()
        #expect(controller.testSource?.isRunning == false)
    }
    #endif
}
