import SwiftUI
import UIKit
import AxyomRemoteCore

/// Shrinks a photo to what an agent needs (longest side 1024 px, JPEG), the
/// same limits as the desktop's own iOS client, so a reply stays small.
enum ImageShrink {
    static let maxSide: CGFloat = 1024

    static func prompt(from image: UIImage, name: String) -> PromptImage? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.75
        guard var data = resized.jpegData(compressionQuality: quality) else { return nil }
        while data.count > 900_000 && quality > 0.3 {
            quality -= 0.15
            if let smaller = resized.jpegData(compressionQuality: quality) { data = smaller }
        }
        return PromptImage(filename: name, mimeType: "image/jpeg", data: data, width: Int(target.width), height: Int(target.height))
    }
}

/// The iPhone camera, for "Tirar foto".
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Thumbnails of the images about to be sent, each with an x to remove it.
struct AttachmentTray: View {
    @Binding var images: [PromptImage]

    var body: some View {
        if !images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images) { img in
                        ZStack(alignment: .topTrailing) {
                            if let ui = UIImage(data: img.data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Button { images.removeAll { $0.id == img.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Theme.text, Theme.background)
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Tirar imagem")
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }
}
