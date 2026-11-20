import CloudKit
import SwiftUI

struct Invitation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

struct Sharing: UIViewControllerRepresentable {
    var invitation: Invitation
    var finished: () -> Void
    var failed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let vc = UICloudSharingController(share: invitation.share, container: invitation.container)
        vc.availablePermissions = [.allowPrivate, .allowReadOnly]
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: Sharing
        init(parent: Sharing) { self.parent = parent }
        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.invitation.share[CKShare.SystemFieldKey.title] as? String
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { parent.finished() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { parent.finished() }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            parent.failed(error.localizedDescription)
        }
    }
}

struct Camera: UIViewControllerRepresentable {
    var result: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(result: result) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var result: (Data?) -> Void
        init(result: @escaping (Data?) -> Void) { self.result = result }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { result(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            result((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.94))
        }
    }
}
