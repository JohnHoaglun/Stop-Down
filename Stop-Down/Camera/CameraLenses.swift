import AVFoundation
import Foundation

/// One selectable camera lens (spec FR-1). Only lenses supplied by the
/// current device are exposed; the back position is used for metering.
///
/// `nonisolated`: a pure value. `AVCaptureDevice.DeviceType` is a Sendable
/// struct, so it is safe to share across actors.
nonisolated public struct CameraLens: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let deviceType: AVCaptureDevice.DeviceType

    public init(id: String, displayName: String, deviceType: AVCaptureDevice.DeviceType) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
    }
}

/// Discovers the back-camera lenses the current device supplies (spec FR-1).
nonisolated public enum CameraLensCatalog {

    /// The back lenses available on this device, in display order:
    /// Ultra Wide, Wide, Tele.
    public static func availableLenses() -> [CameraLens] {
        let candidates: [(type: AVCaptureDevice.DeviceType, id: String, name: String, rank: Int)] = [
            (.builtInUltraWideCamera, "ultrawide", "Ultra Wide", 0),
            (.builtInWideAngleCamera, "wide", "Wide", 1),
            (.builtInTelephotoCamera, "tele", "Tele", 2)
        ]
        var found: [CameraLens] = []
        for candidate in candidates {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [candidate.type],
                mediaType: .video,
                position: .back
            )
            guard !discovery.devices.isEmpty else { continue }
            found.append(CameraLens(id: candidate.id, displayName: candidate.name, deviceType: candidate.type))
        }
        return found
    }

    /// The preferred default lens: the back wide camera (spec FR-1).
    public static func preferredLens(_ lenses: [CameraLens]) -> CameraLens? {
        lenses.first(where: { $0.id == "wide" }) ?? lenses.first
    }
}
