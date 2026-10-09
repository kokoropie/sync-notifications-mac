import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("Chung", systemImage: "gearshape") }
            WhitelistView().tabItem { Label("Whitelist app", systemImage: "checklist") }
        }
        .frame(width: 460, height: 520)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var client = ServerClient.shared

    private var statusText: String {
        if client.connected { return "Đã kết nối" }
        return client.lastError ?? "Chưa kết nối"
    }

    private var statusColor: Color { client.connected ? Color.green : Color.red }

    var body: some View {
        Form {
            Section("Server") {
                TextField("URL", text: $settings.serverURL)
                SecureField("Account key", text: $settings.accountKey)
                TextField("Tên thiết bị", text: $settings.deviceName)
            }
            Section {
                Toggle("Đồng bộ clipboard", isOn: $settings.clipboardSync)
            }
            statusRow
        }
        .formStyle(.grouped)
    }

    private var statusRow: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.caption)
            Spacer()
            Button("Kết nối lại") { client.reconnect() }
        }
    }
}
