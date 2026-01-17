import PhotosUI
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ImageSourcePicker: View {
  @Binding var selectedImage: CGImage?
  @Binding var fullResolutionData: Data?
  @Binding var isLoading: Bool

  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var showFileImporter = false
  #if os(iOS)
    @State private var showCamera = false
    @State private var showPhotoPicker = false
  #endif

  private let maxPreviewSize: CGFloat = 1500

  var body: some View {
    #if os(macOS)
      macOSButtons
    #else
      iOSMenu
    #endif
  }

  #if os(macOS)
    private var macOSButtons: some View {
      HStack(spacing: 12) {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          Label("Photos", systemImage: "photo.on.rectangle.angled")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
        .onChange(of: selectedPhotoItem) { _, newItem in
          Task {
            await loadFromPhotoPicker(newItem)
          }
        }

        Button {
          showFileImporter = true
        } label: {
          Label("File", systemImage: "folder")
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
        .fileImporter(
          isPresented: $showFileImporter,
          allowedContentTypes: [.image],
          allowsMultipleSelection: false
        ) { result in
          Task {
            await handleFileImport(result)
          }
        }
      }
    }
  #endif

  #if os(iOS)
    private var iOSMenu: some View {
      Menu {
        Button {
          showCamera = true
        } label: {
          Label("Take Photo", systemImage: "camera")
        }

        Button {
          showPhotoPicker = true
        } label: {
          Label("Photo Library", systemImage: "photo.on.rectangle.angled")
        }

        Button {
          showFileImporter = true
        } label: {
          Label("Choose File", systemImage: "folder")
        }
      } label: {
        Label("Add Photo", systemImage: "plus.circle.fill")
          .font(.body.weight(.medium))
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoading)
      .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
      .onChange(of: selectedPhotoItem) { _, newItem in
        Task {
          await loadFromPhotoPicker(newItem)
        }
      }
      .fileImporter(
        isPresented: $showFileImporter,
        allowedContentTypes: [.image],
        allowsMultipleSelection: false
      ) { result in
        Task {
          await handleFileImport(result)
        }
      }
      .fullScreenCover(isPresented: $showCamera) {
        CameraView(
          selectedImage: $selectedImage,
          fullResolutionData: $fullResolutionData,
          isLoading: $isLoading
        )
      }
    }
  #endif

  private func loadFromPhotoPicker(_ item: PhotosPickerItem?) async {
    guard let item else { return }

    await MainActor.run {
      isLoading = true
    }

    do {
      if let data = try await item.loadTransferable(type: Data.self) {
        let preview = await Task.detached(priority: .userInitiated) { [self] in
          createPreviewImage(from: data)
        }.value

        await MainActor.run {
          fullResolutionData = data
          selectedImage = preview
          isLoading = false
          selectedPhotoItem = nil
        }
      } else {
        await MainActor.run {
          isLoading = false
        }
      }
    } catch {
      print("Failed to load image: \(error)")
      await MainActor.run {
        isLoading = false
      }
    }
  }

  private func handleFileImport(_ result: Result<[URL], Error>) async {
    await MainActor.run {
      isLoading = true
    }

    do {
      let urls = try result.get()
      guard let url = urls.first else {
        await MainActor.run { isLoading = false }
        return
      }

      let accessing = url.startAccessingSecurityScopedResource()
      defer {
        if accessing {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let data = try Data(contentsOf: url)
      let preview = await Task.detached(priority: .userInitiated) { [self] in
        createPreviewImage(from: data)
      }.value

      await MainActor.run {
        fullResolutionData = data
        selectedImage = preview
        isLoading = false
      }
    } catch {
      print("Failed to load file: \(error)")
      await MainActor.run {
        isLoading = false
      }
    }
  }

  private nonisolated func createPreviewImage(from data: Data) -> CGImage? {
    #if os(macOS)
      guard let nsImage = NSImage(data: data) else { return nil }
      let originalSize = nsImage.size

      let scale = min(maxPreviewSize / originalSize.width, maxPreviewSize / originalSize.height, 1.0)
      let previewWidth = Int(originalSize.width * scale)
      let previewHeight = Int(originalSize.height * scale)

      guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
              data: nil,
              width: previewWidth,
              height: previewHeight,
              bitsPerComponent: 8,
              bytesPerRow: previewWidth * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

      let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphicsContext
      nsImage.draw(in: CGRect(x: 0, y: 0, width: previewWidth, height: previewHeight))
      NSGraphicsContext.restoreGraphicsState()
      return context.makeImage()
    #else
      guard let uiImage = UIImage(data: data) else { return nil }
      let originalSize = uiImage.size

      let scale = min(maxPreviewSize / originalSize.width, maxPreviewSize / originalSize.height, 1.0)
      let previewSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

      UIGraphicsBeginImageContextWithOptions(previewSize, false, 1.0)
      uiImage.draw(in: CGRect(origin: .zero, size: previewSize))
      let previewImage = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      return previewImage?.cgImage
    #endif
  }
}

#if os(iOS)
  struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: CGImage?
    @Binding var fullResolutionData: Data?
    @Binding var isLoading: Bool
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = context.coordinator
      return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
      let parent: CameraView
      private let maxPreviewSize: CGFloat = 1500

      init(_ parent: CameraView) {
        self.parent = parent
      }

      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        parent.dismiss()

        guard let image = info[.originalImage] as? UIImage else { return }

        Task { @MainActor in
          parent.isLoading = true
        }

        Task.detached(priority: .userInitiated) {
          guard let data = image.jpegData(compressionQuality: 0.95) else {
            await MainActor.run {
              self.parent.isLoading = false
            }
            return
          }

          let preview = self.createPreviewImage(from: image)

          await MainActor.run {
            self.parent.fullResolutionData = data
            self.parent.selectedImage = preview
            self.parent.isLoading = false
          }
        }
      }

      func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        parent.dismiss()
      }

      private func createPreviewImage(from image: UIImage) -> CGImage? {
        let originalSize = image.size
        let scale = min(maxPreviewSize / originalSize.width, maxPreviewSize / originalSize.height, 1.0)
        let previewSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        UIGraphicsBeginImageContextWithOptions(previewSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: previewSize))
        let previewImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return previewImage?.cgImage
      }
    }
  }
#endif
