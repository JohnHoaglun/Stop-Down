import Foundation

/// The two metering modes the app offers.
public enum MeteringMode: String, Equatable, Hashable, Sendable, CaseIterable, Codable {
    case centerWeighted
    case spot

    public var displayName: String {
        switch self {
        case .centerWeighted: "Average"
        case .spot: "Spot"
        }
    }
}

/// A point normalized to the preview's 0...1 unit square.
///
/// Orientation-independent, so it can be preserved when the preview layout
/// changes (spec FR-3).
/// `nonisolated`: a pure value used by both the main actor and the frame
/// coordinator.
nonisolated public struct NormalizedPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Clamp to the valid 0...1 bounds (spec FR-3).
    public func clamped() -> NormalizedPoint {
        NormalizedPoint(
            x: Swift.min(1, Swift.max(0, x)),
            y: Swift.min(1, Swift.max(0, y))
        )
    }
}
