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
                        .offset(offset)
                        .gesture(dragGesture())
                        .gesture(magnificationGesture())

                    // Crop frame overlay
                    CropFrameOverlay(frameSize: frameSize)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
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
        let maxWidth = containerSize.width * 0.85
        let maxHeight = containerSize.height * 0.85

        var width = maxWidth
        var height = width / cropAspectRatio

        if height > maxHeight {
            height = maxHeight
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

    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, 0.5), 5.0)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}

struct CropFrameOverlay: View {
    let frameSize: CGSize

    var body: some View {
        ZStack {
            // Semi-transparent overlay with cutout
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .frame(width: frameSize.width, height: frameSize.height)
                                .blendMode(.destinationOut)
                        )
                )

            // White border for crop area
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: frameSize.width, height: frameSize.height)

            // Corner indicators
            CropCorners(frameSize: frameSize)
        }
        .allowsHitTesting(false)
    }
}

struct CropCorners: View {
    let frameSize: CGSize
    let cornerLength: CGFloat = 20
    let cornerWidth: CGFloat = 3

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerShape(cornerLength: cornerLength)
                    .stroke(Color.white, lineWidth: cornerWidth)
                    .frame(width: cornerLength, height: cornerLength)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .offset(cornerOffset(for: index))
            }
        }
    }

    private func cornerOffset(for index: Int) -> CGSize {
        let halfWidth = frameSize.width / 2 - cornerLength / 2
        let halfHeight = frameSize.height / 2 - cornerLength / 2

        switch index {
        case 0: return CGSize(width: -halfWidth, height: -halfHeight)
        case 1: return CGSize(width: halfWidth, height: -halfHeight)
        case 2: return CGSize(width: halfWidth, height: halfHeight)
        case 3: return CGSize(width: -halfWidth, height: halfHeight)
        default: return .zero
        }
    }
}

struct CornerShape: Shape {
    let cornerLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: cornerLength))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: cornerLength, y: 0))
        return path
    }
}
