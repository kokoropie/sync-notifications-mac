import Foundation

/// Lịch sử thông báo/cuộc gọi, lưu trên đĩa, dùng để hiện danh sách nhóm theo app.
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()
    private let limit = 500

    @Published private(set) var items: [ServerEvent] = []   // mới nhất ở đầu

    private let file: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotificationMac")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ServerEvent].self, from: data) {
            items = saved
        }
    }

    func add(_ events: [ServerEvent]) {
        DispatchQueue.main.async {
            let known = Set(self.items.map(\.id))
            let fresh = events.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }
            self.items = Array((fresh + self.items).sorted { $0.id > $1.id }.prefix(self.limit))
            self.save()
        }
    }

    func clear(group key: String? = nil) {
        if let key { items.removeAll { Self.groupKey($0) == key } } else { items.removeAll() }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: file, options: .atomic) }
    }

    static let callGroup = "__calls__"
    static func groupKey(_ e: ServerEvent) -> String { e.type == "call" ? callGroup : (e.packageName ?? e.appName ?? "unknown") }
}
