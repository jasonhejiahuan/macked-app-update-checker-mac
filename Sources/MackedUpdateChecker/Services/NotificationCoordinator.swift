import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator {
    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func prepareIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await requestAuthorization()
    }

    func sendUpdateFound(appName: String, publishedAt: Date) async {
        await prepareIfNeeded()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        await sendNotification(
            id: "update-found-\(appName)-\(publishedAt.timeIntervalSince1970)",
            title: "发现新版本",
            body: "\(appName) 有新版本，发布时间：\(formatter.string(from: publishedAt))"
        )
    }

    func sendDownloadCompleted(appName: String) async {
        await prepareIfNeeded()
        await sendNotification(
            id: "download-completed-\(appName)-\(UUID().uuidString)",
            title: "下载完成",
            body: "\(appName) 已下载完成，请安装后在应用内标记为已安装。"
        )
    }

    private func sendNotification(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await add(request)
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
