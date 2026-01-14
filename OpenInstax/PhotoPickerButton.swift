import SwiftUI
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PhotoPickerButton: View {
    @Binding var selectedImage: CGImage?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
        }
        .buttonStyle(.borderedProminent)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else {
            selectedImage = nil
            return
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImage = createCGImage(from: data)
            }
        } catch {
            print("Failed to load image: \(error)")
            selectedImage = nil
        }
    }

    private func createCGImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        // Draw to bitmap context to ensure correct orientation
        let width = Int(nsImage.size.width)
        let height = Int(nsImage.size.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        nsImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        // Draw to bitmap context to apply orientation
        let size = uiImage.size
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage?.cgImage
        #endif
    }
}
