# Changelog

## Unreleased

- Added the pure, deterministic meter core — `MeterSample`, `MeterReading` (with `ConfidenceLevel`), `MeterConfiguration`, `MeteringMode`/`NormalizedPoint`, and `MeterEngine` — with fixture-based Swift Testing coverage of the metadata EV authority, 10 Hz rate cap, rolling-window stability, dark/clipped confidence and precedence, Spot luma judgment, stale/unavailable handling, and context-change resets. Luminance only expresses confidence; it never alters the reported EV.
- Set the minimum deployment target to iOS 26.0 to match the spec's iOS 26+ requirement.
- Added the pure, deterministic exposure-math domain — `ExposureAxis`, `StopIncrement`, `ExposureMath`, `ExposureValueTables`, `StopQuantizer`, and `ExposureSolver` — with table-driven Swift Testing coverage of the math, stop rounding, filter compensation, and boundaries.
- Added agent delivery contract and initial project-management documentation.
