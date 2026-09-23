import CoreGraphics
import Foundation

/// Pure screen↔capture coordinate conversion for the Spot point of interest
/// (spec FR-3, §4.2, orientation).
///
/// `exposurePointOfInterest` is expressed in the capture buffer's unit square
/// (sensor orientation: landscape, top-left origin). The preview displays that
/// buffer rotated 90° clockwise in portrait, aspect-filled into the view. A
/// tap must be mapped into buffer space so the camera's point of interest and
/// the luma spot box both land where the user pointed (and the reticle can be
/// drawn back at the same screen location).
///
/// `nonisolated`: pure math shared by the UI and the frame coordinator.
nonisolated public enum SpotPointConverter {

    /// How the capture buffer is rotated to produce the portrait preview.
    public enum Rotation {
        /// Back camera in portrait: buffer rotated 90° clockwise.
        case right
    }

    /// Map a point in the preview view (0...1, top-left origin) to the capture
    /// buffer's unit square (top-left origin, sensor orientation).
    ///
    /// - Parameters:
    ///   - viewPoint: Tap position normalized to the preview view.
    ///   - viewSize: Preview view size in points.
    ///   - bufferSize: Capture buffer size in pixels (sensor orientation).
    ///   - rotation: Buffer→preview rotation (back camera portrait: `.right`).
    public static func bufferPoint(
        viewPoint: CGPoint,
        viewSize: CGSize,
        bufferSize: CGSize,
        rotation: Rotation = .right
    ) -> NormalizedPoint {
        guard viewSize.width > 0, viewSize.height > 0,
              bufferSize.width > 0, bufferSize.height > 0 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        let fill = fillScale(viewSize: viewSize, displaySize: displaySize(bufferSize, rotation: rotation))
        // View point → position in the displayed (rotated) buffer image.
        let cropX = (displaySize(bufferSize, rotation: rotation).width * fill - viewSize.width) / 2
        let cropY = (displaySize(bufferSize, rotation: rotation).height * fill - viewSize.height) / 2
        let rx = (viewPoint.x * viewSize.width + cropX) / fill / displaySize(bufferSize, rotation: rotation).width
        let ry = (viewPoint.y * viewSize.height + cropY) / fill / displaySize(bufferSize, rotation: rotation).height
        switch rotation {
        case .right:
            // 90° clockwise: display (x, y) = (1 − v, u) ⇒ u = y, v = 1 − x.
            return NormalizedPoint(x: ry, y: 1 - rx).clamped()
        }
    }

    /// Map a capture-buffer point (the stored `spotPoint`) back to the preview
    /// view, for drawing the reticle exactly where it meters (spec §4.2).
    public static func viewPoint(
        bufferPoint: NormalizedPoint,
        viewSize: CGSize,
        bufferSize: CGSize,
        rotation: Rotation = .right
    ) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0,
              bufferSize.width > 0, bufferSize.height > 0 else {
            return CGPoint(x: 0.5 * viewSize.width, y: 0.5 * viewSize.height)
        }
        let rx: Double
        let ry: Double
        switch rotation {
        case .right:
            rx = 1 - bufferPoint.y
            ry = bufferPoint.x
        }
        let fill = fillScale(viewSize: viewSize, displaySize: displaySize(bufferSize, rotation: rotation))
        let cropX = (displaySize(bufferSize, rotation: rotation).width * fill - viewSize.width) / 2
        let cropY = (displaySize(bufferSize, rotation: rotation).height * fill - viewSize.height) / 2
        let x = max(0, min(1, (rx * displaySize(bufferSize, rotation: rotation).width * fill - cropX) / viewSize.width))
        let y = max(0, min(1, (ry * displaySize(bufferSize, rotation: rotation).height * fill - cropY) / viewSize.height))
        return CGPoint(x: x * viewSize.width, y: y * viewSize.height)
    }

    /// The preview buffer's dimensions when displayed (portrait) for a
    /// sensor-orientation buffer under the given rotation.
    private static func displaySize(_ bufferSize: CGSize, rotation: Rotation) -> CGSize {
        switch rotation {
        case .right:
            CGSize(width: bufferSize.height, height: bufferSize.width)
        }
    }

    /// `.resizeAspectFill` scale between the displayed buffer and the view.
    private static func fillScale(viewSize: CGSize, displaySize: CGSize) -> CGFloat {
        max(viewSize.width / displaySize.width, viewSize.height / displaySize.height)
    }
}
