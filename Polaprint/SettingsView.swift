import InstaxKit
import SwiftUI

enum ConnectionType: String, CaseIterable, Identifiable {
  case `default`
  case local
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .default: "Default"
    case .local: "Local"
    case .custom: "Custom"
    }
  }

  var description: String {
    switch self {
    case .default: "192.168.0.251:8080"
    case .local: "127.0.0.1:8080"
    case .custom: "Custom IP and port"
    }
  }
}

enum PrinterSettings {
  static let connectionTypeKey = "printerConnectionType"
  static let customHostKey = "printerCustomHost"
  static let customPortKey = "printerCustomPort"
  static let pinCodeKey = "printerPinCode"
  static let printerModelKey = "printerModel"

  static let defaultHost = "192.168.0.251"
  static let defaultPort: UInt16 = 8080
  static let defaultPinCode: UInt16 = 1111
  static let defaultPrinterModel: PrinterModel = .sp2

  static func load() -> (host: String, port: UInt16, pinCode: UInt16) {
    let connectionType = ConnectionType(
      rawValue: UserDefaults.standard.string(forKey: connectionTypeKey) ?? "default"
    ) ??
      .default
    let pinCode = UInt16(UserDefaults.standard.integer(forKey: pinCodeKey))
    let effectivePinCode = pinCode > 0 ? pinCode : defaultPinCode

    switch connectionType {
    case .default:
      return (defaultHost, defaultPort, effectivePinCode)
    case .local:
      return ("127.0.0.1", defaultPort, effectivePinCode)
    case .custom:
      let customHost = UserDefaults.standard.string(forKey: customHostKey) ?? defaultHost
      let customPort = UInt16(UserDefaults.standard.integer(forKey: customPortKey))
      return (customHost, customPort > 0 ? customPort : defaultPort, effectivePinCode)
    }
  }

  static func loadPrinterModel() -> PrinterModel {
    guard let savedModel = UserDefaults.standard.string(forKey: printerModelKey),
          let model = PrinterModel(rawValue: savedModel)
    else {
      return defaultPrinterModel
    }
    return model
  }

  static func savePrinterModel(_ model: PrinterModel) {
    UserDefaults.standard.set(model.rawValue, forKey: printerModelKey)
  }
}

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var connectionType: ConnectionType
  @State private var customHost: String
  @State private var customPort: String
  @State private var pinCode: String
  @State private var selectedPrinterModel: PrinterModel

  var onSettingsChanged: () -> Void

  init(onSettingsChanged: @escaping () -> Void) {
    self.onSettingsChanged = onSettingsChanged

    let savedConnectionType = ConnectionType(rawValue: UserDefaults.standard
      .string(forKey: PrinterSettings.connectionTypeKey) ?? "default") ?? .default
    let savedCustomHost = UserDefaults.standard.string(forKey: PrinterSettings.customHostKey) ?? PrinterSettings
      .defaultHost
    let savedCustomPort = UserDefaults.standard.integer(forKey: PrinterSettings.customPortKey)
    let savedPinCode = UserDefaults.standard.integer(forKey: PrinterSettings.pinCodeKey)

    _connectionType = State(initialValue: savedConnectionType)
    _customHost = State(initialValue: savedCustomHost)
    _customPort =
      State(initialValue: savedCustomPort > 0 ? String(savedCustomPort) : String(PrinterSettings.defaultPort))
    _pinCode = State(initialValue: savedPinCode > 0 ? String(savedPinCode) : String(PrinterSettings.defaultPinCode))
    _selectedPrinterModel = State(initialValue: PrinterSettings.loadPrinterModel())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Host", selection: $connectionType) {
            ForEach(ConnectionType.allCases) { type in
              VStack(alignment: .leading) {
                Text(type.displayName)
                Text(type.description)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .tag(type)
            }
          }

          if connectionType == .custom {
            TextField("IP Address", text: $customHost)
            #if os(iOS)
              .keyboardType(.decimalPad)
            #endif
              .textContentType(.none)
              .autocorrectionDisabled()

            TextField("Port", text: $customPort)
            #if os(iOS)
              .keyboardType(.numberPad)
            #endif
          }
        } header: {
          Text("Printer Connection")
        } footer: {
          Text("Select how to connect to your Instax printer.")
        }

        Section {
          TextField("PIN Code", text: $pinCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
        } header: {
          Text("Authentication")
        } footer: {
          Text("The PIN code to connect to your printer.")
        }

        Section {
          Picker("Printer Model", selection: $selectedPrinterModel) {
            Text("SP-1 (Mini)").tag(PrinterModel.sp1)
            Text("SP-2 (Mini)").tag(PrinterModel.sp2)
            Text("SP-3 (Square)").tag(PrinterModel.sp3)
          }
        } header: {
          Text("Printer Model")
        } footer: {
          Text("Select your Instax printer model. This will be overridden when a printer is connected.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              dismiss()
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              saveSettings()
              onSettingsChanged()
              dismiss()
            }
          }
        }
    }
    #if os(macOS)
    .frame(minWidth: 400, minHeight: 350)
    #endif
  }

  private func saveSettings() {
    UserDefaults.standard.set(connectionType.rawValue, forKey: PrinterSettings.connectionTypeKey)
    UserDefaults.standard.set(customHost, forKey: PrinterSettings.customHostKey)
    if let port = UInt16(customPort) {
      UserDefaults.standard.set(Int(port), forKey: PrinterSettings.customPortKey)
    }
    if let pin = UInt16(pinCode) {
      UserDefaults.standard.set(Int(pin), forKey: PrinterSettings.pinCodeKey)
    }
    PrinterSettings.savePrinterModel(selectedPrinterModel)
  }
}

#Preview {
  SettingsView(onSettingsChanged: {})
}
