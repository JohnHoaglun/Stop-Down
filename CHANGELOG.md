# Changelog

## Unreleased

- Added the metering seam and the meter UI. `MeteringSource` is the single feed seam; the DEBUG-only `TestMeterSource` emits known fixtures at ~10 Hz with stable/unstable/dark/clipped scenarios and pause/step (spec 8.5). `ExposureState` keeps the locked/anchor/solved dial trio in equivalent exposure (spec §4.3), `MeteringController` drives the engine and holds live/held readings, and the portrait-first `MeterScreen` shows the EV readout, LIVE/HOLD state, confidence banner, lockable dials, filter compensation, stop increment, and a clearly-labeled DEBUG test-data bar. Unit coverage added for dial solving, lock/anchor behavior, hold/live freezing, and compensation re-solves. The app now shows the meter instead of the placeholder screen.
- Added the pure, deterministic meter core — `MeterSample`, `MeterReading` (with `ConfidenceLevel`), `MeterConfiguration`, `MeteringMode`/`NormalizedPoint`, and `MeterEngine` — with fixture-based Swift Testing coverage of the metadata EV authority, 10 Hz rate cap, rolling-window stability, dark/clipped confidence and precedence, Spot luma judgment, stale/unavailable handling, and context-change resets. Luminance only expresses confidence; it never alters the reported EV.
- Set the minimum deployment target to iOS 26.0 to match the spec's iOS 26+ requirement.
- Added the pure, deterministic exposure-math domain — `ExposureAxis`, `StopIncrement`, `ExposureMath`, `ExposureValueTables`, `StopQuantizer`, and `ExposureSolver` — with table-driven Swift Testing coverage of the math, stop rounding, filter compensation, and boundaries.
- Added agent delivery contract and initial project-management documentation.
