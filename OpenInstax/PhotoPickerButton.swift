import SwiftUI
import PhotosUI
import CoreGraphics

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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Apply EXIF orientation
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: orientationValue) else {
            return cgImage
        }

        return applyOrientation(to: cgImage, orientation: orientation)
    }

    private func applyOrientation(to image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard orientation != .up else { return image }

        let width = image.width
        let height = image.height

        var transform = CGAffineTransform.identity
        var newWidth = width
        var newHeight = height

        switch orientation {
        case .up:
            return image
        case .upMirrored:
            transform = transform.translatedBy(x: CGFloat(width), y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .down:
            transform = transform.translatedBy(x: CGFloat(width), y: CGFloat(height))
            transform = transform.rotated(by: .pi)
        case .downMirrored:
            transform = transform.translatedBy(x: 0, y: CGFloat(height))
            transform = transform.scaledBy(x: 1, y: -1)
        case .leftMirrored:
            newWidth = height
            newHeight = width
            transform = transform.translatedBy(x: CGFloat(height), y: CGFloat(width))
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: 3 * .pi / 2)
        case .right:
            newWidth = height
            newHeight = width
            transform = transform.translatedBy(x: CGFloat(height), y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .rightMirrored:
            newWidth = height
            newHeight = width
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: .pi / 2)
        case .left:
            newWidth = height
            newHeight = width
            transform = transform.translatedBy(x: 0, y: CGFloat(width))
            transform = transform.rotated(by: 3 * .pi / 2)
        }

        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            return image
        }

        context.concatenate(transform)

        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(image, in: CGRect(x: 0, y: 0, width: height, height: width))
        default:
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return context.makeImage()
    }
}
