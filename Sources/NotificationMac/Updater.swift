import AppKit

/// Tự cập nhật từ GitHub Releases. App tự tải DMG nên file không bị gắn cờ quarantine → Gatekeeper không hỏi lại.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "kokoropie/sync-notifications-mac"
    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var busy = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    struct Release: Decodable {
        let tag_name: String
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
        var dmg: Asset? { assets.first { $0.name.hasSuffix(".dmg") } }
    }

    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ m: String) { message = m }
    }

    /// Gọi lúc khởi động: kiểm tra yên lặng tối đa mỗi 24 giờ, chỉ hiện hộp thoại khi có bản mới.
    func checkOnLaunch() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.autoCheckKey) as? Bool == false { return }
        if Date().timeIntervalSince1970 - d.double(forKey: Self.lastCheckKey) < 86_400 { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let latest = try await fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard Self.isNewer(latest.version, than: currentVersion) else {
                if userInitiated { info("Bạn đang dùng bản mới nhất", "Phiên bản \(currentVersion).") }
                return
            }
            guard let dmg = latest.dmg else {
                if userInitiated { info("Có bản \(latest.version) nhưng chưa có file DMG", "Thử lại sau ít phút.") }
                return
            }
            guard confirm(latest) else { return }
            try await install(dmg: dmg.browser_download_url)
        } catch {
            if userInitiated { info("Không cập nhật được", error.localizedDescription) }
        }
    }

    // MARK: - Version

    /// So sánh 1.2.3 với 1.10.0; bản có hậu tố (-beta, -dev) nhỏ hơn bản chính thức cùng số.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parse(_ v: String) -> ([Int], Bool) {
            let parts = v.split(separator: "-", maxSplits: 1)
            let nums = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (nums, parts.count > 1)
        }
        let (x, xPre) = parse(a), (y, yPre) = parse(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return !xPre && yPre
    }

    // MARK: - Network

    private func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Không lấy được thông tin bản phát hành từ GitHub.") }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Install

    private func install(dmg url: URL) async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationMacUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Tải bản cập nhật thất bại.") }
        let dmg = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: tmp, to: dmg)

        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path])
        var detached = false
        func detach() async { if !detached { detached = true; _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) } }

        let staged = work.appendingPathComponent("new.app")
        do {
            let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
            guard let src = apps.first else { throw UpdateError("DMG không chứa app.") }
            try await Self.run("/usr/bin/ditto", [src.path, staged.path])
        } catch {
            await detach()
            throw error
        }
        await detach()

        try await verify(staged)

        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError("Không có quyền ghi vào \(target.deletingLastPathComponent().path). Hãy chép app vào Applications rồi thử lại.")
        }

        // Script chờ app thoát, thay bản mới rồi mở lại.
        let script = work.appendingPathComponent("install.sh")
        let sh = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        rm -rf "$1" && ditto "$2" "$1" && xattr -cr "$1"
        open "$1"
        rm -rf "$3"
        """
        try sh.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, target.path, staged.path, work.path]
        try p.run()
        NSApp.terminate(nil)
    }

    /// Bản mới phải ký hợp lệ; nếu app hiện tại ký bằng chứng chỉ cố định thì bản mới phải cùng chứng chỉ đó.
    private func verify(_ app: URL) async throws {
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError("Chữ ký bản cập nhật không hợp lệ.")
        }
        let dr = try await Self.run("/usr/bin/codesign", ["-d", "-r-", Bundle.main.bundlePath])
        guard let range = dr.range(of: "designated => ") else { return }
        let requirement = String(dr[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if requirement.hasPrefix("cdhash") { return } // ký ad-hoc: không có danh tính để so
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "-R=\(requirement)", app.path])
        } catch {
            throw UpdateError("Bản cập nhật không được ký bằng cùng chứng chỉ với bản đang chạy.")
        }
    }

    // MARK: - Helpers

    @discardableResult
    private nonisolated static func run(_ path: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    let out = String(decoding: data, as: UTF8.self)
                    if p.terminationStatus == 0 { cont.resume(returning: out) }
                    else { cont.resume(throwing: UpdateError("\(URL(fileURLWithPath: path).lastPathComponent) lỗi: \(out)")) }
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func confirm(_ r: Release) -> Bool {
        let a = NSAlert()
        a.messageText = "Có phiên bản mới \(r.version)"
        a.informativeText = "Bạn đang dùng \(currentVersion). App sẽ tải bản mới, thay thế và tự mở lại."
        a.addButton(withTitle: "Cập nhật")
        a.addButton(withTitle: "Để sau")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    private func info(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
