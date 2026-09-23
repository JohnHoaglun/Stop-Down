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
- `MeterEngine` — deterministic stateful engine over sample timestamps (no hidden clock): 10 Hz rate cap, rolling 300 ms smoothing window, stability (≥3 samples within ±0.1 EV), and confidence precedence (clipped → dark → stable → stabilizing). Missing metadata preserves the last reading as `.stale`, or reports `.unavailable` when none exists. `reset()` clears the window, rate cap, and current reading so a feed swap never answers with the old feed's state.

The metering layer lives in `Stop-Down/Metering/`, between the feed and the UI:

- `MeteringSource` — the feed seam that emits `MeterSample`s and applies metering configuration (mode/Spot context, `applyConfiguration` is a protocol requirement so calls reach the concrete source through the existential). `CameraMeteringSource` and `TestMeterSource` both conform.
- `CameraMeteringSource` — the real AVFoundation feed. `start()` requests camera access once, configures a video session with the built-in camera, and reads native AE metadata (ISO, duration, aperture) per frame as the EV authority. It locks device configuration only around point-of-interest and exposure-mode commits, re-reads the device per session queue, and re-syncs permission state on `UIApplication.didBecomeActiveNotification` (the iOS 27 SDK removed `AVCaptureDeviceWasAuthorized`). On denial or session failure it reports `.unavailable` with a reason instead of fabricating a reading.
- `TestMeterSource` — DEBUG-only fixture feed at ~10 Hz with stable/unstable/dark/clipped scenarios and pause/step (spec 8.5); it is always presented as test data, never a true reading.
- `ExposureState` — pure dial state: exactly two pinned axes (the locked axis and the anchor axis) plus one solved axis recomputed by `ExposureSolver` for the target EV (spec §4.3).
- `MeteringController` — `@MainActor @Observable` controller that owns the `MeterEngine` and a `MeteringSource`, keeps a live reading plus a frozen held reading, and exposes configuration and dial operations. While held, incoming samples update the live reading but never re-solve the dials. The default feed is the camera; DEBUG builds can swap the feed at runtime (`replaceSource` resets engine state first).

The camera layer lives in `Stop-Down/Camera/`, isolated behind the seam:

- `CameraFrameCoordinator` — serializes per-frame work off the capture session queue and hops samples to `MainActor` for delivery.
- `LuminanceAnalyzer` — pure, `nonisolated` analysis of biplanar (Y-U-V) pixel buffers: a stride-8 Y grid for center-weighted luminance and a 16×16 Spot box around the normalized point, reporting luma, clipping, and noise diagnostics. Non-biplanar frames are rejected (`hasLuma == false`) rather than misread.

`Stop-Down/Views/MeterScreen.swift` renders the meter (spec §4.2): EV readout, LIVE/HOLD state, low-confidence banner, camera-unavailable banner, lockable dials with the solved axis marked, filter compensation, stop-increment picker, Hold/Live + Save, and a DEBUG test-data bar with feed switching. The UI talks only to `MeteringController`, so swapping the feed never touches the layout.

Exposure math and the meter engine are pure and deterministic and independent of camera hardware and UI. AVFoundation supplies native auto-exposure metadata as the EV authority through `CameraMeteringSource`. Luminance analysis only expresses confidence/instability and never alters the reported EV. Photos saves, SwiftData history, and haptics will be isolated behind testable adapters.
