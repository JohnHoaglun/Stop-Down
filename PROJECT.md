# Stop-Down

## Status

In active development. The exposure-math domain (including the nearby equivalent-combinations finder), deterministic meter core, the meter screen over the live camera preview (lens selection, tap-to-position Spot reticle, nearby-combinations list with auto-Hold on dial edits, spec §4.7 visual system), and the real AVFoundation camera metering feed are implemented with simulator tests. An on-device review round fixed the confidence display (noise-gated dark judgment) and the screen fit (pinned control bars, responsive EV dial with an explicit unit label, fixed banner slot); physical-device validation of camera/permission/preview/Spot behavior — including a re-check of those fixes on device — is the current focus.

## Purpose

A simple reflected-light meter for iPhone photographers using a separate manual or film camera. It meters a scene, holds a reading, and translates equivalent ISO, aperture, and shutter-speed combinations.

## Platform

iPhone 11 and newer, including iPhone SE (2nd generation and later); iOS 26+; SwiftUI, AVFoundation, and SwiftData.

## Architecture status

See `ARCHITECTURE.md`. Exposure math and the meter engine are independent of camera and UI. Native auto-exposure metadata provides EV through `CameraMeteringSource`; luminance analysis reports confidence without changing EV.
