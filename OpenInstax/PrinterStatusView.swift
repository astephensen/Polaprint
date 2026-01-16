import SwiftUI
import InstaxKit

struct PrinterStatusView: View {
    let connectionState: PrinterConnectionState
    let printProgress: PrintProgress?

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
            statusText
            #if os(macOS)
            if case .connected(let info) = connectionState {
                printerDetails(info)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 280)
        #else
        .padding(.horizontal, 16)
        .frame(height: 44)
        #endif
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .searching, .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch connectionState {
        case .searching:
            Text("Searching...")
                .foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting...")
                .foregroundStyle(.secondary)
        case .connected(let info):
            if let progress = printProgress {
                Text("\(info.modelName) — \(progress.message)")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(info.modelName) — Ready")
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func printerDetails(_ info: PrinterInfo) -> some View {
        HStack(spacing: 12) {
            Divider()
                .frame(height: 16)
                .padding(.leading, 4)

            // Film remaining
            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("\(info.printsRemaining)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Battery
            HStack(spacing: 4) {
                batteryIcon(percentage: info.batteryPercentage)
                Text("\(info.batteryPercentage)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func batteryIcon(percentage: Int) -> some View {
        let iconName: String
        let color: Color

        switch percentage {
        case 0..<20:
            iconName = "battery.0percent"
            color = .red
        case 20..<40:
            iconName = "battery.25percent"
            color = .orange
        case 40..<60:
            iconName = "battery.50percent"
            color = .yellow
        case 60..<80:
            iconName = "battery.75percent"
            color = .green
        default:
            iconName = "battery.100percent"
            color = .green
        }

        return Image(systemName: iconName)
            .foregroundStyle(color)
    }
}

struct PrintProgressOverlay: View {
    let progress: PrintProgress

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(progress.percentage), total: 100)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text(progress.message)
                .font(.headline)

            Text("\(progress.percentage)%")
                .font(.title)
                .monospacedDigit()
                .fontWeight(.bold)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#if os(iOS)
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
        }
    }
}

struct PrinterDetailsPopover: View {
    let connectionState: PrinterConnectionState

    var body: some View {
        Group {
            if case .connected(let info) = connectionState {
                VStack(alignment: .leading, spacing: 16) {
                    Text(info.modelName)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.secondary)
                        Text("\(info.printsRemaining) prints remaining")
                    }

                    HStack(spacing: 12) {
                        batteryIcon(percentage: info.batteryPercentage)
                        Text("\(info.batteryPercentage)% battery")
                    }
                }
                .padding()
            } else {
                Text("Not connected")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .presentationCompactAdaptation(.popover)
    }

    private func batteryIcon(percentage: Int) -> some View {
        let iconName: String
        let color: Color

        switch percentage {
        case 0..<20:
            iconName = "battery.0percent"
            color = .red
        case 20..<40:
            iconName = "battery.25percent"
            color = .orange
        case 40..<60:
            iconName = "battery.50percent"
            color = .yellow
        case 60..<80:
            iconName = "battery.75percent"
            color = .green
        default:
            iconName = "battery.100percent"
            color = .green
        }

        return Image(systemName: iconName)
            .foregroundStyle(color)
    }
}
#endif
