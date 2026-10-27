import Foundation
import AppKit
import CryptoKit

struct ServerEvent: Codable, Identifiable, Equatable {
    let kind: String
    let id: Int
    let type: String
    let timestamp: Double?
    // notification
    let packageName: String?
    let appName: String?
    let title: String?
    let text: String?
    let subText: String?
    // call
    let number: String?
    let name: String?
    let state: String?
}

private struct WSMessage: Decodable {
    let kind: String
    let version: String?
    let text: String?
    let type: String?
    let hash: String?
    let mime: String?
    let enabled: Bool?
    let packages: [String]?
}

/// Kết nối WebSocket tới server, tự reconnect, đồng bộ clipboard hai chiều.
final class ServerClient: ObservableObject {
    /// Header đặc biệt để Cloudflare chỉ cho request từ app đi qua.
    static let gateHeader = "X-Notification-Secret"
    /// Giá trị do build.sh ghi vào Info.plist (GateSecret); chạy `swift run` thì lấy từ env NOTIFICATION_SECRET.
    static let gateValue = (Bundle.main.object(forInfoDictionaryKey: "GateSecret") as? String)
        ?? ProcessInfo.processInfo.environment["NOTIFICATION_SECRET"] ?? ""

    static let shared = ServerClient()

    @Published var connected = false
    @Published var lastError: String?
    @Published var serverVersion: String?

    private let settings = AppSettings.shared
    private var task: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var retry = 0
    private var generation = 0
    private var pingTimer: Timer?

    // Clipboard
    private var pbTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastSent: String?
    private var lastImageHash: String? // ảnh vừa gửi / vừa nhận, chống vòng lặp
    static let maxImageBytes = 10 * 1024 * 1024

    func start() {
        Notifier.shared.requestAuthorization()
        connect()
        pbTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.pollPasteboard() }
    }

    func reconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        retry = 0
        connect()
    }

    // MARK: - Connection

    private func baseURL() -> URL? {
        var s = settings.serverURL.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    func request(_ path: String, method: String = "GET") -> URLRequest? {
        guard let base = baseURL() else { return nil }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(settings.accountKey)", forHTTPHeaderField: "Authorization")
        r.setValue(settings.deviceId, forHTTPHeaderField: "X-Device-Id")
        r.setValue(Self.gateValue, forHTTPHeaderField: Self.gateHeader)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    private func connect() {
        generation += 1
        let gen = generation
        guard settings.isConfigured, let base = baseURL(),
              var comps = URLComponents(url: base.appendingPathComponent("ws"), resolvingAgainstBaseURL: false) else {
            setStatus(false, "Chưa cấu hình")
            return
        }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.queryItems = [
            .init(name: "key", value: settings.accountKey),
            .init(name: "deviceId", value: settings.deviceId),
            .init(name: "name", value: settings.deviceName),
            .init(name: "platform", value: "mac"),
            .init(name: "version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"),
            .init(name: "encrypt", value: "1"),
        ]
        guard let url = comps.url else { return }
        var wsReq = URLRequest(url: url)
        wsReq.setValue(Self.gateValue, forHTTPHeaderField: Self.gateHeader)
        task = session.webSocketTask(with: wsReq)
        task?.maximumMessageSize = 32 * 1024 * 1024
        task?.resume()
        receive(gen)
    }

    private func receive(_ gen: Int) {
        task?.receive { [weak self] result in
            guard let self, gen == self.generation else { return }
            switch result {
            case .failure(let err):
                self.setStatus(false, err.localizedDescription)
                self.scheduleReconnect(gen)
            case .success(let msg):
                // encrypt=1: server chỉ gửi frame binary đã mã hoá bằng Kaga
                if case .data(let d) = msg, let s = Kaga.decode([UInt8](d), salt: Kaga.salt(for: self.settings.accountKey)) { self.handle(s) }
                self.receive(gen)
            }
        }
    }

    private func scheduleReconnect(_ gen: Int) {
        pingTimer?.invalidate()
        retry += 1
        let delay = min(30.0, pow(2.0, Double(min(retry, 5))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.connect()
        }
    }

    private func handle(_ s: String) {
        guard let data = s.data(using: .utf8), let m = try? JSONDecoder().decode(WSMessage.self, from: data) else { return }
        switch m.kind {
        case "hello":
            retry = 0
            setStatus(true, nil)
            DispatchQueue.main.async { self.serverVersion = m.version }
            DispatchQueue.main.async { [self] in
                self.pingTimer?.invalidate()
                self.pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                    self?.sendFrame("{\"kind\":\"ping\"}")
                }
            }
            catchUp()
            syncWhitelist()
            fetchLatestClipboard()
        case "event":
            if let e = try? JSONDecoder().decode(ServerEvent.self, from: data) { deliver(e) }
        case "clipboard":
            if m.type == "image", let h = m.hash { fetchRemoteImage(h) } else if let t = m.text { applyRemoteClipboard(t) }
        case "whitelist":
            if !settings.whitelistDirty, let en = m.enabled { settings.applyRemoteWhitelist(enabled: en, packages: m.packages ?? []) }
        default: break
        }
    }

    private func setStatus(_ ok: Bool, _ err: String?) {
        DispatchQueue.main.async { self.connected = ok; self.lastError = err }
    }

    // MARK: - Events

    private func deliver(_ e: ServerEvent) {
        if e.id > settings.lastEventId { settings.lastEventId = e.id }
        NotificationStore.shared.add([e])
        settings.learn([e])
        showWithIcon(e)
    }

    private func showWithIcon(_ e: ServerEvent) {
        guard e.type == "notification", settings.allows(e.packageName) else {
            if e.type == "call" { Notifier.shared.show(e, icon: nil) }
            return
        }
        guard let pkg = e.packageName else { return Notifier.shared.show(e, icon: nil) }
        IconCache.shared.fileURL(for: pkg) { url in Notifier.shared.show(e, icon: url) }
    }

    /// Lấy lịch sử để dựng danh sách; những sự kiện mới hơn lastEventId (bỏ lỡ lúc Mac offline) thì hiện thông báo.
    private func catchUp() {
        guard var req = request("api/history") else { return }
        req.url = URL(string: req.url!.absoluteString + "?limit=300")
        let since = settings.lastEventId
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data, let events = try? JSONDecoder().decode([ServerEvent].self, from: data) else { return }
            NotificationStore.shared.add(events)
            self.settings.learn(events)
            if let maxId = events.map(\.id).max(), maxId > self.settings.lastEventId { self.settings.lastEventId = maxId }
            // lần đầu cài (since == 0) không đổ cả lịch sử thành thông báo
            guard since > 0 else { return }
            let cutoff = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
            let missed = events.filter { $0.id > since && ($0.timestamp ?? 0) > cutoff && !($0.type == "call" && $0.state == "ringing") }
            for e in missed.suffix(20) { self.showWithIcon(e) }
        }.resume()
    }

    // MARK: - Whitelist (dùng chung theo account key)

    private var pushWork: DispatchWorkItem?

    /// Gộp nhiều thay đổi liên tiếp rồi đẩy một lần.
    func scheduleWhitelistPush() {
        pushWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.pushWhitelist() }
        pushWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    private func pushWhitelist() {
        guard var req = request("api/whitelist", method: "PUT") else { return }
        let body: [String: Any] = ["enabled": settings.whitelistEnabled, "packages": Array(settings.whitelist)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200 { self?.settings.whitelistDirty = false }
        }.resume()
    }

    /// Có thay đổi chưa đẩy được thì đẩy; không thì kéo bản của server về.
    private func syncWhitelist() {
        if settings.whitelistDirty { return pushWhitelist() }
        guard let req = request("api/whitelist") else { return }
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = o["enabled"] as? Bool else { return }
            self.settings.applyRemoteWhitelist(enabled: enabled, packages: o["packages"] as? [String] ?? [])
        }.resume()
    }

    // MARK: - Clipboard

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard settings.clipboardSync, connected else { return }
        // bỏ qua nội dung đánh dấu bí mật (password manager)
        if pb.types?.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" }) == true { return }
        // có text thì ưu tiên text (Word/Pages copy chữ cũng kèm ảnh preview); chỉ có ảnh mới gửi ảnh
        guard let text = pb.string(forType: .string), !text.isEmpty else {
            if let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff) { sendImage(raw) }
            return
        }
        guard text != lastSent else { return }
        lastSent = text
        lastImageHash = nil
        let payload = ["kind": "clipboard", "text": text]
        if let d = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: d, encoding: .utf8) {
            sendFrame(s)
        }
    }

    /// Mã hoá bằng Kaga rồi gửi dạng binary.
    private func sendFrame(_ json: String) {
        task?.send(.data(Data(Kaga.encode(json, salt: Kaga.salt(for: settings.accountKey))))) { _ in }
    }

    /// PNG/TIFF từ pasteboard -> PNG (quá lớn thì JPEG), upload qua HTTP; server báo hash cho các máy khác.
    private func sendImage(_ raw: Data) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let (data, mime) = Self.encodeImage(raw) else { return }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            DispatchQueue.main.async {
                guard hash != self.lastImageHash, var req = self.request("api/clipboard/image", method: "POST") else { return }
                self.lastImageHash = hash
                self.lastSent = nil
                req.setValue(mime, forHTTPHeaderField: "Content-Type")
                URLSession.shared.uploadTask(with: req, from: data).resume()
            }
        }
    }

    private static func encodeImage(_ raw: Data) -> (Data, String)? {
        if raw.starts(with: [0x89, 0x50, 0x4E, 0x47]), raw.count <= maxImageBytes { return (raw, "image/png") }
        guard let rep = NSBitmapImageRep(data: raw) else { return nil }
        if let png = rep.representation(using: .png, properties: [:]), png.count <= maxImageBytes { return (png, "image/png") }
        for q in [0.85, 0.6] {
            if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: q]), jpg.count <= maxImageBytes { return (jpg, "image/jpeg") }
        }
        return nil
    }

    private func fetchRemoteImage(_ hash: String) {
        guard settings.clipboardSync, hash != lastImageHash, let req = request("api/clipboard/image/\(hash)") else { return }
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self, let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let rep = NSBitmapImageRep(data: data), let tiff = rep.tiffRepresentation else { return }
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : rep.representation(using: .png, properties: [:])
            DispatchQueue.main.async {
                self.lastImageHash = hash // không gửi ngược lại
                self.lastSent = nil
                let item = NSPasteboardItem()
                if let png { item.setData(png, forType: .png) }
                item.setData(tiff, forType: .tiff)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([item])
                self.lastChangeCount = pb.changeCount
            }
        }.resume()
    }

    private func applyRemoteClipboard(_ text: String) {
        guard settings.clipboardSync else { return }
        DispatchQueue.main.async { [self] in
            let pb = NSPasteboard.general
            if pb.string(forType: .string) == text { return }
            self.lastSent = text // không gửi ngược lại
            self.lastImageHash = nil
            pb.clearContents()
            pb.setString(text, forType: .string)
            self.lastChangeCount = pb.changeCount
        }
    }

    private func fetchLatestClipboard() {
        guard settings.clipboardSync, let req = request("api/clipboard") else { return }
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  o["sourceDevice"] as? String != self.settings.deviceId else { return }
            if o["type"] as? String == "image", let hash = o["hash"] as? String { return self.fetchRemoteImage(hash) }
            if let text = o["content"] as? String, !text.isEmpty { self.applyRemoteClipboard(text) }
        }.resume()
    }
}
