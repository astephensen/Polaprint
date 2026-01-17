import SwiftUI
import InstaxKit

/// Print orientation
enum Orientation: Int, CaseIterable {
    case portrait = 0
    case landscape = 90
    case portraitFlipped = 180
    case landscapeFlipped = 270

    /// Rotate clockwise by 90 degrees
    func rotatedCW() -> Orientation {
        switch self {
        case .portrait: .landscape
        case .landscape: .portraitFlipped
        case .portraitFlipped: .landscapeFlipped
        case .landscapeFlipped: .portrait
        }
    }

    /// Rotate counter-clockwise by 90 degrees
    func rotatedCCW() -> Orientation {
        switch self {
        case .portrait: .landscapeFlipped
        case .landscape: .portrait
        case .portraitFlipped: .landscape
        case .landscapeFlipped: .portraitFlipped
        }
    }

    /// Whether this is a landscape orientation
    var isLandscape: Bool {
        self == .landscape || self == .landscapeFlipped
    }
}

struct ImageEditorView: View {
    let image: CGImage
    let printerModel: PrinterModel
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var orientation: Orientation
    @Binding var frameSize: CGSize
    let onClearImage: () -> Void

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    // Polaroid border proportions (visual only - doesn't affect crop/print)
    private let thinBorderRatio: CGFloat = 0.02
    private let thickBorderRatio: CGFloat = 0.15

    /// Visual offset to align image with polaroid cutout (NOT stored, display only)
    private func visualAlignmentOffset(for frameSize: CGSize) -> CGSize {
        let thin = frameSize.height * thinBorderRatio
        let thick = frameSize.height * thickBorderRatio
        let diff = (thick - thin) / 2
        switch orientation {
        case .portrait:
            return CGSize(width: 0, height: -diff)
        case .landscape:
            return CGSize(width: diff, height: 0)
        case .portraitFlipped:
            return CGSize(width: 0, height: diff)
        case .landscapeFlipped:
            return CGSize(width: -diff, height: 0)
        }
    }

    private var cropAspectRatio: CGFloat {
        let width = CGFloat(printerModel.imageWidth)
        let height = CGFloat(printerModel.imageHeight)
        if orientation.isLandscape {
            return height / width
        } else {
            return width / height
        }
    }

    private var imageAspectRatio: CGFloat {
        CGFloat(image.width) / CGFloat(image.height)
    }

    var body: some View {
        GeometryReader { geometry in
            let calculatedFrameSize = calculateFrameSize(in: geometry.size)
            let imageSize = calculateImageSize(toFill: calculatedFrameSize)
            let visualOffset = visualAlignmentOffset(for: calculatedFrameSize)
            let thinBorder = calculatedFrameSize.height * thinBorderRatio
            let thickBorder = calculatedFrameSize.height * thickBorderRatio
            let polaroidSize = orientation.isLandscape
                ? CGSize(width: calculatedFrameSize.width + thinBorder + thickBorder,
                         height: calculatedFrameSize.height + thinBorder * 2)
                : CGSize(width: calculatedFrameSize.width + thinBorder * 2,
                         height: calculatedFrameSize.height + thinBorder + thickBorder)

            ZStack {
                // Image layer (can extend beyond bounds when zoomed)
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                    .offset(x: offset.width + visualOffset.width,
                            y: offset.height + visualOffset.height)

                // Polaroid frame and controls (fixed size)
                PolaroidFrameOverlay(
                    frameSize: calculatedFrameSize,
                    orientation: orientation,
                    thinBorder: thinBorder,
                    thickBorder: thickBorder,
                    onRotateCW: { orientation = orientation.rotatedCW() },
                    onRotateCCW: { orientation = orientation.rotatedCCW() },
                    onClearImage: onClearImage
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay {
                // Dark overlay with polaroid cutout - extends to screen edges
                // Use outer geometry's safe area insets to position cutout correctly
                let safeArea = geometry.safeAreaInsets
                let cutoutRect = CGRect(
                    x: safeArea.leading + geometry.size.width / 2 - polaroidSize.width / 2,
                    y: safeArea.top + geometry.size.height / 2 - polaroidSize.height / 2,
                    width: polaroidSize.width,
                    height: polaroidSize.height
                )
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.8)))
                    context.blendMode = .destinationOut
                    context.fill(Path(roundedRect: cutoutRect, cornerRadius: 4), with: .color(.white))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(frameSize: calculatedFrameSize, imageSize: imageSize))
            .gesture(magnificationGesture(frameSize: calculatedFrameSize, imageSize: imageSize))
            .onAppear { frameSize = calculatedFrameSize }
            .onChange(of: geometry.size) { _, _ in frameSize = calculatedFrameSize }
            .onChange(of: orientation) { _, _ in frameSize = calculatedFrameSize }
        }
    }

    private func calculateFrameSize(in containerSize: CGSize) -> CGSize {
        #if os(macOS)
        let scaleFactor: CGFloat = 0.80
        #else
        let scaleFactor: CGFloat = 0.85
        #endif
        let maxWidth = containerSize.width * scaleFactor
        let maxHeight = containerSize.height * scaleFactor

        var width = maxWidth
        var height = width / cropAspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * cropAspectRatio
        }

        return CGSize(width: width, height: height)
    }

    private func calculateImageSize(toFill frameSize: CGSize) -> CGSize {
        let frameAspect = frameSize.width / frameSize.height

        if imageAspectRatio > frameAspect {
            // Image is wider than frame - match heights
            let height = frameSize.height
            let width = height * imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            // Image is taller than frame - match widths
            let width = frameSize.width
            let height = width / imageAspectRatio
            return CGSize(width: width, height: height)
        }
    }

    private func clampedOffset(_ proposedOffset: CGSize, frameSize: CGSize, imageSize: CGSize) -> CGSize {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        let maxOffsetX = max(0, (scaledWidth - frameSize.width) / 2)
        let maxOffsetY = max(0, (scaledHeight - frameSize.height) / 2)

        return CGSize(
            width: min(max(proposedOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(proposedOffset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func dragGesture(frameSize: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposedOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposedOffset, frameSize: frameSize, imageSize: imageSize)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func magnificationGesture(frameSize: CGSize, imageSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, 1.0), 5.0)
                offset = clampedOffset(offset, frameSize: frameSize, imageSize: imageSize)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }
}

struct PolaroidFrameOverlay: View {
    let frameSize: CGSize
    let orientation: Orientation
    let thinBorder: CGFloat
    let thickBorder: CGFloat
    let onRotateCW: () -> Void
    let onRotateCCW: () -> Void
    let onClearImage: () -> Void

    private var polaroidSize: CGSize {
        if orientation.isLandscape {
            return CGSize(
                width: frameSize.width + thinBorder + thickBorder,
                height: frameSize.height + thinBorder * 2
            )
        } else {
            return CGSize(
                width: frameSize.width + thinBorder * 2,
                height: frameSize.height + thinBorder + thickBorder
            )
        }
    }

    /// Offset of the image cutout within the polaroid frame
    private var cutoutOffset: CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: 0, height: -(thickBorder - thinBorder) / 2)
        case .landscape:
            return CGSize(width: (thickBorder - thinBorder) / 2, height: 0)
        case .portraitFlipped:
            return CGSize(width: 0, height: (thickBorder - thinBorder) / 2)
        case .landscapeFlipped:
            return CGSize(width: -(thickBorder - thinBorder) / 2, height: 0)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centerX = size.width / 2
            let centerY = size.height / 2

            ZStack {
                // White polaroid frame with image cutout
                Canvas { context, size in
                    let centerX = size.width / 2
                    let centerY = size.height / 2

                    let polaroidRect = CGRect(
                        x: centerX - polaroidSize.width / 2,
                        y: centerY - polaroidSize.height / 2,
                        width: polaroidSize.width,
                        height: polaroidSize.height
                    )

                    let imageRect = CGRect(
                        x: centerX - frameSize.width / 2 + cutoutOffset.width,
                        y: centerY - frameSize.height / 2 + cutoutOffset.height,
                        width: frameSize.width,
                        height: frameSize.height
                    )

                    context.fill(Path(roundedRect: polaroidRect, cornerRadius: 4), with: .color(.white))
                    context.blendMode = .destinationOut
                    context.fill(Path(imageRect), with: .color(.white))
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .allowsHitTesting(false)

                // Rotation buttons in thick border
                rotationButtons(centerX: centerX, centerY: centerY)
            }
        }
    }

    @ViewBuilder
    private func rotationButtons(centerX: CGFloat, centerY: CGFloat) -> some View {
        switch orientation {
        case .portrait:
            // Fat edge at bottom
            HStack(spacing: 20) {
                rotateButton(systemImage: "rotate.right", action: onRotateCW).rotationEffect(Angle(degrees: -90))
                clearButton(action: onClearImage)
                rotateButton(systemImage: "rotate.left", action: onRotateCCW).rotationEffect(Angle(degrees: 90))
            }
            .position(x: centerX, y: centerY + frameSize.height / 2 + thinBorder / 2)

        case .landscape:
            // Fat edge at left
            VStack(spacing: 20) {
                rotateButton(systemImage: "rotate.right", action: onRotateCW)
                clearButton(action: onClearImage)
                rotateButton(systemImage: "rotate.left", action: onRotateCCW).rotationEffect(Angle(degrees: 180))
            }
            .position(x: centerX - frameSize.width / 2 - thinBorder / 2, y: centerY)

        case .portraitFlipped:
            // Fat edge at top
            HStack(spacing: 20) {
              rotateButton(systemImage: "rotate.left", action: onRotateCCW).rotationEffect(Angle(degrees: -90))
              clearButton(action: onClearImage)
              rotateButton(systemImage: "rotate.right", action: onRotateCW).rotationEffect(Angle(degrees: 90))
            }
            .position(x: centerX, y: centerY - frameSize.height / 2 - thinBorder / 2)

        case .landscapeFlipped:
            // Fat edge at right
            VStack(spacing: 20) {
              rotateButton(systemImage: "rotate.left", action: onRotateCCW)
              clearButton(action: onClearImage)
              rotateButton(systemImage: "rotate.right", action: onRotateCW).rotationEffect(Angle(degrees: 180))
            }
            .position(x: centerX + frameSize.width / 2 + thinBorder / 2, y: centerY)
        }
    }

    private func rotateButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
