import SwiftUI
import InstaxKit

struct PrinterStatusView: View {
    let connectionState: PrinterConnectionState
    let printProgress: PrintProgress?

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            statusText
            Spacer()
            if case .connected(let info) = connectionState {
                printerDetails(info)
            }
        }
        .padding()
        .background(statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .searching:
            ProgressView()
                .controlSize(.small)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch connectionState {
            case .searching:
                Text("Searching...")
                    .font(.headline)
                Text("Looking for Instax printer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .connecting:
                Text("Connecting...")
                    .font(.headline)
                Text("Establishing connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .connected(let info):
                Text(info.modelName)
                    .font(.headline)
                if let progress = printProgress {
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready to print")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                Text(message)
                    .font(.headline)
                Text("Will retry automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func printerDetails(_ info: PrinterInfo) -> some View {
        HStack(spacing: 16) {
            // Film remaining
            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("\(info.printsRemaining)")
                    .font(.headline)
                    .monospacedDigit()
            }

            // Battery
            HStack(spacing: 4) {
                batteryIcon(percentage: info.batteryPercentage)
                Text("\(info.batteryPercentage)%")
                    .font(.headline)
                    .monospacedDigit()
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

    private var statusBackground: some ShapeStyle {
        switch connectionState {
        case .searching, .connecting:
            return Color.secondary.opacity(0.1)
        case .connected:
            return Color.green.opacity(0.1)
        case .error:
            return Color.orange.opacity(0.1)
        }
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
