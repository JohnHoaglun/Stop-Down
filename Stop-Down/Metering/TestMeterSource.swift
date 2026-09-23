import Foundation

/// A DEBUG-only metering feed that emits known fixture samples at ~10 Hz.
///
/// It exists so the meter experience can be built, demoed, and tested on the
/// simulator or a device without depending on ambient light or camera permission
/// (spec 8.5). It is clearly "DEBUG TEST DATA", never a true reading.
@MainActor
public final class TestMeterSource: MeteringSource {

    /// The scenario the test feed currently emulates.
    public enum Scenario: String, CaseIterable, Identifiable {
        case stable
        case unstable
        case dark
        case clipped

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .stable: "Stable"
            case .unstable: "Unstable"
            case .dark: "Dark / noisy"
            case .clipped: "Clipped"
            }
        }
    }

    public var scenario: Scenario = .stable {
        didSet {
            if scenario != oldValue { tick = 0 }
        }
    }
    public var isAvailable: Bool { true }
    public var onSample: (@MainActor (MeterSample) -> Void)?
    public var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)?
    public private(set) var isRunning = false

    private var task: Task<Void, Never>?
    private var tick: Int = 0

    public init() {}

    public func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                self.emit()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Emit a single sample on demand (pause/step, spec 8.5).
    public func stepOnce() {
        emit()
    }

    // MARK: - Fixture generation

    private func emit() {
        tick += 1
        let sample: MeterSample
        switch scenario {
        case .stable:
            sample = Self.sample(forEV: 10.0, luma: 0.5, clipping: 0.0, noise: 0.05)
        case .unstable:
            // Drifts by up to ±0.4 EV so the engine never reaches "stable".
            let ev = 10.0 + Double((tick % 9) - 4) * 0.1
            sample = Self.sample(forEV: ev, luma: 0.5, clipping: 0.0, noise: 0.05)
        case .dark:
            sample = Self.sample(forEV: 6.0, luma: 0.03, clipping: 0.0, noise: 0.7)
        case .clipped:
            sample = Self.sample(forEV: 14.0, luma: 0.85, clipping: 0.25, noise: 0.05)
        }
        onSample?(sample)
    }

    /// A sample whose metadata resolves to exactly `ev` (ISO 100, f/5.6).
    /// `EV100 = log2(aperture^2 / duration)` at ISO 100, so
    /// `duration = aperture^2 / 2^ev`.
    private static func sample(forEV ev: Double, luma: Double, clipping: Double, noise: Double) -> MeterSample {
        let aperture = 5.6
        let duration = (aperture * aperture) / pow(2.0, ev)
        return MeterSample(
            timestamp: Date(),
            metadataISO: 100,
            metadataExposureDuration: duration,
            metadataAperture: aperture,
            centerLuma: luma,
            spotLuma: luma,
            clipping: clipping,
            noise: noise
        )
    }
}
