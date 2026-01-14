import SwiftUI

enum ConnectionType: String, CaseIterable, Identifiable {
    case `default` = "default"
    case local = "local"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .local: return "Local"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .default: return "192.168.0.251:8080"
        case .local: return "127.0.0.1:8080"
        case .custom: return "Custom IP and port"
        }
    }
}

struct PrinterSettings {
    static let connectionTypeKey = "printerConnectionType"
    static let customHostKey = "printerCustomHost"
    static let customPortKey = "printerCustomPort"
    static let pinCodeKey = "printerPinCode"

    static let defaultHost = "192.168.0.251"
    static let defaultPort: UInt16 = 8080
    static let defaultPinCode: UInt16 = 1111

    static func load() -> (host: String, port: UInt16, pinCode: UInt16) {
        let connectionType = ConnectionType(rawValue: UserDefaults.standard.string(forKey: connectionTypeKey) ?? "default") ?? .default
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
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var connectionType: ConnectionType
    @State private var customHost: String
    @State private var customPort: String
    @State private var pinCode: String

    var onSettingsChanged: () -> Void

    init(onSettingsChanged: @escaping () -> Void) {
        self.onSettingsChanged = onSettingsChanged

        let savedConnectionType = ConnectionType(rawValue: UserDefaults.standard.string(forKey: PrinterSettings.connectionTypeKey) ?? "default") ?? .default
        let savedCustomHost = UserDefaults.standard.string(forKey: PrinterSettings.customHostKey) ?? PrinterSettings.defaultHost
        let savedCustomPort = UserDefaults.standard.integer(forKey: PrinterSettings.customPortKey)
        let savedPinCode = UserDefaults.standard.integer(forKey: PrinterSettings.pinCodeKey)

        _connectionType = State(initialValue: savedConnectionType)
        _customHost = State(initialValue: savedCustomHost)
        _customPort = State(initialValue: savedCustomPort > 0 ? String(savedCustomPort) : String(PrinterSettings.defaultPort))
        _pinCode = State(initialValue: savedPinCode > 0 ? String(savedPinCode) : String(PrinterSettings.defaultPinCode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Connection", selection: $connectionType) {
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
                    .pickerStyle(.inline)

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
                    Text("The PIN code displayed on your printer.")
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
    }
}

#Preview {
    SettingsView(onSettingsChanged: {})
}
