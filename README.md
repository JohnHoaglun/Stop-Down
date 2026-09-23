# Stop-Down

**A simple reflected-light meter for iPhone photographers.**

Stop-Down uses the iPhone camera to help photographers meter a scene, hold a reading, and translate it into equivalent ISO, aperture, and shutter-speed combinations for a separate manual or film camera.

> **Project status:** Planned and in active development. Stop-Down is not yet available as an app.

## What it will do

- Meter reflected light through the selected iPhone camera.
- Show a large, clear EV reading over the live camera preview.
- Offer center-weighted average metering and tap-to-position Spot metering.
- Let you Hold a reading, lock ISO, aperture, or shutter speed, and explore equivalent exposures.
- Support full-, half-, and third-stop controls, plus 0–10 stops of ND/filter compensation.
- Save a lightweight local history of readings.
- Create an optional scene snapshot with the chosen exposure settings burned into the image.

## Designed for photographers

Stop-Down is intended for photographers using an iPhone as a practical meter for a separate manual or film camera. It is a reflected-light exposure guide—not an incident meter or a laboratory-calibrated reference.

The app uses the iPhone camera’s native auto-exposure metadata as its EV authority. Live luminance analysis helps identify unstable, clipped, or low-confidence readings without altering the reported EV.

## Platform

- iPhone 11 and newer, including iPhone SE (2nd generation and later)
- iOS 26 and later
- SwiftUI, AVFoundation, SwiftData

## Privacy

Stop-Down is designed to be local-first:

- No accounts, analytics, ads, network requests, or app-operated cloud sync.
- Metering, calculations, and reading history remain on device.
- Snapshots are saved to Photos only after explicit confirmation, using add-only Photos permission. Any later iCloud syncing follows the user’s Photos settings.

## Planned experience

The interface pairs a central EV dial with direct exposure wheels for ISO, aperture, and shutter speed. It is portrait-first, high contrast over the live camera preview, and designed to remain usable with Dynamic Type and VoiceOver.

Initial support includes:

- ISO 6–12,800
- Apertures f/0.7–f/64
- Shutter speeds 1/8000 s–30 s

Long-exposure Bulb tools and film reciprocity compensation are planned for a later release.

## Quality and testing

The project is being designed with a four-layer test harness:

1. Unit tests for exposure math, stop rounding, filter compensation, and edge cases.
2. Integration tests using fake camera metadata and synthetic luminance samples.
3. UI tests for onboarding, permissions, Live/Hold, Spot mode, exposure controls, history, and snapshots.
4. A DEBUG-only Test Meter for injecting known readings on a simulator or physical device.

## Roadmap

1. Exposure math and deterministic tests.
2. Camera session, native metering, luminance confidence, and Spot control.
3. Meter UI, Hold/Live workflow, and equivalent-exposure controls.
4. Local history and optional settings snapshots.
5. TestFlight beta, accessibility review, and release readiness.

## Contributing

Stop-Down is intended to be open source under the Apache License 2.0. Contribution and setup guidance will be added as development begins.

## License

Apache License 2.0 is planned for the project. The repository license file will be added before the first public release.
