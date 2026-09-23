import Foundation

/// A concrete, display-ready exposure value on one axis.
///
/// The canonical values are the *conventional photographic* numbers a camera
/// dial actually shows (100/140/200 ISO, f/2.8, 1/125 s), not exact
/// factor-of-two steps. Stop offsets are always derived from these values via
/// `ExposureMath`, so the value is the source of truth and the stop is a
/// derived, approximately-quantized quantity.
public struct ExposureValue: Equatable, Hashable, Sendable {
    public let axis: ExposureAxis
    public let value: Double
    public let display: String

    public init(axis: ExposureAxis, value: Double, display: String? = nil) {
        self.axis = axis
        self.value = value
        self.display = display ?? ExposureValueTables.displayLabel(for: axis, value: value)
    }

    /// Stop offset of this value, derived from the exact value.
    public var stops: Double { ExposureMath.stops(of: axis, value: value) }
}

/// The canonical exposure value tables.
///
/// The third-stop series are the default and are fixed by the planning spec's
/// display fixtures. Full- and half-stop series are the standard photographic
/// dial values. All are stored as explicit conventional numbers; stop math is
/// derived from them, never the reverse.
public enum ExposureValueTables {

    // MARK: - Public access

    /// All values for `axis` at `increment`, ordered for the picker
    /// (ISO ascending, aperture ascending, shutter fastest→slowest).
    public static func series(axis: ExposureAxis, increment: StopIncrement) -> [ExposureValue] {
        tables[axis]?[increment] ?? []
    }

    /// Display labels for the picker, in picker order.
    public static func displayLabels(axis: ExposureAxis, increment: StopIncrement) -> [String] {
        series(axis: axis, increment: increment).map(\.display)
    }

    /// The value whose display label equals `label`, if any.
    public static func value(axis: ExposureAxis, increment: StopIncrement, display: String) -> ExposureValue? {
        series(axis: axis, increment: increment).first { $0.display == display }
    }

    /// The nearest value (in stop space) to `target` on `axis` at `increment`,
    /// with the stop-space delta. `nil` if the axis has no values.
    public static func nearest(axis: ExposureAxis, increment: StopIncrement, to target: Double) -> (value: ExposureValue, delta: Double)? {
        let series = self.series(axis: axis, increment: increment)
        guard let first = series.first else { return nil }
        let targetStops = ExposureMath.stops(of: axis, value: target)
        var best = first
        var bestDelta = abs(first.stops - targetStops)
        for candidate in series.dropFirst() {
            let delta = abs(candidate.stops - targetStops)
            if delta < bestDelta {
                best = candidate
                bestDelta = delta
            }
        }
        return (best, bestDelta)
    }

    // MARK: - Display formatting

    /// Conventional display label for an exact value on `axis`.
    public static func displayLabel(for axis: ExposureAxis, value: Double) -> String {
        switch axis {
        case .iso:
            return trimmedInt(value)
        case .aperture:
            return "f/\(trimmedNumber(value))"
        case .shutter:
            return shutterLabel(value)
        }
    }

    /// Shutter label: fractions for `value <= 1/3` (1/8000…1/3), decimal
    /// seconds otherwise (0.4, 0.5, …, 1, 2, 30).
    private static func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds <= 1.0 / 3.0 + 1e-9 {
            return "1/\(Int((1.0 / seconds).rounded()))"
        }
        return trimmedNumber(seconds)
    }

    private static func trimmedInt(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded)"
    }

    private static func trimmedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value.rounded()))"
        }
        var s = String(format: "%.3f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - Canonical series

    private static let tables: [ExposureAxis: [StopIncrement: [ExposureValue]]] = [
        .iso: makeTable(axis: .iso, values: isoValues),
        .aperture: makeTable(axis: .aperture, values: apertureValues),
        .shutter: makeTable(axis: .shutter, values: shutterValues),
    ]

    private static func makeTable(axis: ExposureAxis, values: [StopIncrement: [Double]]) -> [StopIncrement: [ExposureValue]] {
        values.mapValues { raw in
            raw.map { ExposureValue(axis: axis, value: $0) }
        }
    }

    private static let isoValues: [StopIncrement: [Double]] = [
        .full: [6, 12, 25, 50, 100, 200, 400, 800, 1600, 3200, 6400, 12800],
        .half: [6, 9, 12, 18, 25, 35, 50, 71, 100, 140, 200, 280, 400, 560, 800, 1120, 1600, 2240, 3200, 4500, 6400, 9000, 12800],
        .third: [6, 8, 10, 12, 16, 20, 25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800],
    ]

    private static let apertureValues: [StopIncrement: [Double]] = [
        .full: [1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0, 29.0, 40.0, 56.0],
        .half: [1.0, 1.1, 1.4, 1.6, 2.0, 2.5, 2.8, 3.5, 4.0, 5.0, 5.6, 7.1, 8.0, 10.0, 11.0, 13.0, 16.0, 20.0, 22.0, 25.0, 29.0, 32.0, 40.0, 45.0, 51.0, 56.0, 64.0],
        .third: [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8, 3.2, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14, 16, 18, 20, 22, 25, 29, 32, 36, 40, 45, 51, 57, 64],
    ]

    private static let shutterValues: [StopIncrement: [Double]] = [
        .full: shutterFractions([8000, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2]) + [1, 2, 4, 8, 15, 30],
        .half: shutterFractions([8000, 6400, 4000, 3200, 2000, 1600, 1000, 800, 500, 400, 250, 200, 125, 100, 60, 50, 30, 25, 15, 10, 8, 6, 4, 3, 2]) + [1, 1.3, 2, 2.5, 4, 6, 8, 10, 15, 25, 30],
        .third: shutterFractions([8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250, 200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3]) + [0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30],
    ]

    private static func shutterFractions(_ denominators: [Int]) -> [Double] {
        denominators.map { 1.0 / Double($0) }
    }
}
