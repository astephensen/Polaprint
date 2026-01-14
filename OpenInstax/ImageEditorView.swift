import SwiftUI
import InstaxKit

enum PrintOrientation: String, CaseIterable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var rotation: ImageRotation {
        switch self {
        case .portrait: return .none
        case .landscape: return .clockwise90
        }
    }
}

struct ImageEditorView: View {
    let image: CGImage
    let printerModel: PrinterModel?
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var orientation: PrintOrientation

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    // Match the polaroid border proportions
    private let thinBorder: CGFloat = 8
    private let thickBorder: CGFloat = 28

    /// Offset to align image with polaroid cutout
    private var imageAlignmentOffset: CGSize {
        let diff = (thickBorder - thinBorder) / 2
        switch orientation {
        case .portrait:
            // Thick border at bottom, image cutout is shifted up
            return CGSize(width: 0, height: -diff)
        case .landscape:
            // Thick border at left, image cutout is shifted right
            return CGSize(width: diff, height: 0)
        }
    }

    private var cropAspectRatio: CGFloat {
        guard let model = printerModel else { return 0.75 } // Default 3:4

        let width = CGFloat(model.imageWidth)
        let height = CGFloat(model.imageHeight)

        switch orientation {
        case .portrait:
            return width / height
        case .landscape:
            return height / width
        }
    }

    private var imageAspectRatio: CGFloat {
        CGFloat(image.width) / CGFloat(image.height)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Orientation picker
            Picker("Orientation", selection: $orientation) {
                ForEach(PrintOrientation.allCases, id: \.self) { orientation in
                    Text(orientation.rawValue).tag(orientation)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Image editor area
            GeometryReader { geometry in
                let frameSize = calculateFrameSize(in: geometry.size)
                let imageSize = calculateImageSize(toFill: frameSize)

                ZStack {
                    // Dark background
                    Color.black.opacity(0.8)

                    // Image with gestures
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                        .offset(x: offset.width + imageAlignmentOffset.width,
                                y: offset.height + imageAlignmentOffset.height)

                    // Crop frame overlay
                    CropFrameOverlay(frameSize: frameSize, orientation: orientation)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(frameSize: frameSize, imageSize: imageSize))
                .gesture(magnificationGesture(frameSize: frameSize, imageSize: imageSize))
                .clipped()
            }

            // Reset button
            Button("Reset") {
                withAnimation(.spring(duration: 0.3)) {
                    scale = 1.0
                    offset = .zero
                    lastScale = 1.0
                    lastOffset = .zero
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func calculateFrameSize(in containerSize: CGSize) -> CGSize {
        // Account for polaroid borders when calculating available space
        let horizontalBorders: CGFloat
        let verticalBorders: CGFloat

        switch orientation {
        case .portrait:
            horizontalBorders = thinBorder * 2
            verticalBorders = thinBorder + thickBorder
        case .landscape:
            horizontalBorders = thinBorder + thickBorder
            verticalBorders = thinBorder * 2
        }

        // Max space for the entire polaroid (90% of container)
        let maxPolaroidWidth = containerSize.width * 0.90
        let maxPolaroidHeight = containerSize.height * 0.90

        // Available space for the image frame inside the polaroid
        let maxFrameWidth = maxPolaroidWidth - horizontalBorders
        let maxFrameHeight = maxPolaroidHeight - verticalBorders

        var width = maxFrameWidth
        var height = width / cropAspectRatio

        if height > maxFrameHeight {
            height = maxFrameHeight
            width = height * cropAspectRatio
        }

        return CGSize(width: width, height: height)
    }

    private func calculateImageSize(toFill frameSize: CGSize) -> CGSize {
        // Calculate the image size needed to fill the crop frame
        // while maintaining the image's aspect ratio
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

        // Calculate maximum allowed offset (image must cover the frame)
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
                scale = min(max(newScale, 0.5), 5.0)
                // Re-clamp offset when scale changes
                offset = clampedOffset(offset, frameSize: frameSize, imageSize: imageSize)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }
}

struct CropFrameOverlay: View {
    let frameSize: CGSize
    var orientation: PrintOrientation = .portrait

    // Instax-style border proportions
    private let thinBorder: CGFloat = 8
    private let thickBorder: CGFloat = 28

    private var polaroidSize: CGSize {
        switch orientation {
        case .portrait:
            return CGSize(
                width: frameSize.width + thinBorder * 2,
                height: frameSize.height + thinBorder + thickBorder
            )
        case .landscape:
            return CGSize(
                width: frameSize.width + thinBorder + thickBorder,
                height: frameSize.height + thinBorder * 2
            )
        }
    }

    var body: some View {
        ZStack {
            // Semi-transparent overlay with cutout for entire polaroid
            PolaroidMask(frameSize: polaroidSize)
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            // Polaroid border frame (with hole for image)
            PolaroidFrame(orientation: orientation, frameSize: frameSize, thinBorder: thinBorder, thickBorder: thickBorder)
                .fill(Color.white, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .allowsHitTesting(false)
    }
}

/// Shape that fills everything except the polaroid area
struct PolaroidMask: Shape {
    let frameSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        let polaroidRect = CGRect(
            x: rect.midX - frameSize.width / 2,
            y: rect.midY - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        )
        path.addRoundedRect(in: polaroidRect, cornerSize: CGSize(width: 4, height: 4))

        return path
    }
}

/// Shape that draws the polaroid border with a cutout for the image
struct PolaroidFrame: Shape {
    let orientation: PrintOrientation
    let frameSize: CGSize
    let thinBorder: CGFloat
    let thickBorder: CGFloat

    func path(in rect: CGRect) -> Path {
        let polaroidWidth: CGFloat
        let polaroidHeight: CGFloat
        let imageOffsetX: CGFloat
        let imageOffsetY: CGFloat

        switch orientation {
        case .portrait:
            polaroidWidth = frameSize.width + thinBorder * 2
            polaroidHeight = frameSize.height + thinBorder + thickBorder
            imageOffsetX = thinBorder
            imageOffsetY = thinBorder
        case .landscape:
            polaroidWidth = frameSize.width + thinBorder + thickBorder
            polaroidHeight = frameSize.height + thinBorder * 2
            imageOffsetX = thickBorder
            imageOffsetY = thinBorder
        }

        var path = Path()

        // Outer polaroid frame
        let outerRect = CGRect(
            x: rect.midX - polaroidWidth / 2,
            y: rect.midY - polaroidHeight / 2,
            width: polaroidWidth,
            height: polaroidHeight
        )
        path.addRoundedRect(in: outerRect, cornerSize: CGSize(width: 4, height: 4))

        // Inner image cutout
        let innerRect = CGRect(
            x: outerRect.minX + imageOffsetX,
            y: outerRect.minY + imageOffsetY,
            width: frameSize.width,
            height: frameSize.height
        )
        path.addRect(innerRect)

        return path
    }
}

