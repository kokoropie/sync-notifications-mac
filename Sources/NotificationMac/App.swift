import SwiftUI

@main
struct NotificationMacApp: App {
    @ObservedObject private var client = ServerClient.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        ServerClient.shared.start()
    }

    /// App menu bar không có Dock nên phải tự kích hoạt app để cửa sổ nổi lên trước.
    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.contains(id) == true }?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra("Sync Notification", systemImage: client.connected ? "bell.badge" : "bell.slash") {
            Text(client.connected ? "Đã kết nối" : "Mất kết nối")
            Button("Danh sách thông báo…") { show("history") }
            Divider()
            Button("Cài đặt…") { show("settings") }
                .keyboardShortcut(",")
            Button("Thoát") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        Window("Thông báo Android", id: "history") { HistoryView() }
        Window("Cài đặt", id: "settings") { SettingsView() }
            .windowResizability(.contentSize)
    }
}
