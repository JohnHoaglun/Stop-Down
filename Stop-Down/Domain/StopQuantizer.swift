import Foundation

/// The result of quantizing a continuous stop offset to an allowed increment.
public struct QuantizedStop: Equatable, Sendable {
    /// The continuous input, in stops.
    public let input: Double
    /// The chosen allowed stop offset.
    public let quantized: Double
    /// `input - quantized`. Positive when the result rounds the input down.
    public let delta: Double

    /// True when the input was not already on an allowed stop.
    public var wasRounded: Bool {
        abs(delta) > 1e-9
    }
}

/// Quantizes continuous stop offsets to full/half/third-stop grids.
public enum StopQuantizer {

    /// Quantize `stops` to the nearest multiple of `increment.stepSize`.
    ///
    /// Tie-breaking: when the input falls exactly halfway between two allowed
    /// stops, the **lower** stop offset is chosen (per the approved spec:
    /// "consistently choose the lower exposure value and report the rounding
    /// delta"). This is round-half-down, i.e. ties round toward −∞.
    public static func quantize(_ stops: Double, to increment: StopIncrement) -> QuantizedStop {
        let step = increment.stepSize
        let scaled = stops / step
        // Round-half-down: ceil(scaled - 0.5).
        let index = (scaled - 0.5).rounded(.up)
        let quantized = index * step
        return QuantizedStop(input: stops, quantized: quantized, delta: stops - quantized)
    }
}
