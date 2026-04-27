import Foundation
import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Errors that `VisionCaptureService` can surface.
enum VisionCaptureError: Error, LocalizedError {
    case cameraUnavailable
    case decodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "The camera isn't available on this device."
        case .decodingFailed: "Couldn't decode the selected image."
        case .cancelled: "Image selection was cancelled."
        }
    }

    var failureCategory: FailureCategory {
        switch self {
        case .cameraUnavailable: .cameraAccessFailed
        case .decodingFailed: .cameraAccessFailed
        case .cancelled: .permissionDenied
        }
    }
}

/// Picks an image from the user — camera, photo library, or a
/// screenshot of Eidos's own UI for meta queries.
///
/// Returns a lightweight `CGImage` to the caller; we deliberately avoid
/// keeping an owning reference so the image can be garbage-collected as
/// soon as Gemma's generation finishes.
@MainActor
@Observable
final class VisionCaptureService {

    /// Whether the device has a camera. Set once at init.
    let cameraAvailable: Bool

    init() {
        #if targetEnvironment(simulator)
        self.cameraAvailable = false
        #elseif canImport(UIKit)
        self.cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        self.cameraAvailable = false
        #endif
    }

    /// Returns the first image from the user's selection in the photo
    /// library, or throws `.cancelled` if they dismiss without picking.
    ///
    /// The `selection` is an array of `PhotosPickerItem` that SwiftUI's
    /// `PhotosPicker` hands back. We decode the first one.
    func loadImage(from selection: [PhotosPickerItem]) async throws -> CGImage {
        guard let first = selection.first else {
            throw VisionCaptureError.cancelled
        }
        guard let data = try? await first.loadTransferable(type: Data.self) else {
            throw VisionCaptureError.decodingFailed
        }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let cg = uiImage.cgImage else {
            throw VisionCaptureError.decodingFailed
        }
        EidosLogger.shared.metric(.ui, event: "vision.capture.photos", values: [
            "bytes": data.count,
            "width": cg.width,
            "height": cg.height,
        ])
        return cg
        #else
        throw VisionCaptureError.decodingFailed
        #endif
    }

    /// Convenience: decode raw image data (e.g. from the camera, share
    /// extension, or clipboard).
    func decode(data: Data) throws -> CGImage {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data), let cg = ui.cgImage else {
            throw VisionCaptureError.decodingFailed
        }
        return cg
        #else
        throw VisionCaptureError.decodingFailed
        #endif
    }

    // MARK: - Downsampling

    /// Max dimension (longer edge) we hand to Gemma 4's vision pipeline.
    /// Matches the upper supported visual-token budget — past this, each
    /// extra pixel is wasted compute and heat.
    ///
    /// iPhone: 1024 — tighter thermal envelope, shorter context.
    /// iPad / Mac: 1568 — headroom to spare.
    ///
    /// `nonisolated` so non-MainActor callers (Gemma's generation path
    /// runs in an actor) can read it without hopping.
    nonisolated static var maxSideForGemma: Int {
        #if targetEnvironment(macCatalyst)
        return 1568
        #elseif os(iOS)
        return 1024
        #else
        return 1568
        #endif
    }

    /// Resizes `cg` so its longer edge ≤ `maxSide`, preserving aspect ratio.
    /// Returns the original image unchanged if already within the cap.
    /// Used before passing images to Gemma to avoid hammering the GPU
    /// with 12-megapixel camera captures.
    nonisolated static func downsample(_ cg: CGImage, maxSide: Int = maxSideForGemma) -> CGImage {
        let longest = max(cg.width, cg.height)
        guard longest > maxSide else { return cg }

        let scale = Double(maxSide) / Double(longest)
        let newW = Int(Double(cg.width) * scale)
        let newH = Int(Double(cg.height) * scale)

        let colorSpace = cg.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cg }

        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? cg
    }
}
