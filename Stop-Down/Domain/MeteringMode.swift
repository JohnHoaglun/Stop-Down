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

/// A point in a 0...1 unit square.
///
/// Metering contexts store these in the capture buffer's unit square (the
/// space `exposurePointOfInterest` and the luma spot box use); screen
/// coordinates are converted with `SpotPointConverter` (spec FR-3).
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
