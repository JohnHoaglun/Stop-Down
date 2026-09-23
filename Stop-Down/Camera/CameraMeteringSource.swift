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
public final class CameraMeteringSource: MeteringSource {

    public private(set) var isAvailable = false
    public private(set) var availabilityNote: String?
    public var onSample: (@MainActor (MeterSample) -> Void)?
    public var onAvailability: (@MainActor (_ available: Bool, _ note: String?) -> Void)?

    /// The metering context last applied to the camera.
    private var activeMode: MeteringMode = .centerWeighted
    private var activeSpot: NormalizedPoint?

    private let coordinator = CameraFrameCoordinator()
    private var device: AVCaptureDevice?
    private var sessionRequested = false
    private var permissionPending = false
    private var authorizationObserver: NSObjectProtocol?

    public init() {
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
        coordinator.start(mode: activeMode, spotPoint: activeSpot)
    }

    public func stop() {
        sessionRequested = false
        permissionPending = false
        coordinator.stop()
    }

    /// Apply the metering context: in Spot mode the normalized point becomes
    /// the camera's exposure point of interest; Average re-centers it
    /// (spec FR-3, §4.3).
    public func applyConfiguration(_ configuration: MeterConfiguration) {
        let spot = configuration.mode == .spot ? configuration.spotPoint?.clamped() : nil
        guard spot != activeSpot || configuration.mode != activeMode else { return }
        activeMode = configuration.mode
        activeSpot = spot
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

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "stop-down.camera.session")
    private let analysisQueue = DispatchQueue(label: "stop-down.camera.analysis")
    private var device: AVCaptureDevice?
    private let meteringLock = NSLock()
    private var meteringMode: MeteringMode = .centerWeighted
    private var meteringSpot: NormalizedPoint?
    private var lastEmit = Date.distantPast
    /// Emit at most ~10 Hz, matching the engine's rate cap (spec FR-8).
    private let emitInterval: TimeInterval = 0.1

    func start(mode: MeteringMode, spotPoint: NormalizedPoint?) {
        sessionQueue.async {
            guard !self.session.isRunning else {
                self.applyMetering(mode: mode, spotPoint: spotPoint)
                return
            }
            // Re-fetch on the session queue rather than capturing the device
            // across the queue boundary (AVCaptureDevice is not Sendable).
            guard let device = AVCaptureDevice.default(for: .video) else { return }
            self.device = device
            self.session.beginConfiguration()
            // Luma statistics only — the smallest preset keeps the frame
            // pipeline cheap (no preview is shown in this milestone).
            self.session.sessionPreset = .vga640x480
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
            self.applyMetering(mode: mode, spotPoint: spotPoint)
            self.session.startRunning()
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
    /// v1 is portrait-first and passes the normalized UI point through; when
    /// the live preview lands, screen→capture-space conversion is resolved
    /// there (spec FR-3, orientation).
    func applyMetering(mode: MeteringMode, spotPoint: NormalizedPoint?) {
        sessionQueue.async {
            guard let device = self.device else { return }
            self.meteringLock.lock()
            self.meteringMode = mode
            self.meteringSpot = spotPoint
            self.meteringLock.unlock()
            let target: CGPoint
            if let spot = spotPoint {
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
            let mode = device.exposureMode
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            defer { device.unlockForConfiguration() }
            device.exposurePointOfInterest = target
            device.exposureMode = mode
        }
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
