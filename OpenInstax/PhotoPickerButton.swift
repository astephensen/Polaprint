import SwiftUI
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PhotoPickerButton: View {
    @Binding var selectedImage: CGImage?
    @Binding var fullResolutionData: Data?
    @Binding var isLoading: Bool
    @State private var selectedItem: PhotosPickerItem?

    private let maxPreviewSize: CGFloat = 1500

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                selectedImage = nil
                fullResolutionData = nil
            }
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Process on background thread
                let preview = await Task.detached(priority: .userInitiated) { [self] in
                    self.createPreviewImage(from: data)
                }.value

                await MainActor.run {
                    fullResolutionData = data
                    selectedImage = preview
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            print("Failed to load image: \(error)")
            await MainActor.run {
                selectedImage = nil
                fullResolutionData = nil
                isLoading = false
            }
        }
    }

    private nonisolated func createPreviewImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        let originalSize = nsImage.size

        // Calculate preview size
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

        // Calculate preview size
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
