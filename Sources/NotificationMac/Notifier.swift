import Foundation
import UserNotifications

/// Hiển thị thông báo/cuộc gọi của Android trên macOS.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    func requestAuthorization() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(_ event: ServerEvent, icon: URL?) {
        let content = UNMutableNotificationContent()
        switch event.type {
        case "call":
            let who = (event.name?.isEmpty == false ? event.name : event.number) ?? "Số lạ"
            switch event.state {
            case "ringing": content.title = "📞 Cuộc gọi đến"; content.body = who
            case "missed": content.title = "📵 Cuộc gọi nhỡ"; content.body = who
            case "answered": content.title = "📞 Đã nghe máy"; content.body = who
            default: return
            }
            if let n = event.number, event.name?.isEmpty == false { content.subtitle = n }
            content.sound = event.state == "ringing" ? .defaultCritical : .default
        default:
            content.title = [event.appName, event.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if content.title.isEmpty { content.title = "Thông báo Android" }
            content.body = event.text ?? ""
            if let sub = event.subText, !sub.isEmpty { content.subtitle = sub }
            content.sound = .default
        }
        // macOS luôn dùng icon của chính app này cho thông báo; logo app Android hiện dạng ảnh đính kèm bên phải
        // (macOS di chuyển file đính kèm đi nên phải đưa bản copy, giữ nguyên file trong cache)
        if let icon {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            if (try? FileManager.default.copyItem(at: icon, to: tmp)) != nil,
               let att = try? UNNotificationAttachment(identifier: "icon", url: tmp, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]) {
                content.attachments = [att]
            }
        }
        // Cùng id -> thay thế thay vì chồng thông báo
        let req = UNNotificationRequest(identifier: "ev-\(event.type)-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Hiện banner cả khi app đang active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
