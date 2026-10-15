// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotificationMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0")
    ],
    targets: [
        .executableTarget(
            name: "NotificationMac",
            dependencies: [.product(name: "Sentry", package: "sentry-cocoa")],
            path: "Sources/NotificationMac")
    ]
)
