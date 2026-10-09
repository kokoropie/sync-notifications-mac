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

    private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Tác giả: Kaga Akatsuki\nLiên hệ: admin@kokoropie.info.vn",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        if let r = credits.string.range(of: "admin@kokoropie.info.vn") {
            credits.addAttribute(.link, value: URL(string: "mailto:admin@kokoropie.info.vn")!, range: NSRange(r, in: credits.string))
        }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        credits.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Sync Notification", .credits: credits])
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
