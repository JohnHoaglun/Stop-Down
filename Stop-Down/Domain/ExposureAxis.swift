import Foundation

/// The three adjustable exposure parameters.
///
/// Ordering is fixed (ISO, aperture, shutter) so the solver can deterministically
/// pick "the remaining unlocked axis."
public enum ExposureAxis: String, Equatable, Hashable, Sendable, CaseIterable, Codable, Comparable {
    case iso
    case aperture
    case shutter

    public var displayName: String {
        switch self {
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutter: "Shutter"
        }
    }

    public static func < (lhs: ExposureAxis, rhs: ExposureAxis) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ axis: ExposureAxis) -> Int {
        switch axis {
        case .iso: 0
        case .aperture: 1
        case .shutter: 2
        }
    }

    /// The two axes other than `self`, in fixed order.
    public var others: [ExposureAxis] {
        ExposureAxis.allCases.filter { $0 != self }
    }
}
