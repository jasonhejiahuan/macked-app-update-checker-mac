import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var key: String
    var checkIntervalHours: Double
    var rpcBaseURL: String
    var rpcKey: String
    var loginSiteHost: String?
    private var loginStateRawValue: String?
    var loginDisplayName: String?
    var loginMembershipLabel: String?
    var loginLevelLabel: String?
    var lastLoginCheckAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        key: String = "default",
        checkIntervalHours: Double = 6,
        rpcBaseURL: String = "http://127.0.0.1:16800",
        rpcKey: String = "vQRvPS4LCV4E",
        loginSiteHost: String = "",
        loginState: LoginStateStatus = .unknown,
        loginDisplayName: String? = nil,
        loginMembershipLabel: String? = nil,
        loginLevelLabel: String? = nil,
        lastLoginCheckAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.checkIntervalHours = checkIntervalHours
        self.rpcBaseURL = rpcBaseURL
        self.rpcKey = rpcKey
        self.loginSiteHost = loginSiteHost
        self.loginStateRawValue = loginState.rawValue
        self.loginDisplayName = loginDisplayName
        self.loginMembershipLabel = loginMembershipLabel
        self.loginLevelLabel = loginLevelLabel
        self.lastLoginCheckAt = lastLoginCheckAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let singletonKey = "default"

    var rpcURLValue: URL? {
        URL(string: rpcBaseURL)
    }

    var loginState: LoginStateStatus {
        get { LoginStateStatus(rawValue: loginStateRawValue ?? "") ?? .unknown }
        set { loginStateRawValue = newValue.rawValue }
    }

    var loginSiteHostValue: String {
        get { loginSiteHost ?? "" }
        set { loginSiteHost = newValue }
    }

    func clearLoginState() {
        loginState = .unknown
        loginDisplayName = nil
        loginMembershipLabel = nil
        loginLevelLabel = nil
        lastLoginCheckAt = nil
    }

    func touch() {
        updatedAt = .now
    }
}

struct AppSettingsSnapshot: Sendable, Equatable {
    var checkIntervalHours: Double
    var rpcBaseURL: String
    var rpcKey: String
    var loginSiteHost: String

    init(
        checkIntervalHours: Double = 6,
        rpcBaseURL: String = "http://127.0.0.1:16800",
        rpcKey: String = "vQRvPS4LCV4E",
        loginSiteHost: String = ""
    ) {
        self.checkIntervalHours = checkIntervalHours
        self.rpcBaseURL = rpcBaseURL
        self.rpcKey = rpcKey
        self.loginSiteHost = loginSiteHost
    }

    init(settings: AppSettings) {
        self.checkIntervalHours = settings.checkIntervalHours
        self.rpcBaseURL = settings.rpcBaseURL
        self.rpcKey = settings.rpcKey
        self.loginSiteHost = settings.loginSiteHostValue
    }
}
