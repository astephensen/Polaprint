import InstaxKit
import SwiftUI

struct PrinterStatusView: View {
  let connectionState: PrinterConnectionState
  let printProgress: PrintProgress?
  var secondsUntilRetry: Int = 0
  var onRetry: (() -> Void)?

  var body: some View {
    HStack(spacing: 8) {
      statusIcon
      statusText
      #if os(macOS)
        if case let .connected(info) = connectionState {
          printerDetails(info)
            .fixedSize()
        }
        if case .error = connectionState, let onRetry {
          retrySection(onRetry: onRetry)
        }
      #endif
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func retrySection(onRetry: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Divider()
        .frame(height: 16)
        .padding(.leading, 4)

      if secondsUntilRetry > 0 {
        Text("\(secondsUntilRetry)s")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }

      Button("Retry") {
        onRetry()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
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
    #if os(iOS)
      VStack(alignment: .leading, spacing: 0) {
        statusTitle
        statusSubtitle
      }
    #else
      switch connectionState {
      case .searching:
        Text("Searching...")
          .foregroundStyle(.secondary)
      case .connecting:
        Text("Connecting...")
          .foregroundStyle(.secondary)
      case let .connected(info):
        if let progress = printProgress {
          Text("\(info.modelName) — \(progress.message)")
            .foregroundStyle(.secondary)
        } else {
          Text("\(info.modelName) — Ready")
            .foregroundStyle(.secondary)
        }
      case let .error(message):
        if secondsUntilRetry > 0 {
          Text("\(message) — \(secondsUntilRetry)s")
            .monospacedDigit()
            .foregroundStyle(.orange)
        } else {
          Text(message)
            .foregroundStyle(.orange)
        }
      }
    #endif
  }

  #if os(iOS)
    @ViewBuilder
    private var statusTitle: some View {
      switch connectionState {
      case .searching:
        Text("Searching")
          .fontWeight(.medium)
      case .connecting:
        Text("Connecting")
          .fontWeight(.medium)
      case let .connected(info):
        Text(info.modelName)
          .fontWeight(.medium)
      case let .error(message):
        Text(message)
          .fontWeight(.medium)
          .foregroundStyle(.orange)
      }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
      switch connectionState {
      case .searching:
        Text("Looking for printer...")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .connecting:
        Text("Please wait...")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .connected:
        if let progress = printProgress {
          Text(progress.message)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      case .error:
        Text("Retrying in \(secondsUntilRetry)s...")
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  #endif

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
    var onRetry: (() -> Void)? = nil

    var body: some View {
      Group {
        if case let .connected(info) = connectionState {
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
          VStack(spacing: 16) {
            Text("Not connected")
              .foregroundStyle(.secondary)

            if let onRetry {
              Button("Retry Connection") {
                onRetry()
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .padding()
        }
      }
      .presentationCompactAdaptation(.popover)
    }
  }
#endif

// MARK: - Shared Helper

private func batteryIcon(percentage: Int) -> some View {
  let iconName: String
  let color: Color

  switch percentage {
  case 0 ..< 20:
    iconName = "battery.0percent"
    color = .red
  case 20 ..< 40:
    iconName = "battery.25percent"
    color = .orange
  case 40 ..< 60:
    iconName = "battery.50percent"
    color = .yellow
  case 60 ..< 80:
    iconName = "battery.75percent"
    color = .green
  default:
    iconName = "battery.100percent"
    color = .green
  }

  return Image(systemName: iconName)
    .foregroundStyle(color)
}
