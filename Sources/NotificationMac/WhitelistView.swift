import SwiftUI

/// Chọn app được hiện banner trên Mac. Danh sách app lấy từ các thông báo đã nhận (không cần Android).
struct WhitelistView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var query = ""
    @State private var pinned: Set<String> = []   // app đã bật lúc mở tab: lên đầu, không nhảy khi đang bật/tắt
    @State private var tick = 0

    private var apps: [(pkg: String, name: String)] {
        let q = query.lowercased()
        // app đã thấy thông báo + app chỉ có trong whitelist chung (chọn từ Android)
        var all = settings.knownApps
        for p in settings.whitelist where all[p] == nil { all[p] = p }
        return all
            .map { (pkg: $0.key, name: $0.value) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.pkg.contains(q) }
            .sorted {
                let p0 = pinned.contains($0.pkg), p1 = pinned.contains($1.pkg)
                if p0 != p1 { return p0 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Chỉ hiện thông báo của app đã chọn", isOn: $settings.whitelistEnabled)
            Text(settings.whitelistEnabled
                 ? "Dùng chung với Android theo account key. Android không gửi thông báo của app không chọn; Mac không hiện banner của chúng (vẫn lưu trong danh sách). Cuộc gọi luôn hiện."
                 : "Đang tắt: hiện thông báo của tất cả app.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Tìm app", text: $query).textFieldStyle(.roundedBorder)
                Button("Chọn hết") { settings.whitelist.formUnion(apps.map(\.pkg)) }
                Button("Bỏ hết") { settings.whitelist.subtract(apps.map(\.pkg)) }
            }
            if settings.knownApps.isEmpty {
                Spacer()
                Text("Chưa có app nào. App sẽ xuất hiện ở đây sau khi Android gửi thông báo của nó.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(apps, id: \.pkg) { app in
                    HStack(spacing: 8) {
                        icon(app.pkg)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.whitelist.contains(app.pkg) },
                            set: { on in
                                if on { settings.whitelist.insert(app.pkg) } else { settings.whitelist.remove(app.pkg) }
                            }))
                            .labelsHidden()
                    }
                }
            }
        }
        .padding()
        .onAppear { pinned = settings.whitelist }
    }

    @ViewBuilder
    private func icon(_ pkg: String) -> some View {
        let _ = tick
        Group {
            if let img = IconCache.shared.image(for: pkg, onLoad: { DispatchQueue.main.async { tick += 1 } }) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
