import Foundation

/// The quantization granularity for exposure values.
///
/// A *stop* (EV) is a factor of two in exposure. Full stops step by 1 EV,
/// half stops by 0.5 EV, and third stops by 1/3 EV. Third stop is the v1
/// default.
public enum StopIncrement: Equatable, Hashable, Sendable, CaseIterable, Codable {
    case third
    case half
    case full

    /// The size of a single step, in EV (stops).
    public var stepSize: Double {
        switch self {
        case .third: 1.0 / 3.0
        case .half: 0.5
        case .full: 1.0
        }
    }

    public var displayName: String {
        switch self {
        case .third: "1/3 stop"
        case .half: "1/2 stop"
        case .full: "full stop"
        }
    }
}
