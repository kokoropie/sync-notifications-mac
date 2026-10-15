import Foundation
import Sentry

/// Báo lỗi/crash lên sentry.io. DSN do build.sh ghi vào Info.plist (SentryDSN); không có DSN hoặc bản debug thì tắt.
/// Không gửi PII, nội dung thông báo, clipboard hay header xác thực.
enum CrashReporting {
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, !dsn.isEmpty,
              Bundle.main.object(forInfoDictionaryKey: "IsDebugBuild") as? Bool != true else { return }
        SentrySDK.start { o in
            o.dsn = dsn
            o.releaseName = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            o.sendDefaultPii = false
            o.enableNetworkBreadcrumbs = false
            o.enableNetworkTracking = false
            o.enableCaptureFailedRequests = false
            o.tracesSampleRate = 0
            o.beforeBreadcrumb = { crumb in
                crumb.category == "http" || crumb.category == "console" ? nil : crumb
            }
            o.beforeSend = { event in
                event.user = nil
                event.request = nil
                return event
            }
        }
    }
}
