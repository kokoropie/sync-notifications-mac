import Foundation
import AppKit

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
    let text: String?
    let enabled: Bool?
    let packages: [String]?
}

/// Kết nối WebSocket tới server, tự reconnect, đồng bộ clipboard hai chiều.
final class ServerClient: ObservableObject {
    static let shared = ServerClient()

    @Published var connected = false
    @Published var lastError: String?

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
        ]
        guard let url = comps.url else { return }
        task = session.webSocketTask(with: url)
        task?.maximumMessageSize = 4 * 1024 * 1024
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
                if case .string(let s) = msg { self.handle(s) }
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
            DispatchQueue.main.async { [self] in
                self.pingTimer?.invalidate()
                self.pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                    self?.task?.send(.string("{\"kind\":\"ping\"}")) { _ in }
                }
            }
            catchUp()
            syncWhitelist()
            fetchLatestClipboard()
        case "event":
            if let e = try? JSONDecoder().decode(ServerEvent.self, from: data) { deliver(e) }
        case "clipboard":
            if let t = m.text { applyRemoteClipboard(t) }
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
        guard settings.clipboardSync, connected, let text = pb.string(forType: .string), !text.isEmpty, text != lastSent else { return }
        // bỏ qua nội dung đánh dấu bí mật (password manager)
        if pb.types?.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" }) == true { return }
        lastSent = text
        let payload = ["kind": "clipboard", "text": text]
        if let d = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: d, encoding: .utf8) {
            task?.send(.string(s)) { _ in }
        }
    }

    private func applyRemoteClipboard(_ text: String) {
        guard settings.clipboardSync else { return }
        DispatchQueue.main.async { [self] in
            let pb = NSPasteboard.general
            if pb.string(forType: .string) == text { return }
            self.lastSent = text // không gửi ngược lại
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
                  let text = o["content"] as? String, o["sourceDevice"] as? String != self.settings.deviceId else { return }
            self.applyRemoteClipboard(text)
        }.resume()
    }
}
