# Stop-Down — Agent Instructions

## Product authority

Read `Stop-Down Light Meter App -- Planning Specs.md` and `README.md` before changing product behavior. Stop-Down is a reflected-light exposure guide for photographers using an iPhone as a meter for another camera; it is not an incident meter or a laboratory-calibrated exposure reference.

Follow the roadmap in order: exposure math and deterministic tests; camera session/native metering/luminance confidence/Spot; meter UI and equivalent exposures; local history and snapshots; then TestFlight and release readiness.

## Delivery loop

For every completed, file-changing delivery: inspect status and relevant docs; make the smallest coherent change; update only documentation whose facts changed; run proportionate verification; review the diff; commit code, tests, build metadata, and docs atomically; then push to `origin`. A task is not done solely because a tool succeeds: relevant checks must pass or a concrete blocker must be recorded.

Maintain `PROJECT.md`, `PLAN.md`, `TODO.md`, `ARCHITECTURE.md`, `DECISIONS.md`, and `CHANGELOG.md` truthfully. Link GitHub Issues from `TODO.md` instead of duplicating them. Check whether a file or directory exists before creating it and preserve unrelated user work.

## Architecture and product constraints

- Target iOS 26+, SwiftUI, AVFoundation, and SwiftData.
- Keep exposure math independent of camera hardware and UI.
- Native camera auto-exposure metadata is the EV authority. Luminance analysis may express confidence or instability, but must not silently alter reported EV.
- Isolate AVFoundation, camera permission, Photos access, persistence, and haptics behind testable adapters.
- Maintain a DEBUG-only Test Meter for injecting known readings on simulator and device.
- Keep the product local-first: no accounts, analytics, ads, network requests, or app-operated cloud sync.
- Save snapshots to Photos only after explicit user action and confirmation; request add-only Photos permission only when needed.
- Do not add Bulb tools, reciprocity compensation, or other deferred features without updating the plan/specification.

## Verification

Discover projects, schemes, test targets, and existing scripts before selecting commands; never guess a scheme name. Keep `scripts/verify.sh` as the canonical verification entry point. Cover exposure math, stop rounding, filter compensation, and boundaries with unit tests; fake metadata and synthetic luminance with integration tests; and key workflows with UI tests. Physical-device validation is required for camera, permission, and Photos behavior. Accessibility validation covers Dynamic Type, VoiceOver, preview contrast, and portrait-first use.

## Versioning and Git safety

Maintain `VERSIONS_LOCATIONS.md` as the inventory of version/build locations. Keep marketing version separate from a monotonically increasing build number; increment the build number once per completed file-changing delivery and change marketing version only for an intentional release. Xcode build settings and `Info.plist` values are authoritative. Never force-push, rewrite history, reset destructively, commit secrets/signing material, or include unrelated changes.
