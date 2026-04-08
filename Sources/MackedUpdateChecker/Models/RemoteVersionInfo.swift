import Foundation

struct RenderedPageSnapshot: Sendable {
    let html: String
    let finalURL: URL
    let loadedAt: Date
}

struct RemoteVersionInfo: Sendable, Equatable {
    let publishedAt: Date
    let version: String?
    let downloadURL: URL?
}

enum LoginStateStatus: String, Codable, Equatable, Sendable {
    case unknown
    case requiresLogin
    case loggedIn

    var displayName: String {
        switch self {
        case .unknown:
            return "未检测"
        case .requiresLogin:
            return "未登录"
        case .loggedIn:
            return "已登录"
        }
    }
}

struct LoginAccountProfile: Equatable, Sendable {
    let displayName: String
    let membershipLabel: String?
    let levelLabel: String?
    let badges: [String]

    var summaryText: String {
        var segments = [displayName]
        if let membershipLabel, !membershipLabel.isEmpty {
            segments.append(membershipLabel)
        }
        if let levelLabel, !levelLabel.isEmpty {
            segments.append(levelLabel)
        }
        return segments.joined(separator: " · ")
    }
}

struct LoginStateSummary: Equatable, Sendable {
    let status: LoginStateStatus
    let profile: LoginAccountProfile?
    let checkedAt: Date?
    let userPageURL: URL?
    let message: String?

    static let unknown = LoginStateSummary(status: .unknown, profile: nil, checkedAt: nil, userPageURL: nil, message: nil)

    var primaryText: String {
        switch status {
        case .unknown:
            return message ?? "尚未检查登录状态"
        case .requiresLogin:
            return message ?? "当前账号未登录"
        case .loggedIn:
            return profile?.summaryText ?? "已登录"
        }
    }
}

struct DownloadRequest: Codable, Equatable, Sendable {
    let appId: UUID
    let url: URL
    let sourcePageURL: URL
    let referer: URL
    let suggestedFilename: String
}

enum DownloadState: String, Codable, Equatable, Sendable {
    case queued
    case running
    case completed
    case failed
    case unknown
}

struct DownloadJob: Equatable, Sendable {
    let id: String
    let state: DownloadState
}

struct DownloadJobStatus: Equatable, Sendable {
    let jobID: String
    let state: DownloadState
    let filePath: String?
    let errorMessage: String?

    var isTerminal: Bool {
        switch state {
        case .completed, .failed:
            return true
        case .queued, .running, .unknown:
            return false
        }
    }
}
