# Delivery Plan

## Active milestone

Camera session, native metering, luminance confidence, and Spot control.

Progress: the pure, deterministic meter core (`MeterEngine`), the `MeteringSource` feed seam, the DEBUG-only `TestMeterSource`, the equivalent-exposure dial state (`ExposureState`), the `MeteringController`, the meter UI (`MeterScreen`), and the real camera feed (`CameraMeteringSource` with session/permission handling, native AE metadata as the EV authority, `LuminanceAnalyzer` confidence/Spot diagnostics, and mode/Spot configuration) are complete with simulator unit and integration tests. Remaining for this milestone: physical-device validation of camera, permission, and Spot behavior (including the screen→capture point-of-interest transform and `lensAperture` availability on iOS 26 fixed-aperture hardware).

## Roadmap

1. [x] Exposure math and deterministic tests.
2. Camera session, native metering, luminance confidence, and Spot control.
3. [x] Meter UI, Live/Hold workflow, and equivalent-exposure controls.
4. Local history and optional settings snapshots.
5. TestFlight beta, accessibility review, and release readiness.

## Verification gate

Camera, permission, and Photos behavior require physical-device validation. The completed release gate also includes Dynamic Type, VoiceOver, and portrait-first preview-contrast checks.
