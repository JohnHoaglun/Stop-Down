import Foundation

/// The meter's dial state: which axis is locked, which unlocked dial is the
/// user's pinned "anchor", and the three current dial values.
///
/// Exactly two axes are pinned (the locked axis and the anchor axis); the
/// remaining axis — the *solved* axis — is always recomputed so the trio
/// describes an equivalent exposure for the target EV (spec §4.3). This is pure
/// and deterministic: stop math is delegated to `ExposureSolver`.
public struct ExposureState: Equatable {
    /// The axis the user has locked (shown with a lock icon, accent-colored).
    public var lockedAxis: ExposureAxis
    /// The other pinned unlocked dial. The third axis is solved.
    public var anchorAxis: ExposureAxis
    /// The three current dial values (always snapped to the table).
    public var iso: Double
    public var aperture: Double
    public var shutter: Double
    /// Stop quantization for the wheels and solver.
    public var increment: StopIncrement
    /// The most recent solve result (for rounding / out-of-range notes). `nil`
    /// before the first solve.
    public private(set) var lastSolve: SolvedExposure?

    public init(
        lockedAxis: ExposureAxis = .iso,
        anchorAxis: ExposureAxis = .aperture,
        iso: Double = 100,
        aperture: Double = 5.6,
        shutter: Double = 1.0 / 125.0,
        increment: StopIncrement = .third
    ) {
        precondition(lockedAxis != anchorAxis, "locked and anchor axes must differ")
        self.lockedAxis = lockedAxis
        self.anchorAxis = anchorAxis
        self.iso = iso
        self.aperture = aperture
        self.shutter = shutter
        self.increment = increment
    }

    /// The axis that is solved for (neither locked nor anchored).
    public var solvedAxis: ExposureAxis {
        ExposureAxis.allCases.first { $0 != lockedAxis && $0 != anchorAxis } ?? .shutter
    }

    /// The display label for a dial's current value.
    public func display(for axis: ExposureAxis) -> String {
        ExposureValueTables.displayLabel(for: axis, value: value(of: axis))
    }

    public func value(of axis: ExposureAxis) -> Double {
        switch axis {
        case .iso: iso
        case .aperture: aperture
        case .shutter: shutter
        }
    }

    /// Change a dial's value as the user turns it (spec §4.3). The dragged axis
    /// becomes the pinned anchor (if it is not the locked axis), and the newly
    /// solved axis is recomputed for the given target EV.
    ///
    /// - Returns `true` if the newly solved value was rounded to a supported
    ///   value (so the UI can explain the rounding).
    @discardableResult
    public mutating func set(_ newValue: Double, for axis: ExposureAxis, targetEV100: Double) -> Bool {
        setPinned(axis, to: newValue)
        return resolve(targetEV100: targetEV100, compensationStops: 0)
    }

    /// Recompute the solved axis for a new target EV, keeping the pinned dials.
    @discardableResult
    public mutating func resolve(targetEV100: Double, compensationStops: Double) -> Bool {
        guard let solved = try? ExposureSolver.solve(
            targetEV100: targetEV100,
            iso: pinnedValue(for: .iso),
            aperture: pinnedValue(for: .aperture),
            shutter: pinnedValue(for: .shutter),
            compensationStops: compensationStops,
            increment: increment
        ) else {
            return false
        }
        lastSolve = solved
        apply(solved.settings)
        return !solved.inRange
    }

    // MARK: - Internals

    private func pinnedValue(for axis: ExposureAxis) -> Double? {
        (axis == lockedAxis || axis == anchorAxis) ? value(of: axis) : nil
    }

    private mutating func setPinned(_ axis: ExposureAxis, to value: Double) {
        switch axis {
        case .iso: iso = value
        case .aperture: aperture = value
        case .shutter: shutter = value
        }
        if axis != lockedAxis {
            anchorAxis = axis
        }
    }

    private mutating func apply(_ settings: ExposureSettings) {
        iso = settings.iso.value
        aperture = settings.aperture.value
        shutter = settings.shutter.value
    }
}
