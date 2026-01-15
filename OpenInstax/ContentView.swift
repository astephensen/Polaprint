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
    @State private var orientation: InstaxOrientation = .portrait
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

            // Orientation picker
            Picker("", selection: $orientation) {
                ForEach(InstaxOrientation.standardOrientations, id: \.self) { orientation in
                    Text(orientation.displayName).tag(orientation)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

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
            try await printerManager.print(image: processedImage, orientation: orientation)
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
        // Apply the scale and offset transformations to create the final image
        let model = printerManager.printerModel

        let targetWidth: Int
        let targetHeight: Int

        switch orientation {
        case .portrait, .portraitFlipped:
            targetWidth = model.imageWidth
            targetHeight = model.imageHeight
        case .landscape, .landscapeFlipped:
            targetWidth = model.imageHeight
            targetHeight = model.imageWidth
        }

        let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)

        // Calculate the scaled image size to fill the target (same logic as preview)
        var baseWidth: CGFloat
        var baseHeight: CGFloat

        if imageAspect > targetAspect {
            baseHeight = CGFloat(targetHeight)
            baseWidth = baseHeight * imageAspect
        } else {
            baseWidth = CGFloat(targetWidth)
            baseHeight = baseWidth / imageAspect
        }

        // Apply user's scale
        let scaledWidth = baseWidth * scale
        let scaledHeight = baseHeight * scale

        // Convert offset from preview coordinates to print coordinates
        // The offset is in screen points relative to the preview frame
        // We need to scale it proportionally to the print size
        let scaleFactorX = CGFloat(targetWidth) / max(previewFrameSize.width, 1)
        let scaleFactorY = CGFloat(targetHeight) / max(previewFrameSize.height, 1)

        let printOffsetX = offset.width * scaleFactorX
        let printOffsetY = offset.height * scaleFactorY

        // Calculate final position (centered + user offset)
        let offsetX = (CGFloat(targetWidth) - scaledWidth) / 2 + printOffsetX
        let offsetY = (CGFloat(targetHeight) - scaledHeight) / 2 + printOffsetY

        // Create the output context
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        // Fill with white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // Draw the image with transformations
        // Note: Core Graphics has origin at bottom-left, so we flip Y offset
        let drawRect = CGRect(
            x: offsetX,
            y: CGFloat(targetHeight) - offsetY - scaledHeight,
            width: scaledWidth,
            height: scaledHeight
        )
        context.draw(image, in: drawRect)

        return context.makeImage() ?? image
    }
}

#Preview {
    ContentView()
}
