import SwiftUI
import InstaxKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @State private var printerManager = PrinterManager()
    @State private var selectedImage: CGImage?
    @State private var fullResolutionImageData: Data?
    @State private var isLoadingImage: Bool = false
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var orientation: Orientation = .portrait
    @State private var previewFrameSize: CGSize = .zero
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Printer status bar at top
            HStack {
                PrinterStatusView(
                    connectionState: printerManager.connectionState,
                    printProgress: printerManager.printProgress
                )

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Main content area
            if let image = selectedImage {
                // Image editor
                ImageEditorView(
                    image: image,
                    printerModel: printerManager.printerModel,
                    scale: $scale,
                    offset: $offset,
                    orientation: $orientation,
                    frameSize: $previewFrameSize
                )
                .overlay {
                    if printerManager.isPrinting, let progress = printerManager.printProgress {
                        PrintProgressOverlay(progress: progress)
                    }
                }
            } else if isLoadingImage {
                // Loading state
                loadingView
            } else {
                // Empty state
                emptyStateView
            }

            Divider()

            // Bottom toolbar
            bottomToolbar
                .padding()
        }
        .onAppear {
            printerManager.startMonitoring()
        }
        .onDisappear {
            printerManager.stopMonitoring()
        }
        .alert("Print Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                printerManager.applySettings()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Select a photo to print")
                .font(.title2)
                .foregroundStyle(.secondary)

            ImageSourcePicker(
                selectedImage: $selectedImage,
                fullResolutionData: $fullResolutionImageData,
                isLoading: $isLoadingImage
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading image...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomToolbar: some View {
        HStack {
            // Photo picker
            ImageSourcePicker(
                selectedImage: $selectedImage,
                fullResolutionData: $fullResolutionImageData,
                isLoading: $isLoadingImage
            )

            Spacer()

            // Print button
            Button {
                Task {
                    await printPhoto()
                }
            } label: {
                Label("Print", systemImage: "printer.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!canPrint)
        }
    }

    private var canPrint: Bool {
        guard selectedImage != nil else { return false }
        guard !printerManager.isPrinting else { return false }
        guard case .connected = printerManager.connectionState else { return false }
        return true
    }

    private func printPhoto() async {
        guard let imageData = fullResolutionImageData,
              let fullImage = createFullResolutionImage(from: imageData) else { return }

        do {
            let processedImage = processImageForPrint(fullImage)
            try await printerManager.print(image: processedImage)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private nonisolated func createFullResolutionImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
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
        let size = uiImage.size
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage?.cgImage
        #endif
    }

    private func processImageForPrint(_ image: CGImage) -> CGImage {
        let model = printerManager.printerModel

        // For landscape orientations, crop to swapped dimensions
        let cropWidth: Int
        let cropHeight: Int
        if orientation.isLandscape {
            cropWidth = model.imageHeight
            cropHeight = model.imageWidth
        } else {
            cropWidth = model.imageWidth
            cropHeight = model.imageHeight
        }

        let targetAspect = CGFloat(cropWidth) / CGFloat(cropHeight)
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)

        // Calculate the scaled image size to fill the target
        var baseWidth: CGFloat
        var baseHeight: CGFloat

        if imageAspect > targetAspect {
            baseHeight = CGFloat(cropHeight)
            baseWidth = baseHeight * imageAspect
        } else {
            baseWidth = CGFloat(cropWidth)
            baseHeight = baseWidth / imageAspect
        }

        // Apply user's scale
        let scaledWidth = baseWidth * scale
        let scaledHeight = baseHeight * scale

        // Convert offset from preview coordinates to print coordinates
        let scaleFactorX = CGFloat(cropWidth) / max(previewFrameSize.width, 1)
        let scaleFactorY = CGFloat(cropHeight) / max(previewFrameSize.height, 1)

        let printOffsetX = offset.width * scaleFactorX
        let printOffsetY = offset.height * scaleFactorY

        // Calculate final position (centered + user offset)
        let offsetX = (CGFloat(cropWidth) - scaledWidth) / 2 + printOffsetX
        let offsetY = (CGFloat(cropHeight) - scaledHeight) / 2 + printOffsetY

        // Create the output context for cropping
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: cropWidth,
                height: cropHeight,
                bitsPerComponent: 8,
                bytesPerRow: cropWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        // Fill with white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))

        // Draw the image
        let drawRect = CGRect(
            x: offsetX,
            y: CGFloat(cropHeight) - offsetY - scaledHeight,
            width: scaledWidth,
            height: scaledHeight
        )
        context.draw(image, in: drawRect)

        guard let croppedImage = context.makeImage() else {
            return image
        }

        // Apply rotation based on orientation
        switch orientation {
        case .portrait:
            return croppedImage
        case .landscape:
            return rotateImage(croppedImage, degrees: 90) ?? croppedImage
        case .portraitFlipped:
            return rotateImage(croppedImage, degrees: 180) ?? croppedImage
        case .landscapeFlipped:
            return rotateImage(croppedImage, degrees: 270) ?? croppedImage
        }
    }

    /// Rotate image by specified degrees clockwise
    private func rotateImage(_ image: CGImage, degrees: Int) -> CGImage? {
        let radians = CGFloat(degrees) * .pi / 180

        // For 90 and 270, swap dimensions
        let width: Int
        let height: Int
        if degrees == 90 || degrees == 270 {
            width = image.height
            height = image.width
        } else {
            width = image.width
            height = image.height
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        // Apply appropriate transform for each rotation
        switch degrees {
        case 90:
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: radians)
        case 180:
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: radians)
        case 270:
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: radians)
        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

#Preview {
    ContentView()
}
