import Foundation
import SwiftData

enum TrackedAppStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable
    case downloading
    case downloadedAwaitingInstall
    case failed

    var displayName: String {
        switch self {
        case .idle:
            return "空闲"
        case .checking:
            return "检查中"
        case .upToDate:
            return "已最新"
        case .updateAvailable:
            return "发现更新"
        case .downloading:
            return "下载中"
        case .downloadedAwaitingInstall:
            return "已下载待安装"
        case .failed:
            return "失败"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .checking:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .downloading:
            return "icloud.and.arrow.down.fill"
        case .downloadedAwaitingInstall:
            return "shippingbox.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

@Model
final class TrackedApp {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var sourcePageURL: String
    var localAppPath: String
    var lastSeenRemotePublishedAt: Date
    var installedPublishedAt: Date
    var lastCheckedAt: Date?
    var lastSeenRemoteVersion: String?
    var installedVersion: String?
    var lastDownloadURL: String?
    var lastDownloadedFilePath: String?
    private var statusRawValue: String
    var lastError: String?
    var activeDownloadID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        sourcePageURL: String,
        localAppPath: String,
        lastSeenRemotePublishedAt: Date,
        installedPublishedAt: Date,
        lastCheckedAt: Date? = nil,
        lastSeenRemoteVersion: String? = nil,
        installedVersion: String? = nil,
        lastDownloadURL: String? = nil,
        lastDownloadedFilePath: String? = nil,
        status: TrackedAppStatus = .idle,
        lastError: String? = nil,
        activeDownloadID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.sourcePageURL = sourcePageURL
        self.localAppPath = localAppPath
        self.lastSeenRemotePublishedAt = lastSeenRemotePublishedAt
        self.installedPublishedAt = installedPublishedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastSeenRemoteVersion = lastSeenRemoteVersion
        self.installedVersion = installedVersion
        self.lastDownloadURL = lastDownloadURL
        self.lastDownloadedFilePath = lastDownloadedFilePath
        self.statusRawValue = status.rawValue
        self.lastError = lastError
        self.activeDownloadID = activeDownloadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: TrackedAppStatus {
        get { TrackedAppStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    var sourceURLValue: URL? {
        URL(string: sourcePageURL)
    }

    var localAppURLValue: URL {
        URL(fileURLWithPath: localAppPath)
    }

    var downloadURLValue: URL? {
        guard let lastDownloadURL else { return nil }
        return URL(string: lastDownloadURL)
    }

    var downloadedFileURLValue: URL? {
        guard let lastDownloadedFilePath else { return nil }
        return URL(fileURLWithPath: lastDownloadedFilePath)
    }

    var needsInstallConfirmation: Bool {
        return installedPublishedAt < lastSeenRemotePublishedAt
    }

    var lastSeenRemoteVersionValue: String? {
        normalizedVersion(lastSeenRemoteVersion)
    }

    var installedVersionValue: String? {
        normalizedVersion(installedVersion)
    }

    var installedBundleVersionValue: String? {
        guard let bundle = Bundle(url: localAppURLValue) else {
            return nil
        }

        if let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let normalizedShortVersion = normalizedVersion(shortVersion) {
            return normalizedShortVersion
        }

        if let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let normalizedBundleVersion = normalizedVersion(bundleVersion) {
            return normalizedBundleVersion
        }

        return nil
    }

    func touch() {
        updatedAt = .now
    }

    private func normalizedVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]\s*"#, with: "", options: .regularExpression)
        return normalized.isEmpty ? nil : normalized
    }
}
