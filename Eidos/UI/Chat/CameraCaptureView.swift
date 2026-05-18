import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Presents the system camera and hands back the captured photo as
/// a `CGImage` to the caller. Videos are out of scope — we disable
/// video on the picker and accept still frames only.
///
/// The camera is available only on physical iOS devices; on Mac
/// Catalyst and simulator, the view renders a short error message
/// and lets the caller fall back to the photo picker.
struct CameraCaptureView: View {
    let onCaptured: (CGImage) -> Void
    let onCancelled: () -> Void

    var body: some View {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !targetEnvironment(simulator)
        CameraPickerRepresentable(
            onCaptured: onCaptured,
            onCancelled: onCancelled
        )
        .ignoresSafeArea()
        #else
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera not available here")
                .font(.title3.bold())
            Text("The camera is only available on a physical iPhone. Try the photo picker instead.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Cancel") { onCancelled() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        #endif
    }
}

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !targetEnvironment(simulator)

/// UIKit bridge for `UIImagePickerController` — still-photo only.
/// Videos are disabled in the configuration, so the picker returns
/// only `UIImagePickerController.InfoKey.originalImage`.
struct CameraPickerRepresentable: UIViewControllerRepresentable {
    let onCaptured: (CGImage) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerRepresentable
        init(_ parent: CameraPickerRepresentable) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let ui = info[.originalImage] as? UIImage, let cg = ui.cgImage {
                parent.onCaptured(cg)
            } else {
                parent.onCancelled()
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancelled()
            picker.dismiss(animated: true)
        }
    }
}

#endif
