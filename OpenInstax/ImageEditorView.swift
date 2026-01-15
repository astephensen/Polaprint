import SwiftUI
import InstaxKit

extension InstaxOrientation {
  var displayName: String {
    switch self {
    case .portrait: "Portrait"
    case .landscape: "Landscape"
    case .portraitFlipped: "Portrait Flipped"
    case .landscapeFlipped: "Landscape Flipped"
    }
  }

  static var standardOrientations: [InstaxOrientation] {
    [.portrait, .landscape]
  }
}

struct ImageEditorView: View {
    let image: CGImage
    let printerModel: PrinterModel?
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var orientation: InstaxOrientation
    @Binding var frameSize: CGSize

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
        case .portrait, .portraitFlipped:
            return CGSize(width: 0, height: -diff)
        case .landscape, .landscapeFlipped:
            return CGSize(width: diff, height: 0)
        }
    }

    private var cropAspectRatio: CGFloat {
        guard let model = printerModel else { return 0.75 } // Default 3:4

        let width = CGFloat(model.imageWidth)
        let height = CGFloat(model.imageHeight)

        switch orientation {
        case .portrait, .portraitFlipped:
            return width / height
        case .landscape, .landscapeFlipped:
            return height / width
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

            ZStack {
                // Dark background
                Color.black.opacity(0.8)

                // Image - offset includes user pan + visual alignment for polaroid
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                    .offset(x: offset.width + visualOffset.width,
                            y: offset.height + visualOffset.height)

                // Polaroid frame overlay (visual only)
                PolaroidFrameOverlay(
                    frameSize: calculatedFrameSize,
                    orientation: orientation,
                    thinBorder: thinBorder,
                    thickBorder: thickBorder
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(frameSize: calculatedFrameSize, imageSize: imageSize))
            .gesture(magnificationGesture(frameSize: calculatedFrameSize, imageSize: imageSize))
            .clipped()
            .onAppear { frameSize = calculatedFrameSize }
            .onChange(of: geometry.size) { _, _ in frameSize = calculatedFrameSize }
            .onChange(of: orientation) { _, _ in frameSize = calculatedFrameSize }
        }
    }

    private func calculateFrameSize(in containerSize: CGSize) -> CGSize {
        let maxWidth = containerSize.width * 0.75
        let maxHeight = containerSize.height * 0.75

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
    let orientation: InstaxOrientation
    let thinBorder: CGFloat
    let thickBorder: CGFloat

    private var polaroidSize: CGSize {
        switch orientation {
        case .portrait, .portraitFlipped:
            return CGSize(
                width: frameSize.width + thinBorder * 2,
                height: frameSize.height + thinBorder + thickBorder
            )
        case .landscape, .landscapeFlipped:
            return CGSize(
                width: frameSize.width + thinBorder + thickBorder,
                height: frameSize.height + thinBorder * 2
            )
        }
    }

    /// Offset of the image cutout within the polaroid frame
    private var cutoutOffset: CGSize {
        switch orientation {
        case .portrait, .portraitFlipped:
            // Image at top, thick border at bottom
            return CGSize(width: 0, height: -(thickBorder - thinBorder) / 2)
        case .landscape, .landscapeFlipped:
            // Image at right, thick border at left
            return CGSize(width: (thickBorder - thinBorder) / 2, height: 0)
        }
    }

    var body: some View {
        ZStack {
            // Dark overlay with polaroid-shaped cutout
            Canvas { context, size in
                // Fill entire area
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))

                // Cut out the polaroid shape
                let polaroidRect = CGRect(
                    x: (size.width - polaroidSize.width) / 2,
                    y: (size.height - polaroidSize.height) / 2,
                    width: polaroidSize.width,
                    height: polaroidSize.height
                )
                context.blendMode = .destinationOut
                context.fill(Path(roundedRect: polaroidRect, cornerRadius: 4), with: .color(.white))
            }

            // White polaroid frame with image cutout
            Canvas { context, size in
                let centerX = size.width / 2
                let centerY = size.height / 2

                // Outer polaroid rectangle
                let polaroidRect = CGRect(
                    x: centerX - polaroidSize.width / 2,
                    y: centerY - polaroidSize.height / 2,
                    width: polaroidSize.width,
                    height: polaroidSize.height
                )

                // Inner image cutout (offset based on orientation)
                let imageRect = CGRect(
                    x: centerX - frameSize.width / 2 + cutoutOffset.width,
                    y: centerY - frameSize.height / 2 + cutoutOffset.height,
                    width: frameSize.width,
                    height: frameSize.height
                )

                // Draw white frame
                context.fill(Path(roundedRect: polaroidRect, cornerRadius: 4), with: .color(.white))

                // Cut out the image area
                context.blendMode = .destinationOut
                context.fill(Path(imageRect), with: .color(.white))
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .allowsHitTesting(false)
    }
}
