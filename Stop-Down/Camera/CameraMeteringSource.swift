import AVFoundation
import CoreVideo
import Foundation
import UIKit

/// The real metering feed (spec Phase 2c): the back camera's native
/// auto-exposure metadata is the EV authority; per-frame luma analysis is
/// confidence-only (spec FR-2).
///
/// All session work happens off the main thread (dedicated serial queues);
/// samples are delivered to the main actor through `onSample`, keeping the
/// `MeteringSource` seam intact. Permission state is surfaced through
/// `isAvailable` / `onAvailability` so the UI can offer recovery (spec FR-7).
@MainActor
public final class CameraMeteringSource: MeteringSource, PreviewProviding, LensProviding {

    public private(set) var isAvailable = false
    public private(set) var availabilityNote: String?
    public var onSample: (@MainActor (MeterSample) -> Void)?
    public var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)?

    /// The lenses this device supplies (spec FR-1: expose only what the
    /// current device provides), in display order.
    public private(set) var availableLenses: [CameraLens]
    /// The display name of the lens the session currently uses (spec FR-1).
    public private(set) var selectedLensName: String
    /// The session the preview layer should render (spec §4.7).
    public var previewSession: AVCaptureSession { coordinator.session }
    /// Nominal session buffer size (sensor orientation) for Spot-space math.
    public var previewBufferSize: CGSize { CameraFrameCoordinator.previewBufferSize }
    public var availableLensNames: [String] { availableLenses.map(\.displayName) }

    /// The metering context last applied to the camera.
    private var activeMode: MeteringMode = .centerWeighted
    private var activeSpot: NormalizedPoint?
    private var selectedLensID: String

    private let coordinator = CameraFrameCoordinator()
    private var device: AVCaptureDevice?
    private var sessionRequested = false
    private var permissionPending = false
    private var authorizationObserver: NSObjectProtocol?

    public init() {
        let lenses = CameraLensCatalog.availableLenses()
        let preferred = CameraLensCatalog.preferredLens(lenses)
        availableLenses = lenses
        selectedLensID = preferred?.id ?? "wide"
        selectedLensName = preferred?.displayName ?? "Wide"
        coordinator.onSample = { [weak self] sample in
            Task { @MainActor [weak self] in
                self?.onSample?(sample)
            }
        }
        // The iOS 27 SDK removed the dedicated authorization notification, so
        // re-sync whenever the app becomes active (covers the "Open Settings,
        // enable the camera, come back" recovery flow, spec FR-7).
        authorizationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncAvailability()
                if self.isAvailable {
                    self.start()
                } else {
                    self.stop()
                }
            }
        }
    }

    deinit {
        if let authorizationObserver {
            NotificationCenter.default.removeObserver(authorizationObserver)
        }
    }

    // MARK: MeteringSource

    public func start() {
        syncAvailability()
        guard isAvailable else { return }
        guard !sessionRequested else { return }
        sessionRequested = true
        let deviceType = availableLenses.first(where: { $0.id == selectedLensID })?.deviceType
            ?? .builtInWideAngleCamera
        coordinator.start(deviceType: deviceType, mode: activeMode, spotPoint: activeSpot)
    }

    public func stop() {
        sessionRequested = false
        permissionPending = false
        coordinator.stop()
    }

    /// Apply the metering context: in Spot mode the normalized point becomes
    /// the camera's exposure point of interest; Average re-centers it
    /// (spec FR-3, §4.3). A lens change reconfigures the session (spec FR-1);
    /// the engine separately resets its smoothing window on the same change.
    public func applyConfiguration(_ configuration: MeterConfiguration) {
        let spot = configuration.mode == .spot ? configuration.spotPoint?.clamped() : nil
        let lensChanged = configuration.lens != selectedLensName
        guard spot != activeSpot || configuration.mode != activeMode || lensChanged else { return }
        activeMode = configuration.mode
        activeSpot = spot
        if lensChanged {
            if let lens = availableLenses.first(where: { $0.displayName == configuration.lens }) {
                selectedLensID = lens.id
                selectedLensName = lens.displayName
                coordinator.setLens(lens.deviceType)
            }
            // An unknown lens name leaves the current lens untouched; the
            // engine still reset its smoothing window for the config change.
        }
        coordinator.applyMetering(mode: configuration.mode, spotPoint: spot)
    }

    // MARK: Availability

    /// Re-check camera authorization and update the published availability
    /// state. Requests access once when status is `.notDetermined`.
    private func syncAvailability() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var available = false
        var note: String?

        switch status {
        case .authorized:
            device = AVCaptureDevice.default(for: .video)
            available = device != nil
            note = available ? nil : "No camera is available on this device."
        case .notDetermined:
            note = "Camera access has not been allowed yet."
        case .denied, .restricted:
            note = "Camera access is off. Turn it on in Settings, then reopen Stop-Down."
        @unknown default:
            note = "Camera access is unavailable."
        }
        setAvailability(available, note: note)

        if status == .notDetermined && !permissionPending {
            permissionPending = true
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                self.permissionPending = false
                guard granted else {
                    self.syncAvailability()
                    return
                }
                self.syncAvailability()
                self.start()
            }
        }
    }

    private func setAvailability(_ available: Bool, note: String?) {
        isAvailable = available
        availabilityNote = available ? nil : note
        onAvailability?(available, available ? nil : note)
    }
}

// MARK: - Frame pipeline

/// Owns the `AVCaptureSession` and the per-frame pipeline.
///
/// Explicitly `nonisolated` (the app module defaults to `@MainActor`): session
/// mutation happens on `sessionQueue`, frame analysis on `analysisQueue`. It
/// never touches the main actor — it hands finished `MeterSample`s to the
/// source's callback, which hops over.
///
/// `@unchecked Sendable`: every mutable property is confined to a single
/// serial queue (`sessionQueue` or `analysisQueue`), except the metering
/// context, which is guarded by `meteringLock`.
nonisolated final class CameraFrameCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    /// Called (off-main) with each paced sample.
    var onSample: (@Sendable (MeterSample) -> Void)?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "stop-down.camera.session")
    private let analysisQueue = DispatchQueue(label: "stop-down.camera.analysis")
    private var device: AVCaptureDevice?
    private let meteringLock = NSLock()
    private var meteringMode: MeteringMode = .centerWeighted
    private var meteringSpot: NormalizedPoint?
    private var lastEmit = Date.distantPast
    /// Emit at most ~10 Hz, matching the engine's rate cap (spec FR-8).
    private let emitInterval: TimeInterval = 0.1

    /// The session preset drives both the preview and the data output, so the
    /// buffer aspect used for Spot-space math (spec FR-3) is the nominal
    /// 1920×1080 of this preset (sensor orientation).
    static let previewBufferSize = CGSize(width: 1920, height: 1080)

    func start(deviceType: AVCaptureDevice.DeviceType, mode: MeteringMode, spotPoint: NormalizedPoint?) {
        sessionQueue.async {
            guard !self.session.isRunning else {
                self.applyMeteringLocked(mode: mode, spotPoint: spotPoint)
                return
            }
            // Re-resolve on the session queue rather than capturing the device
            // across the queue boundary (AVCaptureDevice is not Sendable).
            // Falls back to the default back camera so metering never depends
            // on a specific lens being present (spec FR-1).
            let device = Self.backDevice(for: deviceType)
            guard let device else { return }
            self.device = device
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080
            if let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.analysisQueue)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }
            self.session.commitConfiguration()
            self.applyMeteringLocked(mode: mode, spotPoint: spotPoint)
            self.session.startRunning()
        }
    }

    /// Swap the active lens while the session runs (spec FR-1). No-op when the
    /// session is stopped — the next `start` receives the lens explicitly.
    func setLens(_ deviceType: AVCaptureDevice.DeviceType) {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.replaceInput(deviceType: deviceType)
        }
    }

    /// Resolve a back-position device of the requested type, falling back to
    /// the default back camera.
    private static func backDevice(for deviceType: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType],
            mediaType: .video,
            position: .back
        ).devices.first ?? AVCaptureDevice.default(for: .video)
    }

    /// Replace the video input with the requested lens, re-applying the
    /// metering point of interest to the new device. If the swap fails, the
    /// previous input is restored so the session keeps running (spec FR-1:
    /// lens switching reconfigures the session cleanly).
    private func replaceInput(deviceType: AVCaptureDevice.DeviceType) {
        guard let newDevice = Self.backDevice(for: deviceType),
              let previousInput = self.session.inputs.first as? AVCaptureDeviceInput,
              previousInput.device !== newDevice
        else { return }
        let previousDevice = previousInput.device
        self.session.beginConfiguration()
        self.session.removeInput(previousInput)
        if let input = try? AVCaptureDeviceInput(device: newDevice), self.session.canAddInput(input) {
            self.session.addInput(input)
            self.device = newDevice
        } else {
            self.session.addInput(previousInput)
        }
        self.session.commitConfiguration()
        if self.device !== previousDevice {
            // The exposure point of interest lives on the device, not the
            // session — re-apply it to whichever device won the swap.
            self.applyMeteringLocked()
        }
    }

    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.session.commitConfiguration()
            self.device = nil
        }
    }

    /// Position the camera's exposure point of interest (spec FR-3).
    ///
    /// The spot point is already in capture (buffer) space — the UI converts
    /// screen coordinates through `SpotPointConverter` before publishing it
    /// (spec FR-3, orientation).
    func applyMetering(mode: MeteringMode, spotPoint: NormalizedPoint?) {
        sessionQueue.async {
            self.applyMeteringLocked(mode: mode, spotPoint: spotPoint)
        }
    }

    /// Session-queue-only core of `applyMetering` (no hop), so a lens swap
    /// can re-apply the stored metering context to the new device in order.
    private func applyMeteringLocked(mode: MeteringMode? = nil, spotPoint: NormalizedPoint? = nil) {
        guard let device = self.device else { return }
        meteringLock.lock()
        if let mode { meteringMode = mode }
        if let spotPoint { meteringSpot = spotPoint }
        let currentSpot = meteringSpot
        meteringLock.unlock()
        let target: CGPoint
        if let spot = currentSpot {
            target = CGPoint(
                x: min(max(CGFloat(spot.x), 0), 1),
                y: min(max(CGFloat(spot.y), 0), 1)
            )
        } else {
            target = CGPoint(x: 0.5, y: 0.5)
        }
        guard device.isExposurePointOfInterestSupported else { return }
        let current = device.exposurePointOfInterest
        if abs(current.x - target.x) > 0.001 || abs(current.y - target.y) > 0.001 {
            // The header documents that setting the point of interest alone
            // does not apply it — the exposure mode must be (re)set.
            let exposureMode = device.exposureMode
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            defer { device.unlockForConfiguration() }
            device.exposurePointOfInterest = target
            device.exposureMode = exposureMode
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let device, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Pace emits at the engine's update rate (spec FR-8).
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= emitInterval else { return }
        lastEmit = now

        let duration = CMTimeGetSeconds(device.exposureDuration)
        let iso = Double(device.iso)
        let aperture = Self.currentAperture(device)
        meteringLock.lock()
        let mode = meteringMode
        let spot = meteringSpot
        meteringLock.unlock()
        let luma = LuminanceAnalyzer.analyze(pixelBuffer, mode: mode, spotPoint: spot)

        onSample?(MeterSample(
            timestamp: now,
            metadataISO: iso > 0 ? iso : nil,
            metadataExposureDuration: duration.isFinite && duration > 0 ? duration : nil,
            metadataAperture: (aperture ?? 0) > 0 ? aperture : nil,
            centerLuma: luma.hasLuma ? luma.centerLuma : nil,
            spotLuma: luma.spotLuma,
            clipping: luma.hasLuma ? luma.clipping : 0,
            noise: luma.hasLuma ? luma.noise : 0
        ))
    }

    /// Resolve the physical f-number of the active lens.
    ///
    /// Prefers the live `lensAperture` metadata, falls back to the active
    /// format's defaults (iOS 27+), and otherwise reports `nil` — never a
    /// fabricated aperture (an incomplete sample yields an honest
    /// "no reading" state, per the spec's "never fabricate" rule).
    private static func currentAperture(_ device: AVCaptureDevice) -> Double? {
        let live = Double(device.lensAperture)
        if live > 0 { return live }
        if #available(iOS 27.0, *) {
            let format = device.activeFormat
            if let recommended = format.recommendedLensApertureStops.first, recommended > 0 {
                return Double(recommended)
            }
            let fallback = Double(format.defaultLensAperture)
            if fallback > 0 { return fallback }
        }
        return nil
    }
}
