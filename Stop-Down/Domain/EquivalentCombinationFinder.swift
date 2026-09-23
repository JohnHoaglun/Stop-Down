import Foundation

/// A nearby equivalent-exposure combination (spec §4.3): the locked axis keeps
/// its value, the anchor axis is stepped by `anchorStepOffset` table positions,
/// and the third axis is solved so the trio reproduces the same target EV.
public struct EquivalentCombination: Equatable, Sendable, Identifiable {
    public let settings: ExposureSettings
    /// Table positions the anchor axis moved from the current dial value
    /// (signed; positive is toward the higher index in the axis's table).
    public let anchorStepOffset: Int

    public init(settings: ExposureSettings, anchorStepOffset: Int) {
        self.settings = settings
        self.anchorStepOffset = anchorStepOffset
    }

    public var id: String {
        "\(settings.iso.value)|\(settings.aperture.value)|\(settings.shutter.value)"
    }
}

/// Pure enumerator of the nearby equivalent combinations shown below the
/// exposure wheels (spec §4.3).
///
/// The locked axis is the user's commitment and never changes; the rows walk
/// the one-dimensional trade-off between the anchor axis and the solved axis
/// at the same target EV. Stop math and snapping are delegated to
/// `ExposureSolver`, so every row is self-consistent with the dials.
public enum EquivalentCombinationFinder {

    /// Enumerate nearby equivalent combinations around `state`.
    ///
    /// The anchor axis is stepped by every table offset within ±1 full stop
    /// (at the state's stop increment), both directions; each step re-solves
    /// the third axis for `targetEV100` after `compensationStops` of filter
    /// compensation. Rows whose solved value falls outside the supported
    /// generic range are dropped, as is the current combination itself.
    ///
    /// - Returns rows sorted nearest-first, capped at `limit`.
    public static func nearbyCombinations(
        state: ExposureState,
        targetEV100: Double,
        compensationStops: Double = 0,
        limit: Int = 5
    ) -> [EquivalentCombination] {
        let series = ExposureValueTables.series(axis: state.anchorAxis, increment: state.increment)
        let anchorValue = state.value(of: state.anchorAxis)
        guard let currentIndex = series.firstIndex(where: { abs($0.value - anchorValue) < 1e-6 }) else {
            return []
        }

        // ±1 full stop of anchor travel, expressed in table positions.
        let maxOffset = Swift.max(1, Int((1.0 / state.increment.stepSize).rounded()))
        var candidates: [(offset: Int, value: Double)] = []
        for sign in [-1, 1] {
            var offset = sign
            while Swift.abs(offset) <= maxOffset {
                let index = currentIndex + offset
                if series.indices.contains(index) {
                    candidates.append((offset: offset, value: series[index].value))
                }
                offset += sign
            }
        }

        var results: [EquivalentCombination] = []
        var seen = Set<String>()
        for candidate in candidates.sorted(by: { Swift.abs($0.offset) < Swift.abs($1.offset) }) {
            guard results.count < limit else { break }
            func pinned(_ axis: ExposureAxis) -> Double? {
                if axis == state.lockedAxis { return state.value(of: axis) }
                if axis == state.anchorAxis { return candidate.value }
                return nil
            }
            guard let solved = try? ExposureSolver.solve(
                targetEV100: targetEV100,
                iso: pinned(.iso),
                aperture: pinned(.aperture),
                shutter: pinned(.shutter),
                compensationStops: compensationStops,
                increment: state.increment
            ), solved.inRange else { continue }
            guard seen.insert(solved.settings.id).inserted else { continue }
            results.append(EquivalentCombination(settings: solved.settings, anchorStepOffset: candidate.offset))
        }
        return results
    }

    /// A stable key for a settings trio.
    public static func id(of settings: ExposureSettings) -> String {
        "\(settings.iso.value)|\(settings.aperture.value)|\(settings.shutter.value)"
    }
}

private extension ExposureSettings {
    var id: String { EquivalentCombinationFinder.id(of: self) }
}
