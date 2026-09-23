# Stop-Down — Planning Specification

**Status:** Approved v1 planning baseline  
**Platform:** iPhone 11 and newer (including iPhone SE, 2nd generation and later), iOS 26 and later  
**Build environment:** Current Xcode, Swift 5.9+, SwiftUI, AVFoundation  
**License:** Apache License 2.0 (Apache-2.0)

## 1. Product summary

Stop-Down is a simple, privacy-respecting reflected-light meter for photographers using an iPhone to set exposure on a separate manual or film camera. It measures the live camera scene, presents an EV reading, and lets the photographer explore equivalent ISO, aperture, and shutter combinations.

The product is a learning project for a future photo app, but the first release must be useful on its own: quick to open, legible outdoors, honest about uncertainty, and explicit that it is a reflected-light meter—not an incident meter.

### Product promise

“Meter the scene with your iPhone, hold the reading, and translate it into a usable exposure for your camera.”

### Non-goals for v1

- Incident-light metering or a diffuser accessory.
- Direct manual control of the iPhone camera for final photography.
- Location capture, cloud sync, accounts, analytics, ads, or any server component.
- Film reciprocity compensation, bulb timer, camera-range profiles, hyperfocal tools, or reading export. These remain future work.

## 2. Release scope

### In scope

1. Reflected-light metering from the selected iPhone camera.
2. A fused meter model: camera auto-exposure metadata plus live image-luminance analysis.
3. Center-weighted average metering and user-positioned spot metering.
4. A large EV readout, confidence state, and simple exposure guidance.
5. Live/Hold control independent of Save.
6. ISO, aperture, and shutter dials with one lockable axis and equivalent-exposure results.
7. Full-, half-, and third-stop increments; third stop is the default.
8. Manual filter/ND exposure compensation.
9. Modern iPhone camera/lens selection when the hardware offers it.
10. Lightweight local reading history with optional thumbnail.
11. Optional snapshot photo with a burned-in settings overlay and explicit Photos-save confirmation.
12. Three-screen first-run onboarding and appropriately timed permission education.
13. A deterministic automated test suite and a developer-only Test Meter harness.

### Deferred to v2+

- User-defined camera profiles and supported ranges.
- Closest-match mode for a chosen camera profile.
- Reciprocity-failure compensation and bulb timer.
- Volume-button control, share export, presets, dark-theme customization, and hyperfocal calculator.

## 3. Target users and primary workflow

### Primary user

A photographer who carries a manual digital or film camera and uses their iPhone to meter a scene. They understand, or want to learn, ISO, aperture, shutter speed, and stops.

### Main workflow

1. Launch Stop-Down and tap **Start metering**.
2. Grant Camera access when asked; select a lens if more than one is available.
3. Use the default center-weighted average mode, or choose Spot and tap the subject/area to meter.
4. Watch the live EV reading stabilize; tap **Hold** to freeze it.
5. Optionally set filter compensation and select the desired ISO/aperture/shutter lock.
6. Turn the dials to examine equivalent exposures and select an intended combination.
7. Tap **Save** to add the reading to local history; optionally create and confirm a settings-snapshot photo.
8. Resume **Live** metering or inspect history.

## 4. UX and screen specification

### 4.1 Onboarding

Show only on first launch. It may be dismissed and revisited from Settings.

1. **Reflected light:** “Stop-Down reads light reflected from the scene through your iPhone camera.”
2. **Meter and hold:** explain Average vs. Spot and that Hold freezes a reading for study.
3. **Translate exposure:** explain locking an exposure value to explore equivalent settings.

The final action is **Start metering**. Do not ask for Camera permission during passive onboarding; request it after this action. If denied, show a recovery screen with an **Open Settings** button and a non-camera **Manual/Test Meter** option in developer builds only.

### 4.2 Meter screen

The visual direction is a clean dial interface over the live camera preview. The preview remains visible behind a high-contrast, accessible control layer.

The app is portrait-first in v1. It does not provide a separate landscape interface, but preview orientation, still-photo orientation, and Spot coordinate conversion must remain correct.

- **Top bar:** selected lens, Average/Spot segmented control, History, Settings.
- **Preview:** camera feed. In Spot mode, show a movable reticle at the tapped point; a tap moves it. The spot region is visible but unobtrusive.
- **Center dial/readout:** a large `EV x.x` value, mode label, and `LIVE` or `HOLD` state. Show a subtle stabilization indicator while live.
- **Confidence banner:** only when needed. It explains low confidence without hiding the latest estimate.
- **Exposure controls:** ISO, aperture, shutter wheels; selected locked axis has a lock icon and clear accent. One axis is locked at a time. The user can choose another locked axis at any time.
- **Compensation:** filter/ND compensation control, shown as a signed stop value; its effect is visible in the resulting exposure.
- **Bottom actions:** Hold/Live, Save. Save must not change the Hold/Live state.

Accessibility requirements: every dial supports VoiceOver adjustable actions, controls have labels and values, dynamic type does not obscure the EV or primary actions, and color is never the sole confidence indicator.

### 4.3 Exposure-dial behavior

The app has a target EV derived from the held or current reading after compensation. The three values must always describe an equivalent exposure, subject to the current stop increment.

- The user selects one locked axis: ISO, aperture, or shutter.
- Changing either unlocked dial causes the engine to solve the remaining unlocked value.
- If a selected value is impossible in the supported generic range, the nearest supported value is selected and the UI states that the result was rounded.
- A compact list below the wheels shows nearby equivalent combinations. Tapping a row applies it.
- No individual camera profile constrains values in v1. The generic tables cover ISO 6–12,800, apertures f/0.7–f/64, and shutter speeds 1/8000 s–30 s. The app does not claim that every listed combination is supported by the user’s camera.
- For a calculated exposure beyond 30 seconds, show the 30-second boundary and explain: “For longer exposures, use this as a base reading; reciprocity compensation and a Bulb timer are planned for a later release.”
- Initial values are ISO 100 locked and f/5.6; the engine calculates the shutter value from the meter reading.
- Turning an exposure wheel while Live automatically enters Hold before applying the edit. Returning to Live preserves the selected lock axis and wheel preferences, then updates the calculated equivalent value as the EV changes.

### 4.4 Confidence and extreme-light states

Continue to display the latest estimated EV, but visibly label it **Low confidence** when the measurement is likely unreliable.

| Condition | User-facing guidance |
| --- | --- |
| Very dark/noisy preview | “Too dark for a reliable meter reading. Use a tripod or a longer exposure.” |
| Highlight clipping / overexposure | “Highlights are clipped. Meter a darker mid-tone area.” |
| Camera adjusting / no stable samples | “Stabilizing reading…” |
| Camera unavailable | “Camera unavailable. Choose another lens or try again.” |

Do not invent a precision value when the capture pipeline has no valid data. In that case, preserve the last valid reading with its timestamp and mark it stale rather than calculating a new one.

### 4.5 History

History is local-only and lists newest first. A saved record contains:

- system creation timestamp (used for ordering and display),
- EV,
- ISO,
- shutter speed,
- aperture,
- filter compensation,
- metering mode,
- selected lens identifier/display name,
- optional thumbnail reference, when a constrained local JPEG is created.

The history detail view renders these fields clearly and allows deletion of an individual reading. A future release may add notes and export; v1 does not.

History has no automatic deletion limit in v1. Constrain each thumbnail to a 320-point long edge and an 80 KB JPEG budget. Provide individual deletion and a clearly confirmed **Clear all history** action. At 500 readings or 40 MB of thumbnail storage, show a non-blocking **Review history** notice; never delete a record automatically.

### 4.6 Snapshot photo

After Save, present a clear choice: **Save reading only**, **Create snapshot**, or Cancel. Tapping Save immediately creates the reading-history record. Creating a snapshot captures the current scene, renders a legible settings overlay, and presents a preview. The user may save it to Photos or keep the reading without a photo. It must never silently add an image to Photos.

Overlay fields: EV, ISO, aperture, shutter, filter compensation, metering mode, selected lens, and timestamp. The overlay must be readable on both light and dark scenes (opaque or adaptive backing). Create and attach a local thumbnail only after Photos save succeeds. If Photos permission is denied, capture fails, or the user cancels, retain the reading without a thumbnail, explain recovery where appropriate, and do not treat Save as failed. Deleting history removes its local thumbnail only; it never removes the separately user-owned image from Photos.

### 4.7 Visual direction and design-system plan

The approved direction is a **hybrid meter**: a circular central EV meter that gives the app a photographic-instrument feel, paired with straightforward exposure wheels in the lower third for speed and clarity. The desired character is “instrument-panel clarity over a live camera view,” rather than a skeuomorphic reproduction of a vintage meter.

#### Visual hierarchy

1. The EV value and Live/Hold state are always the most prominent elements.
2. Metering mode, confidence, and selected lens are visible at a glance but secondary.
3. Exposure wheels and lock state are the main editing controls.
4. Save and History are available without competing with the meter reading.

#### Design constraints

- Use the live camera preview as the background with dark/translucent adaptive panels behind controls.
- Use one restrained semantic accent color for the selected lock axis and active controls; never use color alone to communicate state.
- Use high-contrast white/light meter numerals and a distinct warning treatment for low confidence.
- Ensure every primary target is at least 44 by 44 points, including dial lock targets.
- Support Dynamic Type without obscuring EV, Hold/Live, or Save; allow secondary chrome to reflow or collapse.
- Provide VoiceOver labels/values for EV, mode, confidence, each dial, and each lock state. Wheels support adjustable actions.
- Test panel opacity and text contrast against bright sun, dark interiors, and mixed scenes using the DEBUG Test Meter fixture states.

#### Approved visual system

Build the selected **hybrid** design first as a static SwiftUI fake-data screen, then use the DEBUG Test Meter states to validate it before real-camera integration. The validation rubric remains outdoor legibility, one-handed reach, speed of recognizing Live/Hold and low confidence, Dynamic Type behavior, VoiceOver clarity, and readability over both light and dark preview scenes.

**Typography**

- EV: `.system(size: 64, weight: .bold, design: .rounded)` with `.monospacedDigit()`. Use responsive scaling and a minimum scale factor rather than allowing the readout to clip.
- ISO/aperture/shutter values: `.system(size: 28, weight: .semibold)` with `.monospacedDigit()`.
- Mode/state labels: 13-point semibold uppercase labels with modest tracking.
- Guidance/confidence copy: the Dynamic Type body text style; never a fixed size.
- History values: 17–20-point semibold; labels use the system secondary text style.

**Geometry and spacing**

- Central EV dial: responsive 190–240-point diameter, targeting 220 points on standard iPhones.
- Use a thin, partial 6-point ring only as a state indicator; it is not a precision control.
- Exposure wheels occupy the lower third of the screen. Their lock controls have a 44 by 44-point minimum target.
- Use a 4/8/12/16/24-point spacing scale and reusable panel, dial, and state-badge components.

**Semantic colors**

| Token | Starting value | Use |
| --- | --- | --- |
| `meterBackground` | `#0B0B0D` | Near-black base behind preview/panels |
| `meterPanel` | Black at ~68% opacity | Adaptive control-panel backing |
| `meterPrimary` | `#F5F2EA` | EV and important values |
| `meterSecondary` | `#A6A8AD` | Labels and secondary metadata |
| `meterAccent` | `#FFB000` | Active lock, selected mode, primary interaction |
| `meterWarning` | `#FF7A45` | Low-confidence state, always paired with text/icon |
| `meterSuccess` | `#58B77B` | Confirmation only; never the sole state signal |

**App icon**

Use a near-black background with a centered, clean amber six-blade aperture ring and a single small downward tick/chevron at the ring’s bottom. Do not use letters, EV/ISO text, or a photorealistic camera. Deliver it as an Xcode vector/PDF asset and test its legibility at small icon sizes.

## 5. Functional requirements

### FR-1: Camera and lens session

- Start and stop `AVCaptureSession` safely off the main thread.
- Prefer the back wide camera initially. Expose only lenses supplied by the current device.
- Switching lenses restarts/configures the session cleanly and resets the live-sample smoothing window.
- Display a friendly unsupported-device message if the camera cannot be configured.

### FR-2: Meter calculation

The meter must use both inputs:

1. **Exposure-metadata authority:** obtain live ISO, exposure duration, lens aperture, exposure state, and device format information from AVFoundation. In Average mode, the iPhone camera’s native auto-exposure metadata is the EV authority. Estimate EV at ISO 100 using:

   `EV100 = log2(aperture² / exposureDurationSeconds) - log2(ISO / 100)`

2. **Image-luminance analysis:** sample low-cost luma values from `AVCaptureVideoDataOutput` pixel buffers. Compute center-weighted and spot-region statistics without retaining full frames. Use normalized luma and clipping/noise indicators only to validate the metadata result and assign confidence; never use preview brightness to alter EV.

In Spot mode, a tap sets the camera’s supported `exposurePointOfInterest`. Wait for the camera to settle, then use its resulting native exposure metadata as the EV authority. If the device cannot support a point of interest, communicate that Spot is unavailable rather than fabricating a spot result.

The implementation must keep these sources separately observable in debug output (`metadataEV`, luma/clipping/noise diagnostics, `finalEV`, confidence reason). This prevents a misleading black-box number and supports deterministic testing.

**Accuracy constraint:** v1 presents the iPhone camera’s native exposure metadata, informed by live image-luminance analysis for scene awareness and confidence. It provides no user adjustment and makes no laboratory-precision claim.

### FR-3: Metering modes

- **Center-weighted average:** use the normal camera auto-exposure behavior for the EV reading; use a center-weighted luma region and a short rolling sample window for confidence only.
- **Spot:** set the camera’s supported `exposurePointOfInterest` to the normalized user tap, then use its settled exposure metadata for the EV reading. Preserve the normalized point when preview layout changes; clamp it to valid bounds.
- Each reading stores the selected mode. A mode, lens, or spot-point change clears smoothing samples and transitions through a brief “Stabilizing” state.

### FR-4: Hold and live

- Live is the default after a valid camera session starts.
- Hold freezes the displayed `MeterReading`, including EV, confidence, mode, lens, and compensation at that moment.
- While held, camera preview may continue, but no dial target is changed automatically.
- Live resumes updates and clears the held-reading marker.

### FR-5: Exposure math and compensation

- Represent shutter speed internally as seconds, aperture as f-number, and ISO as numeric sensitivity.
- Apply filter compensation as a signed stop offset to the target exposure. Positive compensation represents additional exposure required by a light-reducing filter; UI copy must make this explicit.
- Support full (1 EV), half (0.5 EV), and third (1/3 EV) quantization, persisted in Settings.
- Use fixed standard value tables for v1, not floating-point values displayed as fabricated camera settings. Maintain a tested canonical table for ISO 6–12,800, apertures f/0.7–f/64, and shutter times 1/8000 s–30 s.
- The engine returns both unrounded and quantized values plus a rounding delta so the UI can explain meaningful rounding.
- Filter compensation defaults to 0 and ranges from 0 to +10 stops in the selected stop increment. It is exclusively for light-reducing filters in v1, so negative values are not offered. Display it as `Filter compensation +x.x stops`.

### 5.1 Canonical exposure-value tables

`ExposureValueTables` is the single source of truth for UI wheels, the solver, and test fixtures. Store exact numeric values internally; display conventional notation (`ISO 400`, `f/5.6`, `1/125 s`, `1 s`). Generate independent full-, half-, and third-stop series from exact stop math, then apply the same tested display formatter to each series. The third-stop display tables below define the default values. When a value is exactly between two supported choices, consistently choose the lower exposure value and report the rounding delta.

- **ISO:** 6, 8, 10, 12, 16, 20, 25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10,000, 12,800.
- **Aperture:** f/0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8, 3.2, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14, 16, 18, 20, 22, 25, 29, 32, 36, 40, 45, 51, 57, 64.
- **Shutter:** 1/8000, 1/6400, 1/5000, 1/4000, 1/3200, 1/2500, 1/2000, 1/1600, 1/1250, 1/1000, 1/800, 1/640, 1/500, 1/400, 1/320, 1/250, 1/200, 1/160, 1/125, 1/100, 1/80, 1/60, 1/50, 1/40, 1/30, 1/25, 1/20, 1/15, 1/13, 1/10, 1/8, 1/6, 1/5, 1/4, 1/3, 0.4 s, 0.5 s, 0.6 s, 0.8 s, 1 s, 1.3 s, 1.6 s, 2 s, 2.5 s, 3.2 s, 4 s, 5 s, 6 s, 8 s, 10 s, 13 s, 15 s, 20 s, 25 s, 30 s.

### FR-6: Settings

- Persist stop increment, last lens where applicable, last meter mode, and onboarding completion using `UserDefaults` through a testable settings store.
- Include a reset-settings confirmation. It resets app preferences but does not delete history without a separate explicit action.

### FR-7: Privacy and permissions

- Stop-Down makes no network requests, uses no analytics, and does not operate its own cloud sync. Metering, history, overlays, and calculations occur locally on device.
- A snapshot is saved to the user’s Photos library only after explicit confirmation and is then subject to the user’s Photos and iCloud settings.
- Camera permission: explain purpose before system prompt and recover gracefully after denial/restriction.
- Request `PHPhotoLibrary` add-only authorization only after the user chooses to save a snapshot. Never request read/write Photos access or fetch/list existing Photos assets.
- Add accurate Camera and add-only Photos usage descriptions to `Info.plist`.

### FR-8: Performance and lifecycle

- Camera preview may run at its configured device rate, but luma analysis and visible meter updates are each capped at 10 samples/updates per second.
- Mark a reading stable only after at least three consistent samples across 300 ms within ±0.1 EV. Process and display each usable sample within 250 ms; this does not guarantee how quickly camera auto exposure settles.
- Disable idle-screen sleep only while the Meter screen is actively Live; restore normal behavior when held, backgrounded, interrupted, or dismissed.
- Pause the session on backgrounding or camera interruption and show a recoverable state; reconfigure when returning to the foreground.
- Under serious thermal pressure, reduce analysis rate. At critical thermal pressure, pause metering and communicate the reason.

## 6. Technical architecture

Use a small, layered architecture with protocols at every hardware/persistence boundary. Keep views declarative and exposure calculations independent of AVFoundation and SwiftUI.

```text
SwiftUI Views
    │
Feature View Models (@MainActor)
    │
Domain: MeterEngine • ExposureSolver • ReadingRepository
    │
Adapters: CameraService • LuminanceAnalyzer • PhotoService • SettingsStore
    │
AVFoundation / Photos / SwiftData + local thumbnail files / UserDefaults
```

### Recommended implementation choices

- **UI:** SwiftUI with a UIKit/`UIViewRepresentable` preview layer wrapper only where required by `AVCaptureVideoPreviewLayer`.
- **Concurrency:** `CameraService` owns a serial session queue. It emits value-type samples through `AsyncStream` or Combine; UI state mutations happen on `@MainActor`.
- **Image analysis:** downsample/sample NV12 luma plane on a dedicated queue. Never do per-pixel full-resolution work on the main thread. Do not persist video frames for metering.
- **Persistence:** use SwiftData for `SavedReadingRecord` metadata, accessed only through `ReadingRepositoryProtocol`. Use a separate `ThumbnailStore` for constrained JPEG files in Application Support; records retain only an optional thumbnail filename. Configure the `ModelContainer` with CloudKit disabled and add no CloudKit entitlement. Use an in-memory `ModelContainer` in tests.
- **Photos:** use `AVCapturePhotoOutput` for a still image and render overlays with Core Graphics/UIGraphicsImageRenderer. Keep capture and Photos save as separate operations so a declined save is recoverable.

### Proposed modules/folders

```text
StopDown/
  App/
  Domain/
    MeterReading.swift
    ExposureValue.swift
    ExposureSolver.swift
    StopQuantizer.swift
    MeterEngine.swift
  Camera/
    CameraService.swift
    CameraSample.swift
    LuminanceAnalyzer.swift
    LensDescriptor.swift
  Features/
    Meter/
    History/
    Onboarding/
    Settings/
    Snapshot/
    DeveloperTools/
  Persistence/
    ReadingRepository.swift
    SettingsStore.swift
  Support/
StopDownTests/
StopDownUITests/
```

### Core domain contracts

Define these early and keep them platform-independent wherever possible:

- `MeterReading`: EV100, timestamp, ISO, duration, aperture, mode, lens, confidence, source diagnostics, and filter compensation.
- `MeterSample`: optional metadata EV inputs; normalized average/center/spot luma; clipping/noise signals; sample time.
- `MeterEngineProtocol`: accepts samples and configuration; emits a reading.
- `ExposureSolverProtocol`: solves equivalent values using target EV, lock axis, user edit, stop increment, and compensation.
- `CameraServiceProtocol`: authorization, available lenses, preview/session state, sample stream, and still capture.
- `ReadingRepositoryProtocol`: save/list/delete readings and optional thumbnail.
- `SettingsStoreProtocol`: typed settings get/set/reset.

## 7. Data model

### `SavedReading`

| Field | Type | Notes |
| --- | --- | --- |
| id | UUID | Stable identifier |
| createdAt | Date | System timestamp; required for history order |
| ev100 | Double | Stored before display rounding |
| iso | Double | Selected exposure value |
| shutterSeconds | Double | Selected exposure value |
| aperture | Double | Selected exposure value |
| filterCompensationEV | Double | Signed stops |
| meteringMode | Enum | `.centerWeighted`, `.spot` |
| lensID | String | Hardware identifier or stable app descriptor |
| lensDisplayName | String | Readable history label |
| thumbnailFilename | String? | Optional constrained-JPEG filename managed by `ThumbnailStore` |

No location, note, raw preview frame, account identifier, or cloud identifier is stored. SwiftData is configured for local persistence only; CloudKit sync is disabled.

## 8. Test harness and quality plan

The harness is a product feature, not an afterthought. Metering depends on hardware and lighting that cannot be reliably reproduced in CI, so the design must separate deterministic math from device adapters.

### 8.1 Test seams

- Inject `CameraServiceProtocol`, `LuminanceAnalyzing`, clock, settings store, repository, and photo saver.
- Ship JSON fixtures of sanitized `MeterSample` sequences: normal, dark/noisy, clipped, unstable, and spot-bright/spot-dark scenes.
- Include synthetic NV12/luma buffers or lightweight luma grids for analyzer tests; do not commit user photographs.
- Gate developer tools behind `#if DEBUG` and ensure they cannot appear in Release builds.

### 8.2 Unit tests — `StopDownTests`

Required deterministic cases:

- EV100 calculation across representative ISO/aperture/shutter values.
- Inverse solving: calculated combinations reproduce target EV within a defined tolerance.
- Full/half/third-stop table selection and tie-breaking rules.
- Filter compensation sign and magnitude.
- One locked axis is preserved; correct remaining axis is solved after an edit.
- Generic-range boundaries and rounding metadata.
- Average/Spot camera-configuration selection, spot-point clamping, and smoothing reset after mode/lens/spot change.
- Confidence classification for dark, clipped, stale, and stable samples.
- Stable-reading rules: three samples across 300 ms within ±0.1 EV, plus update-rate caps.
- Saved-reading serialization/migration and settings reset behavior.

Use table-driven tests with known photographic references. Floating-point assertions should use explicit tolerances; never compare computed doubles for exact equality.

### 8.3 Integration tests

Run in XCTest using fake camera/photo/persistence adapters:

- Feed recorded metadata/luma fixture sequences into `MeterEngine`; assert final EV, confidence, and diagnostic source values.
- Verify Spot configures the selected normalized exposure point of interest, waits for stable metadata, and uses that metadata without a preview-luma EV adjustment.
- Verify Hold freezes the exact reading while later fake-camera samples arrive; Live resumes changes.
- Verify Save writes precisely the approved metadata and creates/deletes a thumbnail file only when supplied.
- Verify snapshot flow invokes the renderer, then Photos saver only after confirmation; cancellation, capture failure, or Photos denial preserves the saved reading without a thumbnail.
- Verify backgrounding, camera interruption, and thermal-pressure state changes pause/recover the session correctly.
- Verify permission-denied and unavailable-camera state transitions never crash or leave controls falsely enabled.

### 8.4 UI tests — `StopDownUITests`

Launch with test arguments that inject a fake camera and stable fixtures. Cover:

- first-run onboarding and deferred Camera permission request;
- denied permission recovery path;
- Average/Spot selection and spot reticle placement;
- Live → Hold → Live labels and frozen EV;
- lock-axis selection, dial adjustment, and nearby-combination application;
- stop-increment setting persistence;
- low-confidence banner and accessibility labels;
- Save reading, History display, and delete confirmation;
- snapshot confirmation and Photos-denied user feedback.

Use stable accessibility identifiers for all essential controls and avoid tests that depend on animation timing or a real camera.

### 8.5 Developer-only Test Meter screen

Add a DEBUG-only Settings entry named **Test Meter**. It must:

- inject a known EV, mode, lens, and confidence state;
- select a fixture sequence (stable, dark, clipped, unstable, spot delta);
- pause/advance a sequence and display metadata EV, luma/clipping/noise diagnostics, final EV, and confidence reason;
- provide a reset-to-real-camera action;
- visibly state “DEBUG TEST DATA” so it cannot be mistaken for a true reading.

This enables hands-on demos and reproducible checks on simulator or device without depending on ambient lighting.

### 8.6 CI and manual device matrix

On every pull request: format/lint if configured, build, run unit and integration tests, and run UI tests against an iPhone simulator.

Before a release candidate, manually test on at least:

- iPhone 11 running iOS 26;
- a recent multi-lens iPhone;
- a current iOS release on a supported device.

Manual checks: each lens, bright sun, indoor room, very dark scene, permission denial/re-enable, dynamic type, VoiceOver, snapshot overlay readability, camera interruption, background/foreground transition, and no unexpected data/network activity.

## 9. Implementation roadmap for Xcode + OpenCode agents

Agents should receive narrow work packets with explicit interfaces, tests, and acceptance criteria. One integrator reviews all generated code; agents must not independently change domain contracts without approval. Keep each packet small enough for review and commit separately.

### Phase 0 — Bootstrap and conventions

- Create the Xcode project, targets, folder structure, `README`, license decision placeholder, and CI workflow.
- Add SwiftLint/SwiftFormat only if the team wants the maintenance overhead; do not block initial development on tooling.
- Add test targets and a fixture-loading utility before feature work.

**Done when:** clean build, empty tests pass, release build excludes developer tools, and project has privacy strings.

### Phase 1 — Pure exposure domain

- Implement `ExposureValue`, canonical stop tables, `StopQuantizer`, `ExposureSolver`, and filter-compensation rules.
- Write exhaustive table-driven tests before UI work.

**Done when:** a test suite proves known exposure equivalences, all increments, lock-axis behavior, and boundary behavior.

### Phase 2 — Camera and meter engine

- Implement authorization/session state and selected-lens discovery behind a fakeable camera service.
- Implement downsampled luma analyzer, average/Spot camera-point configuration, smoothing, diagnostics, and confidence engine.
- Feed fixture samples through integration tests before connecting real hardware.

**Done when:** real preview works on device; fixture tests are deterministic; live metadata/luma diagnostics can be inspected only in DEBUG.

### Phase 3 — Meter experience

- Build onboarding, permission recovery, preview, central readout, mode switch, spot reticle, and Hold/Live.
- Connect exposure dials and equivalent-exposure list to the proven domain engine.
- Add VoiceOver identifiers and UI tests as each control lands.

**Done when:** a user can complete the core workflow entirely with fake camera fixtures in UI tests and with real camera input on a device.

### Phase 4 — Persistence and snapshots

- Implement `SavedReadingRecord`, a local-only SwiftData `ModelContainer`, `SwiftDataReadingRepository`, and `ThumbnailStore`; cover the repository with in-memory SwiftData tests.
- Implement snapshot capture, overlay renderer, confirmation, thumbnail generation, and Photos error recovery.

**Done when:** Save preserves exactly the approved record fields; snapshot permission failures do not lose the reading; overlay is manually verified on light and dark scenes.

### Phase 5 — Developer harness, polish, release readiness

- Implement the DEBUG Test Meter screen.
- Add performance measurements for luma analysis and scroll/preview responsiveness.
- Complete accessibility, device matrix, privacy review, and documentation.

**Done when:** all automated tests pass, manual matrix is signed off, no known crash/permission dead end remains, and Test Meter is absent from Release.

## 10. Agent work-packet template

Use this prompt structure for every OpenCode agent task:

```text
You are working on Stop-Down, an iOS 26+ SwiftUI iPhone light-meter app for iPhone 11 and newer.
Task: [single concrete outcome].

Read these contracts first: [paths]. Do not change public domain interfaces
without identifying the reason and adding/updating tests.

Constraints:
- Keep AVFoundation and Photos behind protocols.
- No network calls, analytics, or new third-party dependencies.
- UI state updates occur on MainActor; camera work stays off the main thread.
- Add accessibility identifiers for interactive UI.
- Add or update XCTest coverage for every behavior.

Deliver:
1. Implementation limited to [paths/modules].
2. Tests covering [named scenarios].
3. A brief summary, test command/results, and any integration risk.
```

Recommended first assignments: (1) exposure domain/tests, (2) persisted settings/repository tests, (3) fake camera fixtures and meter-engine tests. Integrate only after interface agreement and passing tests.

## 10.1 Open-source repository policy

Stop-Down is licensed under the **Apache License 2.0**. This allows broad reuse while providing an explicit patent license from contributors; it requires retaining license and attribution notices and marking material changes where required.

Before the public repository is opened, add:

- `LICENSE` containing the unmodified Apache License 2.0 text and correct copyright holder/year notice.
- `CONTRIBUTING.md` with supported Xcode/iOS versions, setup and test commands, code/test expectations, PR-size guidance, and the rule that contributors may submit only work they have the right to license.
- A contribution statement: “Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in Stop-Down is licensed under Apache-2.0, without additional terms.”
- A short `README` privacy statement: all metering and history are on-device; no analytics, accounts, or network service are included in v1.

No contributor license agreement is required for v1. Add a `CODE_OF_CONDUCT.md` when external participation becomes active. Treat the Stop-Down name and any logo as separate trademark/brand assets; Apache-2.0 does not grant trademark rights.

## 10.2 Distribution path

Use a staged release path:

1. Develop and run locally through Xcode.
2. Distribute builds through TestFlight to a small real-device beta group after the automated suite and manual device matrix pass.
3. Publish to the App Store only after beta feedback confirms the metering workflow, privacy wording, and snapshot behavior are trustworthy.
4. Keep the GitHub repository public under Apache-2.0 from the start.

The TestFlight/App Store release build must exclude the DEBUG Test Meter and all fixture-injection paths.

## 11. Acceptance criteria for v1

- An iPhone 11 running iOS 26 can launch the app, complete onboarding, grant Camera access, and view a live average meter.
- A compatible multi-lens iPhone can switch among available lenses without a crash or stale reading.
- Average and tap-to-position Spot modes each change the active meter state and saved record.
- Hold freezes the reading; Live resumes it; Save is independent.
- A photographer starts at ISO 100 locked and f/5.6, can choose a lock axis, and, after Hold, can change an exposure value and see valid equivalent settings at the selected increment.
- Filter compensation has a tested, understandable effect.
- Low-light, clipping, denial, interruption, and unavailable-camera cases communicate uncertainty or recovery clearly.
- A saved history entry contains precisely the approved exposure/meter fields and optional thumbnail.
- A snapshot uses explicit confirmation before Photos save, includes a readable settings overlay, and adds a thumbnail only after a successful save.
- Stop-Down makes no network requests or cloud-sync calls; an opt-in Photos snapshot is subject to the user’s Photos/iCloud settings.
- Unit, integration, and UI test suites pass; Test Meter demonstrates known values in DEBUG and is unavailable in Release.

## 12. Decisions log

| Decision | Approved direction |
| --- | --- |
| Device support | iPhone 11 and newer, including iPhone SE (2nd generation and later); iOS 26 minimum |
| Meter inputs | Camera auto-exposure metadata plus image-luminance analysis |
| Metering authority | Native camera metadata sets EV; luminance is confidence-only; Spot uses a settled exposure point of interest |
| Metering modes | Center-weighted average and tap-positioned spot |
| Exposure controls | Three dials, one lockable axis, computed remaining value, nearby combinations |
| Stop increments | Full, half, third; default third |
| Snapshot | In v1; user confirms before Photos save |
| Saved reading data | EV, ISO, shutter, aperture, filter compensation, meter mode, lens, thumbnail, system timestamp |
| Onboarding | Three screens; permission only after Start metering |
| Extreme light | Retain estimate, label low confidence, provide guidance |
| Target user | Photographer metering for a separate manual or film camera |
| Test harness | Unit, integration, UI, and DEBUG Test Meter layers |
| License and contributions | Apache-2.0; lightweight `CONTRIBUTING.md`; inbound contributions under Apache-2.0; no CLA |
| Generic v1 exposure bounds | ISO 6–12,800; f/0.7–f/64; 1/8000 s–30 s; longer exposures deferred to Bulb/reciprocity work |
| Reading persistence | Local-only SwiftData metadata; separate Application Support JPEG thumbnails; CloudKit disabled; repository protocol retained |
| Visual system | Hybrid EV dial plus lower exposure wheels; system typography; amber-on-charcoal semantic palette; aperture-ring app icon |
| Filter compensation | 0 to +10 stops only, at selected stop increment; intended for light-reducing filters |
| Exposure-control default | ISO 100 locked, f/5.6 initial aperture; wheel interaction automatically enters Hold from Live |
| Snapshot transaction | Save reading first; thumbnail only after successful Photos save; deleting history never deletes Photos image |
| Privacy wording | No app network/cloud sync; opt-in Photos snapshots follow the user’s Photos/iCloud settings |
| Meter performance | 10 Hz analysis/UI cap; stable after three samples over 300 ms within ±0.1 EV; lifecycle and thermal handling required |
| Exposure tables | Canonical full/half/third-stop series generated from exact stop math; conventional display notation; tested tie-breaking |
| Orientation | Portrait-first UI; preview, capture, and Spot coordinate conversion remain orientation-correct |
| History retention | No automatic deletion; 320-point/80 KB thumbnails; Review History notice at 500 records or 40 MB |
| Photos permission | Add-only access requested only after snapshot confirmation; app never browses the Photos library |
| Distribution | Local Xcode development → limited TestFlight beta → App Store after validation; public Apache-2.0 repository |

## 13. Implementation validation before coding

No product decisions remain open. Validate the approved visual system with the fake-data screen and DEBUG Test Meter states before connecting it to the camera pipeline.
