import Foundation

/// Pure, deterministic exposure stop-math.
///
/// Everything is expressed in *stop offsets* (EV), a factor-of-two unit, so
/// exposure equivalence becomes linear:
///
///     EV100 = apertureStops + shutterStops - isoStops
///
/// Aperture stops follow the photographic convention `log2(N^2)`, so
/// f/1.0 = 0, f/1.4 = 1, f/2.0 = 2, f/2.8 = 3 (each full stop halves light).
///
/// This type has no dependency on AVFoundation or SwiftUI — it is the
/// single source of truth for the math, the solver, and the tests.
/// `nonisolated`: pure math, callable from any executor.
nonisolated public enum ExposureMath {

    // MARK: - Stop offsets

    /// ISO stop offset from ISO 100. ISO 100 → 0, ISO 200 → +1, ISO 50 → −1.
    public static func isoStops(_ iso: Double) -> Double {
        log2(iso / 100)
    }

    /// ISO value for a stop offset from ISO 100.
    public static func isoValue(stops: Double) -> Double {
        100 * pow(2, stops)
    }

    /// Aperture stop offset from f/1.0, using the photographic convention.
    /// f/1.0 → 0, f/1.4 → 1, f/2.0 → 2, f/2.8 → 3, f/4.0 → 4.
    /// (One full stop halves light, doubling N^2, so N = 2^(stops/2).)
    public static func apertureStops(_ fNumber: Double) -> Double {
        2 * log2(fNumber)
    }

    /// Aperture (f-number) for a stop offset from f/1.0.
    public static func apertureValue(stops: Double) -> Double {
        pow(2, stops / 2)
    }

    /// Shutter stop offset from 1 second. 1 s → 0, 1/2 s → +1 (faster),
    /// 2 s → −1 (slower). Faster exposure is a *higher* offset.
    public static func shutterStops(_ seconds: Double) -> Double {
        -log2(seconds)
    }

    /// Shutter duration (seconds) for a stop offset from 1 second.
    public static func shutterValue(stops: Double) -> Double {
        pow(2, -stops)
    }

    // MARK: - EV100

    /// EV100 for a concrete ISO / f-number / shutter duration.
    ///
    /// `EV100 = log2(aperture^2 / duration) - log2(ISO / 100)`.
    public static func ev100(iso: Double, aperture: Double, shutterSeconds: Double) -> Double {
        log2((aperture * aperture) / shutterSeconds) - log2(iso / 100)
    }

    /// EV100 from stop offsets. Equivalent to the value-based form above;
    /// this is the linear identity the solver relies on. `apertureStops`
    /// here follows the photographic `log2(N^2)` convention.
    public static func ev100(isoStops: Double, apertureStops: Double, shutterStops: Double) -> Double {
        apertureStops + shutterStops - isoStops
    }

    // MARK: - Axis dispatch

    /// The stop offset of `value` on `axis`.
    public static func stops(of axis: ExposureAxis, value: Double) -> Double {
        switch axis {
        case .iso: isoStops(value)
        case .aperture: apertureStops(value)
        case .shutter: shutterStops(value)
        }
    }

    /// The exact value for `stops` on `axis`.
    public static func value(of axis: ExposureAxis, stops: Double) -> Double {
        switch axis {
        case .iso: isoValue(stops: stops)
        case .aperture: apertureValue(stops: stops)
        case .shutter: shutterValue(stops: stops)
        }
    }
}
