# Delivery Plan

## Active milestone

Camera session, native metering, luminance confidence, and Spot control.

Progress: the pure, deterministic meter core (`MeterEngine`), the `MeteringSource` feed seam, the DEBUG-only `TestMeterSource`, the equivalent-exposure dial state (`ExposureState`), the `MeteringController`, the meter UI (`MeterScreen`, now the spec's hybrid meter over the live camera preview: full-bleed preview background, 220 pt circular EV dial with the thin state ring, lens selection per FR-1, and the spec §4.7 design tokens), and the real camera feed (`CameraMeteringSource` with session/permission handling, lens discovery and lens switching, native AE metadata as the EV authority, `LuminanceAnalyzer` confidence/Spot diagnostics, mode/Spot configuration, and the pure `SpotPointConverter` screen↔capture math) are complete with simulator unit and integration tests. Remaining for this milestone: physical-device validation of camera, permission, and Spot behavior (including the preview and reticle placement, lens switching, the screen→capture point-of-interest transform, and `lensAperture` availability on iOS 26 fixed-aperture hardware).

## Roadmap

1. [x] Exposure math and deterministic tests.
2. Camera session, native metering, luminance confidence, and Spot control.
3. [x] Meter UI, Live/Hold workflow, and equivalent-exposure controls.
4. Local history and optional settings snapshots.
5. TestFlight beta, accessibility review, and release readiness.

## Verification gate

Camera, permission, and Photos behavior require physical-device validation. The completed release gate also includes Dynamic Type, VoiceOver, and portrait-first preview-contrast checks.
