import Foundation
import SwiftUI

/// Cấu hình lưu trong UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var serverURL: String { didSet { d.set(serverURL, forKey: "serverURL") } }
    @Published var accountKey: String { didSet { d.set(accountKey, forKey: "accountKey") } }
    @Published var deviceName: String { didSet { d.set(deviceName, forKey: "deviceName") } }
    @Published var clipboardSync: Bool { didSet { d.set(clipboardSync, forKey: "clipboardSync") } }

    /// Whitelist dùng chung theo account key (đồng bộ qua server với Android).
    /// Bật = chỉ hiện banner của app đã chọn (lịch sử vẫn lưu đủ).
    @Published var whitelistEnabled: Bool { didSet { whitelistChanged() } }
    @Published var whitelist: Set<String> { didSet { whitelistChanged() } }
    /// true = đang áp dụng dữ liệu từ server, không đẩy ngược lên.
    var applyingRemoteWhitelist = false
    var whitelistDirty: Bool {
        get { d.bool(forKey: "whitelistDirty") }
        set { d.set(newValue, forKey: "whitelistDirty") }
    }

    private func whitelistChanged() {
        d.set(whitelistEnabled, forKey: "whitelistEnabled")
        d.set(Array(whitelist), forKey: "whitelist")
        guard !applyingRemoteWhitelist else { return }
        whitelistDirty = true
        ServerClient.shared.scheduleWhitelistPush()
    }

    func applyRemoteWhitelist(enabled: Bool, packages: [String]) {
        DispatchQueue.main.async {
            self.applyingRemoteWhitelist = true
            self.whitelistEnabled = enabled
            self.whitelist = Set(packages)
            self.applyingRemoteWhitelist = false
        }
    }
    /// Các app đã từng gửi thông báo (packageName -> tên), lấy từ chính thông báo nhận được.
    @Published private(set) var knownApps: [String: String]

    let deviceId: String

    func allows(_ pkg: String?) -> Bool {
        guard whitelistEnabled, let pkg else { return true }
        if pkg == "com.kokoropie.notification" { return true } // thông báo thử của chính app
        return whitelist.contains(pkg)
    }

    func learn(_ events: [ServerEvent]) {
        var found: [String: String] = [:]
        for e in events where e.type == "notification" {
            guard let pkg = e.packageName, !pkg.isEmpty else { continue }
            let name = (e.appName?.isEmpty == false ? e.appName! : pkg)
            if knownApps[pkg] != name { found[pkg] = name }
        }
        guard !found.isEmpty else { return }
        DispatchQueue.main.async {
            self.knownApps.merge(found) { _, new in new }
            self.d.set(self.knownApps, forKey: "knownApps")
        }
    }

    var lastEventId: Int {
        get { d.integer(forKey: "lastEventId") }
        set { d.set(newValue, forKey: "lastEventId") }
    }

    var isConfigured: Bool { !serverURL.isEmpty && !accountKey.isEmpty }

    private init() {
        serverURL = d.string(forKey: "serverURL") ?? "http://localhost:3000"
        accountKey = d.string(forKey: "accountKey") ?? ""
        deviceName = d.string(forKey: "deviceName") ?? (Host.current().localizedName ?? "Mac")
        clipboardSync = d.object(forKey: "clipboardSync") as? Bool ?? true
        whitelistEnabled = d.bool(forKey: "whitelistEnabled")
        whitelist = Set(d.stringArray(forKey: "whitelist") ?? [])
        knownApps = d.dictionary(forKey: "knownApps") as? [String: String] ?? [:]
        if let id = d.string(forKey: "deviceId") {
            deviceId = id
        } else {
            deviceId = "mac-" + UUID().uuidString.lowercased()
            d.set(deviceId, forKey: "deviceId")
        }
    }
}
