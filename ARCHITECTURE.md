# Architecture

`SwiftUI views → exposure domain → camera/persistence/Photos adapters`

The pure, deterministic exposure-math domain lives in `Stop-Down/Domain/`:

- `ExposureAxis` / `StopIncrement` — the three dial axes (ISO, aperture, shutter) and full/half/third increments.
- `ExposureMath` — EV100 and per-axis stop/value conversions (pure math).
- `ExposureValueTables` — the canonical conventional dial values and their display labels.
- `StopQuantizer` — rounds an arbitrary stop offset onto a full/half/third grid (ties round down).
- `ExposureSolver` — solves any two dial values for the third at a target EV, with filter compensation.

The pure, deterministic meter core also lives in `Stop-Down/Domain/`:

- `MeterSample` — one timestamped sample carrying optional native metadata (ISO/duration/aperture) and optional luminance diagnostics (center/spot luma, clipping, noise); derives `metadataEV100` from the metadata.
- `MeterReading` — a displayable reading: final EV, metadata EV, source diagnostics, mode, lens, `ConfidenceLevel`, confidence reason, and filter compensation.
- `ConfidenceLevel` — `.stable`, `.stabilizing`, `.dark`, `.clipped`, `.stale`, `.unavailable`, with `isLowConfidence` and user-facing `guidance`.
- `MeterConfiguration` — stability (count/window/tolerance), 10 Hz rate cap, and confidence thresholds (min luma, max clipping, max noise).
- `MeteringMode` / `NormalizedPoint` — center-weighted vs. spot metering and the normalized Spot point.
- `MeterEngine` — deterministic stateful engine over sample timestamps (no hidden clock): 10 Hz rate cap, rolling 300 ms smoothing window, stability (≥3 samples within ±0.1 EV), and confidence precedence (clipped → dark → stable → stabilizing). Missing metadata preserves the last reading as `.stale`, or reports `.unavailable` when none exists.

The metering layer lives in `Stop-Down/Metering/`, between the feed and the UI:

- `MeteringSource` — the `@MainActor` feed seam that emits `MeterSample`s (the real camera source will conform to this; `TestMeterSource` conforms today).
- `TestMeterSource` — DEBUG-only fixture feed at ~10 Hz with stable/unstable/dark/clipped scenarios and pause/step (spec 8.5); it is always presented as test data, never a true reading.
- `ExposureState` — pure dial state: exactly two pinned axes (the locked axis and the anchor axis) plus one solved axis recomputed by `ExposureSolver` for the target EV (spec §4.3).
- `MeteringController` — `@MainActor @Observable` controller that owns the `MeterEngine` and a `MeteringSource`, keeps a live reading plus a frozen held reading, and exposes configuration and dial operations. While held, incoming samples update the live reading but never re-solve the dials.

`Stop-Down/Views/MeterScreen.swift` renders the meter (spec §4.2): EV readout, LIVE/HOLD state, low-confidence banner, lockable dials with the solved axis marked, filter compensation, stop-increment picker, Hold/Live + Save, and a DEBUG test-data bar. The UI talks only to `MeteringController`, so swapping the feed never touches the layout.

Exposure math and the meter engine are pure and deterministic and independent of camera hardware and UI. AVFoundation will supply native auto-exposure metadata as the EV authority. Luminance analysis only expresses confidence/instability and never alters the reported EV. Camera permissions, Photos saves, SwiftData history, and haptics will be isolated behind testable adapters.
