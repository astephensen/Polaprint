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
        case (.searching, .searching): return true
        case (.connecting, .connecting): return true
        case (.connected(let a), .connected(let b)):
            return a.modelName == b.modelName && a.printsRemaining == b.printsRemaining
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

@MainActor
@Observable
final class PrinterManager {
    var connectionState: PrinterConnectionState = .searching
    var printProgress: PrintProgress?
    var isPrinting: Bool = false
    private(set) var printerModel: PrinterModel?

    var host: String = "192.168.0.251"
    var port: UInt16 = 8080
    var pinCode: UInt16 = 1111

    private var printer: InstaxPrinter?
    private var monitorTask: Task<Void, Never>?
    private var cachedInfo: PrinterInfo?
    private var lastInfoFetch: Date?

    // Short interval when searching, longer when connected
    private let searchInterval: TimeInterval = 3.0
    private let connectedRefreshInterval: TimeInterval = 30.0

    init() {
        loadSettings()
    }

    func loadSettings() {
        let settings = PrinterSettings.load()
        host = settings.host
        port = settings.port
        pinCode = settings.pinCode
    }

    func applySettings() {
        loadSettings()
        // Reset connection to use new settings
        printer = nil
        printerModel = nil
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
    }

    private func monitorPrinter() async {
        while !Task.isCancelled {
            await checkPrinterStatus()

            // Use shorter interval when searching, longer when connected
            let interval = (printer != nil) ? connectedRefreshInterval : searchInterval
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
                printerModel = await detectedPrinter.model

                // Fetch info on initial connection
                let info = try await detectedPrinter.getInfo()
                cachedInfo = info
                lastInfoFetch = Date()
                connectionState = .connected(info)
            } else if let printer = printer {
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
            printerModel = nil
            cachedInfo = nil
            lastInfoFetch = nil
            let errorMessage = parseError(error)
            if case .error(let currentError) = connectionState, currentError == errorMessage {
                // Don't update if same error
            } else {
                connectionState = .error(errorMessage)
            }
            // After error, wait then go back to searching
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled && !isPrinting {
                connectionState = .searching
            }
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

    func print(image: CGImage, rotation: ImageRotation) async throws {
        guard let printer = printer, let model = printerModel else {
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

        let encoder = InstaxImageEncoder(model: model)
        let encodedData = try encoder.encode(image: image, rotation: rotation)

        try await printer.print(encodedImage: encodedData) { [weak self] progress in
            Task { @MainActor in
                self?.printProgress = progress
            }
        }
    }
}
