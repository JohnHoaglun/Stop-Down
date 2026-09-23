import Foundation

/// A concrete trio of dial values.
public struct ExposureSettings: Equatable, Hashable, Sendable {
    public let iso: ExposureValue
    public let aperture: ExposureValue
    public let shutter: ExposureValue

    public init(iso: ExposureValue, aperture: ExposureValue, shutter: ExposureValue) {
        self.iso = iso
        self.aperture = aperture
        self.shutter = shutter
    }

    public subscript(axis: ExposureAxis) -> ExposureValue {
        switch axis {
        case .iso: iso
        case .aperture: aperture
        case .shutter: shutter
        }
    }

    /// EV100 of these exact values (the achieved exposure).
    public var ev100: Double {
        ExposureMath.ev100(iso: iso.value, aperture: aperture.value, shutterSeconds: shutter.value)
    }
}

/// The result of an equivalent-exposure solve.
public struct SolvedExposure: Equatable, Sendable {
    public let settings: ExposureSettings
    /// The raw meter EV the solve targets.
    public let targetEV100: Double
    /// Filter compensation applied in stops (>= 0).
    public let compensationStops: Double
    /// The axis that was solved for.
    public let solvedAxis: ExposureAxis
    /// The EV100 actually produced by the (snapped) settings.
    public let achievedEV100: Double
    /// Whether the solved value fell within the axis's supported range.
    public let inRange: Bool
}

public enum ExposureSolverError: Error, Equatable {
    /// Exactly one axis must be left `nil` (the axis to solve for).
    case badArity(provided: Int)
}

/// Pure equivalent-exposure solver.
///
/// Given a target EV100 and two of the three dial values, solve the third so the
/// trio reproduces the target (after filter compensation), snapping every value
/// to the canonical table at the requested increment. Stop math is delegated to
/// `ExposureMath`; value selection to `ExposureValueTables`.
public enum ExposureSolver {

    /// Solve the missing axis. Provide exactly two of `iso`, `aperture`,
    /// `shutter`; the `nil` one is solved for.
    public static func solve(
        targetEV100: Double,
        iso: Double?,
        aperture: Double?,
        shutter: Double?,
        compensationStops: Double = 0,
        increment: StopIncrement = .third
    ) throws -> SolvedExposure {
        let provided = [iso, aperture, shutter].compactMap { $0 }.count
        guard provided == 2 else {
            throw ExposureSolverError.badArity(provided: provided)
        }

        // Snap the known axes first so the solve is self-consistent with the
        // values actually returned.
        let isoValue = iso.map { snapped(axis: .iso, increment: increment, raw: $0) }
        let apertureValue = aperture.map { snapped(axis: .aperture, increment: increment, raw: $0) }
        let shutterValue = shutter.map { snapped(axis: .shutter, increment: increment, raw: $0) }

        let isoStops = isoValue.map { ExposureMath.stops(of: .iso, value: $0.value) }
        let apStops = apertureValue.map { ExposureMath.stops(of: .aperture, value: $0.value) }
        let shStops = shutterValue.map { ExposureMath.stops(of: .shutter, value: $0.value) }

        // An ND filter removes `compensationStops` of light, so the dial setting
        // must be that many stops "slower" (lower setting-EV) to compensate.
        let desired = targetEV100 - compensationStops

        let solvedAxis: ExposureAxis
        let solvedStops: Double
        if isoValue == nil {
            solvedAxis = .iso
            solvedStops = apStops! + shStops! - desired
        } else if apertureValue == nil {
            solvedAxis = .aperture
            solvedStops = desired - shStops! + isoStops!
        } else {
            solvedAxis = .shutter
            solvedStops = desired - apStops! + isoStops!
        }

        let solvedValue = snapped(
            axis: solvedAxis,
            increment: increment,
            raw: ExposureMath.value(of: solvedAxis, stops: solvedStops)
        )

        let settings = ExposureSettings(
            iso: isoValue ?? solvedValue,
            aperture: apertureValue ?? solvedValue,
            shutter: shutterValue ?? solvedValue
        )

        return SolvedExposure(
            settings: settings,
            targetEV100: targetEV100,
            compensationStops: compensationStops,
            solvedAxis: solvedAxis,
            achievedEV100: settings.ev100,
            inRange: inRange(axis: solvedAxis, increment: increment, stops: solvedStops)
        )
    }

    /// Snap a raw value on `axis` to the nearest canonical table value at
    /// `increment`, clamped to the supported range.
    private static func snapped(axis: ExposureAxis, increment: StopIncrement, raw: Double) -> ExposureValue {
        let clamped = clamped(axis: axis, increment: increment, value: raw)
        return ExposureValueTables
            .nearest(axis: axis, increment: increment, to: clamped)
            .map { $0.value }
            ?? ExposureValue(axis: axis, value: raw)
    }

    private static func clamped(axis: ExposureAxis, increment: StopIncrement, value: Double) -> Double {
        let series = ExposureValueTables.series(axis: axis, increment: increment)
        guard let lower = series.first?.value, let upper = series.last?.value else { return value }
        return Swift.min(Swift.max(lower, value), upper)
    }

    private static func inRange(axis: ExposureAxis, increment: StopIncrement, stops: Double) -> Bool {
        let series = ExposureValueTables.series(axis: axis, increment: increment)
        guard let first = series.first, let last = series.last else { return true }
        let a = ExposureMath.stops(of: axis, value: first.value)
        let b = ExposureMath.stops(of: axis, value: last.value)
        let (low, high) = a < b ? (a, b) : (b, a)
        return stops >= low && stops <= high
    }
}
