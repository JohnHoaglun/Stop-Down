import AVFoundation
import Testing

@testable import Stop_Down

/// Pure logic for the lens default (spec FR-1: prefer the back wide camera).
/// Hardware discovery itself is exercised on-device, not in unit tests.
struct CameraLensCatalogTests {

    @Test
    func preferredLensIsWideWhenPresent() {
        let lenses = [
            CameraLens(id: "ultrawide", displayName: "Ultra Wide", deviceType: .builtInUltraWideCamera),
            CameraLens(id: "wide", displayName: "Wide", deviceType: .builtInWideAngleCamera),
            CameraLens(id: "tele", displayName: "Tele", deviceType: .builtInTelephotoCamera)
        ]
        #expect(CameraLensCatalog.preferredLens(lenses)?.id == "wide")
    }

    @Test
    func preferredLensFallsBackToFirst() {
        let onlyTele = [
            CameraLens(id: "tele", displayName: "Tele", deviceType: .builtInTelephotoCamera)
        ]
        #expect(CameraLensCatalog.preferredLens(onlyTele)?.id == "tele")
        #expect(CameraLensCatalog.preferredLens([]) == nil)
    }
}
