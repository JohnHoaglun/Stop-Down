# Delivery Plan

## Active milestone

Camera session, native metering, luminance confidence, and Spot control.

Progress: the pure, deterministic meter core (`MeterEngine`), the `MeteringSource` feed seam with the DEBUG-only `TestMeterSource`, the equivalent-exposure dial state (`ExposureState`), the `MeteringController`, and the meter UI (`MeterScreen`) are complete with fixture tests. Remaining for this milestone: the AVFoundation camera-session and native-metering adapter, the luminance-analysis adapter, and Spot point-of-interest wiring (all behind the existing `MeteringSource` seam).

## Roadmap

1. [x] Exposure math and deterministic tests.
2. Camera session, native metering, luminance confidence, and Spot control.
3. [x] Meter UI, Live/Hold workflow, and equivalent-exposure controls.
4. Local history and optional settings snapshots.
5. TestFlight beta, accessibility review, and release readiness.

## Verification gate

Camera, permission, and Photos behavior require physical-device validation. The completed release gate also includes Dynamic Type, VoiceOver, and portrait-first preview-contrast checks.
