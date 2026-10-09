import SwiftUI

private struct AppGroup: Identifiable {
    let key: String
    let name: String
    let items: [ServerEvent]
    var id: String { key }
}

struct HistoryView: View {
    @ObservedObject var store = NotificationStore.shared
    @State private var query = ""

    private var groups: [AppGroup] {
        let q = query.lowercased()
        let filtered = store.items.filter {
            q.isEmpty || [$0.title, $0.text, $0.appName, $0.name, $0.number].compactMap { $0 }.contains { $0.lowercased().contains(q) }
        }
        let dict = Dictionary(grouping: filtered, by: NotificationStore.groupKey)
        return dict.map { key, items in
            AppGroup(key: key,
                     name: key == NotificationStore.callGroup ? "Cuộc gọi" : (items.first?.appName ?? key),
                     items: items)
        }
        .sorted { ($0.items.first?.id ?? 0) > ($1.items.first?.id ?? 0) }   // app có thông báo mới nhất lên đầu
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Tìm kiếm", text: $query).textFieldStyle(.roundedBorder)
                Button("Xóa tất cả") { store.clear() }.disabled(store.items.isEmpty)
            }
            .padding(10)
            Divider()
            if groups.isEmpty {
                Spacer()
                Text("Chưa có thông báo").foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            DisclosureGroup {
                                ForEach(group.items) { EventRow(event: $0) }
                            } label: {
                                groupHeader(group)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    private func groupHeader(_ g: AppGroup) -> some View {
        HStack(spacing: 8) {
            AppIconView(key: g.key)
            Text(g.name).fontWeight(.semibold)
            Spacer()
            Text("\(g.items.count)")
                .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            Button { store.clear(group: g.key) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).help("Xóa nhóm này")
        }
    }
}

private struct AppIconView: View {
    let key: String
    @State private var tick = 0   // vẽ lại khi icon tải xong

    var body: some View {
        let _ = tick
        Group {
            if key == NotificationStore.callGroup {
                Image(systemName: "phone.fill").resizable().scaledToFit().padding(5).foregroundStyle(.white).background(Color.green)
            } else if let img = IconCache.shared.image(for: key, onLoad: { DispatchQueue.main.async { tick += 1 } }) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct EventRow: View {
    let event: ServerEvent

    private var time: String {
        guard let t = event.timestamp else { return "" }
        let d = Date(timeIntervalSince1970: t / 1000)
        return Calendar.current.isDateInToday(d)
            ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(headline).font(.subheadline).fontWeight(.medium).lineLimit(1)
                Spacer()
                Text(time).font(.caption).foregroundStyle(.secondary)
            }
            if let body = detail, !body.isEmpty {
                Text(body).font(.callout).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private var headline: String {
        if event.type == "call" {
            let who = (event.name?.isEmpty == false ? event.name : event.number) ?? "Số lạ"
            switch event.state {
            case "ringing": return "Cuộc gọi đến · \(who)"
            case "missed": return "Cuộc gọi nhỡ · \(who)"
            case "answered": return "Đã nghe máy · \(who)"
            default: return who
            }
        }
        return event.title ?? ""
    }

    private var detail: String? { event.type == "call" ? event.number : event.text }
}
