import Foundation
import InstaxKit
import SwiftUI

enum PrinterConnectionState: Equatable {
  case searching
  case connecting
  case connected(PrinterInfo)
  case error(String)

  static func == (lhs: PrinterConnectionState, rhs: PrinterConnectionState) -> Bool {
    switch (lhs, rhs) {
    case (.searching, .searching): true
    case (.connecting, .connecting): true
    case let (.connected(a), .connected(b)):
      a.modelName == b.modelName && a.printsRemaining == b.printsRemaining
    case let (.error(a), .error(b)): a == b
    default: false
    }
  }
}

@MainActor
@Observable
final class PrinterManager {
  var connectionState: PrinterConnectionState = .searching
  var printProgress: PrintProgress?
  var isPrinting: Bool = false
  var secondsUntilRetry: Int = 0
  private(set) var detectedPrinterModel: PrinterModel?
  private(set) var selectedPrinterModel: PrinterModel = .sp2

  /// Returns the detected printer model if connected, otherwise the user-selected model
  var printerModel: PrinterModel {
    detectedPrinterModel ?? selectedPrinterModel
  }

  var host: String = "192.168.0.251"
  var port: UInt16 = 8080
  var pinCode: UInt16 = 1111

  private var printer: InstaxPrinter?
  private var monitorTask: Task<Void, Never>?
  private var countdownTask: Task<Void, Never>?
  private var cachedInfo: PrinterInfo?
  private var lastInfoFetch: Date?
  private var retryCount: Int = 0

  // Retry backoff settings
  private let initialRetryInterval: TimeInterval = 3.0
  private let maxRetryInterval: TimeInterval = 15.0
  private let connectedRefreshInterval: TimeInterval = 30.0

  init() {
    loadSettings()
  }

  func loadSettings() {
    let settings = PrinterSettings.load()
    host = settings.host
    port = settings.port
    pinCode = settings.pinCode
    selectedPrinterModel = PrinterSettings.loadPrinterModel()
  }

  func applySettings() {
    loadSettings()
    // Reset connection to use new settings
    printer = nil
    detectedPrinterModel = nil
    cachedInfo = nil
    lastInfoFetch = nil
    connectionState = .searching
  }

  func startMonitoring() {
    stopMonitoring()
    monitorTask = Task {
      await monitorPrinter()
    }
  }

  func stopMonitoring() {
    monitorTask?.cancel()
    monitorTask = nil
    countdownTask?.cancel()
    countdownTask = nil
  }

  func retryNow() {
    countdownTask?.cancel()
    countdownTask = nil
    secondsUntilRetry = 0
    retryCount = 0
    connectionState = .searching
    monitorTask?.cancel()
    monitorTask = Task {
      await monitorPrinter()
    }
  }

  private func currentRetryInterval() -> TimeInterval {
    let interval = initialRetryInterval * pow(1.5, Double(retryCount))
    return min(interval, maxRetryInterval)
  }

  private func startCountdown(seconds: Int) {
    countdownTask?.cancel()
    secondsUntilRetry = seconds
    countdownTask = Task {
      for remaining in stride(from: seconds, through: 1, by: -1) {
        if Task.isCancelled { break }
        secondsUntilRetry = remaining
        try? await Task.sleep(for: .seconds(1))
      }
      secondsUntilRetry = 0
    }
  }

  private func monitorPrinter() async {
    while !Task.isCancelled {
      await checkPrinterStatus()

      // Use connected refresh interval when connected, backoff when searching
      let interval: TimeInterval
      if printer != nil {
        retryCount = 0
        interval = connectedRefreshInterval
      } else {
        interval = currentRetryInterval()
        retryCount += 1
        startCountdown(seconds: Int(interval))
      }
      try? await Task.sleep(for: .seconds(interval))
    }
  }

  private func checkPrinterStatus() async {
    guard !isPrinting else { return }

    do {
      if printer == nil {
        connectionState = .connecting
        let detectedPrinter = try await InstaxKit.detectPrinter(
          host: host,
          port: port,
          pinCode: pinCode
        )
        printer = detectedPrinter
        detectedPrinterModel = await detectedPrinter.model

        // Fetch info on initial connection
        let info = try await detectedPrinter.getInfo()
        cachedInfo = info
        lastInfoFetch = Date()
        connectionState = .connected(info)
      } else if let printer {
        // Only refresh info if enough time has passed
        let shouldRefresh = lastInfoFetch == nil ||
          Date().timeIntervalSince(lastInfoFetch!) >= connectedRefreshInterval

        if shouldRefresh {
          let info = try await printer.getInfo()
          cachedInfo = info
          lastInfoFetch = Date()
          connectionState = .connected(info)
        } else if let cached = cachedInfo {
          // Use cached info
          connectionState = .connected(cached)
        }
      }
    } catch {
      printer = nil
      detectedPrinterModel = nil
      cachedInfo = nil
      lastInfoFetch = nil
      let errorMessage = parseError(error)
      connectionState = .error(errorMessage)
    }
  }

  private func parseError(_ error: Error) -> String {
    let description = String(describing: error)
    if description.contains("Connection refused") {
      return "Printer not found"
    } else if description.contains("Network is unreachable") {
      return "Network unreachable"
    } else if description.contains("timed out") || description.contains("timeout") {
      return "Connection timed out"
    }
    return "Connection failed"
  }

  func print(image: CGImage) async throws {
    guard let printer else {
      throw PrintError.encodingFailed
    }

    isPrinting = true
    printProgress = PrintProgress(stage: .connecting, percentage: 0, message: "Starting...")

    defer {
      isPrinting = false
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        self.printProgress = nil
      }
    }

    let encoder = InstaxImageEncoder(model: printerModel)
    let encodedData = try encoder.encode(image: image)

    try await printer.print(encodedImage: encodedData) { [weak self] progress in
      Task { @MainActor in
        self?.printProgress = progress
      }
    }
  }
}
