import SwiftUI
import InstaxKit

struct ContentView: View {
    @State private var printerManager = PrinterManager()
    @State private var selectedImage: CGImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var orientation: PrintOrientation = .portrait
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Printer status bar at top
            PrinterStatusView(
                connectionState: printerManager.connectionState,
                printProgress: printerManager.printProgress
            )
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
                    orientation: $orientation
                )
                .overlay {
                    if printerManager.isPrinting, let progress = printerManager.printProgress {
                        PrintProgressOverlay(progress: progress)
                    }
                }
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

            PhotoPickerButton(selectedImage: $selectedImage)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomToolbar: some View {
        HStack {
            // Photo picker
            PhotoPickerButton(selectedImage: $selectedImage)

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
        guard let image = selectedImage else { return }

        do {
            let processedImage = processImageForPrint(image)
            try await printerManager.print(image: processedImage, rotation: orientation.rotation)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func processImageForPrint(_ image: CGImage) -> CGImage {
        // Apply the scale and offset transformations to create the final image
        guard let model = printerManager.printerModel else { return image }

        let targetWidth: Int
        let targetHeight: Int

        switch orientation {
        case .portrait:
            targetWidth = model.imageWidth
            targetHeight = model.imageHeight
        case .landscape:
            targetWidth = model.imageHeight
            targetHeight = model.imageWidth
        }

        let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)

        // Calculate the scaled image size to fill the target
        var scaledWidth: CGFloat
        var scaledHeight: CGFloat

        if imageAspect > targetAspect {
            scaledHeight = CGFloat(targetHeight)
            scaledWidth = scaledHeight * imageAspect
        } else {
            scaledWidth = CGFloat(targetWidth)
            scaledHeight = scaledWidth / imageAspect
        }

        // Apply user's scale
        scaledWidth *= scale
        scaledHeight *= scale

        // Calculate offset in image coordinates
        let offsetX = (CGFloat(targetWidth) - scaledWidth) / 2 + (offset.width / 300 * CGFloat(targetWidth))
        let offsetY = (CGFloat(targetHeight) - scaledHeight) / 2 + (offset.height / 300 * CGFloat(targetHeight))

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
