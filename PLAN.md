# Delivery Plan

## Active milestone

Camera session, native metering, luminance confidence, and Spot control.

Progress: the pure, deterministic meter core (`MeterEngine` and its sample/reading/configuration types) is complete with fixture tests. Remaining: the DEBUG-only Test Meter seam, the AVFoundation camera-session and native-metering adapter, luminance-analysis adapter, Spot control wiring, and the meter UI.

## Roadmap

1. [x] Exposure math and deterministic tests.
2. Camera session, native metering, luminance confidence, and Spot control.
3. Meter UI, Live/Hold workflow, and equivalent-exposure controls.
4. Local history and optional settings snapshots.
5. TestFlight beta, accessibility review, and release readiness.

## Verification gate

Camera, permission, and Photos behavior require physical-device validation. The completed release gate also includes Dynamic Type, VoiceOver, and portrait-first preview-contrast checks.
