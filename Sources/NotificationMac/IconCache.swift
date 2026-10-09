import AppKit

/// Tải icon app Android từ server, cache trên đĩa + RAM.
final class IconCache {
    static let shared = IconCache()

    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("NotificationMac/icons")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let lock = NSLock()
    private var images: [String: NSImage] = [:]
    private var missing: [String: Date] = [:]          // package -> lần thử cuối thất bại
    private var waiting: [String: [(URL?) -> Void]] = [:]

    private func path(_ pkg: String) -> URL {
        dir.appendingPathComponent(pkg.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    /// Ảnh đã có sẵn (đồng bộ), dùng cho UI; nếu chưa có thì kích hoạt tải và gọi `onLoad`.
    func image(for pkg: String, onLoad: @escaping () -> Void = {}) -> NSImage? {
        lock.lock()
        if let img = images[pkg] { lock.unlock(); return img }
        lock.unlock()
        if let img = NSImage(contentsOf: path(pkg)) {
            lock.lock(); images[pkg] = img; lock.unlock()
            return img
        }
        fileURL(for: pkg) { url in if url != nil { onLoad() } }
        return nil
    }

    /// File PNG của icon (để làm attachment). Gọi completion trên thread bất kỳ; nil nếu không tải được.
    func fileURL(for pkg: String, completion: @escaping (URL?) -> Void) {
        let file = path(pkg)
        if FileManager.default.fileExists(atPath: file.path) { return completion(file) }

        lock.lock()
        if let t = missing[pkg], Date().timeIntervalSince(t) < 60 { lock.unlock(); return completion(nil) }
        if waiting[pkg] != nil { waiting[pkg]!.append(completion); lock.unlock(); return }
        waiting[pkg] = [completion]
        lock.unlock()

        let encoded = pkg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pkg
        guard let req = ServerClient.shared.request("api/icons/\(encoded)") else { return finish(pkg, nil) }
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self else { return }
            if let data, (resp as? HTTPURLResponse)?.statusCode == 200, NSImage(data: data) != nil,
               (try? data.write(to: file)) != nil {
                self.finish(pkg, file)
            } else {
                self.finish(pkg, nil)
            }
        }.resume()
    }

    private func finish(_ pkg: String, _ url: URL?) {
        lock.lock()
        let cbs = waiting.removeValue(forKey: pkg) ?? []
        if url == nil { missing[pkg] = Date() }
        lock.unlock()
        cbs.forEach { $0(url) }
    }
}
