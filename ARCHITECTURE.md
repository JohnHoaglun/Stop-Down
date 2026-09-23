# Architecture

`SwiftUI views → exposure domain → camera/persistence/Photos adapters`

The pure, deterministic exposure-math domain lives in `Stop-Down/Domain/`:

- `ExposureAxis` / `StopIncrement` — the three dial axes (ISO, aperture, shutter) and full/half/third increments.
- `ExposureMath` — EV100 and per-axis stop/value conversions (pure math).
- `ExposureValueTables` — the canonical conventional dial values and their display labels.
- `StopQuantizer` — rounds an arbitrary stop offset onto a full/half/third grid (ties round down).
- `ExposureSolver` — solves any two dial values for the third at a target EV, with filter compensation.

Exposure math is pure and deterministic and independent of camera hardware and UI. AVFoundation will supply native auto-exposure metadata as the EV authority. Luminance confidence, camera permissions, Photos saves, SwiftData history, and haptics will be isolated behind testable adapters. A DEBUG-only Test Meter will inject known readings.
