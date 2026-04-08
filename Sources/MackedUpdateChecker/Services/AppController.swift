import AppKit
import Foundation
import SwiftData

@MainActor
final class AppController: ObservableObject {
    let modelContainer: ModelContainer

    @Published private(set) var settingsSnapshot = AppSettingsSnapshot()
    @Published private(set) var isCheckingAll = false
    @Published private(set) var loginStateSummary = LoginStateSummary.unknown
    @Published var transientMessage: String?

    private let parser: UpdateSourceParsing
    private let loginParser: LoginStatusParsing
    private let pageRenderer: PageSnapshotProvider
    private let notifications: NotificationCoordinator
    private let scheduler = CheckScheduler()
    private var started = false
    private var activeDownloadPollingTasks: [UUID: Task<Void, Never>] = [:]

    init(
        modelContainer: ModelContainer,
        parser: UpdateSourceParsing = UpdateParser(),
        loginParser: LoginStatusParsing = LoginStatusParser(),
        pageRenderer: PageSnapshotProvider = WebKitPageRenderer(),
        notifications: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.modelContainer = modelContainer
        self.parser = parser
        self.loginParser = loginParser
        self.pageRenderer = pageRenderer
        self.notifications = notifications
        _ = ensureSettings()
    }

    var modelContext: ModelContext {
        modelContainer.mainContext
    }

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        await notifications.prepareIfNeeded()
        await scheduleAutomaticChecks()
    }

    func addTrackedApp(displayName: String, sourcePageURLString: String, localAppPath: String) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL = URL(string: sourcePageURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = sourceURL.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw ValidationError.invalidSourceURL
        }

        let localURL = URL(fileURLWithPath: localAppPath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw ValidationError.localAppNotFound
        }

        if try hasDuplicateTrackedApp(sourcePageURL: sourceURL.absoluteString, localAppPath: localURL.path) {
            throw ValidationError.duplicateEntry
        }

        let snapshot = try await pageRenderer.loadRenderedHTML(from: sourceURL)
        let remoteInfo = try parser.parseRemoteVersionInfo(from: snapshot.html, baseURL: snapshot.finalURL)

        let trackedApp = TrackedApp(
            displayName: trimmedName.isEmpty ? localURL.deletingPathExtension().lastPathComponent : trimmedName,
            sourcePageURL: sourceURL.absoluteString,
            localAppPath: localURL.path,
            lastSeenRemotePublishedAt: remoteInfo.publishedAt,
            installedPublishedAt: remoteInfo.publishedAt,
            lastCheckedAt: .now,
            lastSeenRemoteVersion: remoteInfo.version,
            lastDownloadURL: remoteInfo.downloadURL?.absoluteString,
            status: .upToDate
        )

        modelContext.insert(trackedApp)
        try saveContext()
    }

    func deleteTrackedApps(ids: [UUID]) {
        for id in ids {
            if let app = try? fetchTrackedApp(id: id) {
                activeDownloadPollingTasks[id]?.cancel()
                activeDownloadPollingTasks[id] = nil
                modelContext.delete(app)
            }
        }

        try? saveContext()
    }

    func checkAllNow() async {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        defer { isCheckingAll = false }

        let appIDs = ((try? fetchTrackedApps()) ?? []).map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for appID in appIDs {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.checkTrackedApp(id: appID)
                }
            }
        }
    }

    func checkTrackedApp(id: UUID) async {
        guard let app = try? fetchTrackedApp(id: id), let sourceURL = app.sourceURLValue else {
            return
        }

        let previousStatus = app.status
        app.status = .checking
        app.lastError = nil
        app.lastCheckedAt = .now
        app.touch()
        try? saveContext()

        do {
            let snapshot = try await pageRenderer.loadRenderedHTML(from: sourceURL)
            let remoteInfo = try parser.parseRemoteVersionInfo(from: snapshot.html, baseURL: snapshot.finalURL)

            app.lastCheckedAt = .now
            app.lastDownloadURL = remoteInfo.downloadURL?.absoluteString
            app.lastSeenRemoteVersion = remoteInfo.version

            let hasDateChange = remoteInfo.publishedAt > app.lastSeenRemotePublishedAt

            if hasDateChange {
                app.lastSeenRemotePublishedAt = remoteInfo.publishedAt
                app.lastDownloadedFilePath = nil
                app.activeDownloadID = nil
                app.status = .updateAvailable
                app.touch()
                try saveContext()

                await notifications.sendUpdateFound(appName: app.displayName, publishedAt: remoteInfo.publishedAt)

                if let downloadURL = remoteInfo.downloadURL {
                    try await enqueueDownload(for: app, downloadURL: downloadURL)
                } else {
                    await annotateMissingDownloadLinkIfNeeded(for: app, sourceURL: sourceURL)
                }
            } else {
                applyStatusAfterNoVersionChange(for: app, previousStatus: previousStatus)
                if remoteInfo.downloadURL == nil {
                    await annotateMissingDownloadLinkIfNeeded(for: app, sourceURL: sourceURL)
                }
                app.touch()
                try saveContext()
            }
        } catch {
            app.status = .failed
            app.lastError = error.localizedDescription
            app.touch()
            try? saveContext()
        }
    }

    func retryDownload(id: UUID) async {
        guard let app = try? fetchTrackedApp(id: id),
              let downloadURL = app.downloadURLValue,
              app.sourceURLValue != nil else {
            return
        }

        do {
            try await enqueueDownload(for: app, downloadURL: downloadURL)
        } catch {
            app.status = .failed
            app.lastError = error.localizedDescription
            app.touch()
            try? saveContext()
        }
    }

    func markInstalled(id: UUID) {
        guard let app = try? fetchTrackedApp(id: id) else { return }
        app.installedPublishedAt = app.lastSeenRemotePublishedAt
        app.status = .upToDate
        app.lastError = nil
        app.activeDownloadID = nil
        app.touch()
        try? saveContext()
    }

    func revealDownloadedFile(id: UUID) {
        guard let app = try? fetchTrackedApp(id: id), let fileURL = app.downloadedFileURLValue else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func openLocalAppDirectory(id: UUID) {
        guard let app = try? fetchTrackedApp(id: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.localAppURLValue])
    }

    func saveSettings(_ snapshot: AppSettingsSnapshot) throws {
        let settings = ensureSettings()
        let trimmedLoginSiteHost = snapshot.loginSiteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let loginSiteChanged = settings.loginSiteHostValue != trimmedLoginSiteHost

        settings.checkIntervalHours = max(snapshot.checkIntervalHours, 1)
        settings.rpcBaseURL = snapshot.rpcBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.rpcKey = snapshot.rpcKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.loginSiteHostValue = trimmedLoginSiteHost
        if loginSiteChanged {
            settings.clearLoginState()
        }
        settings.touch()
        try saveContext()
        settingsSnapshot = AppSettingsSnapshot(settings: settings)
        loginStateSummary = makeLoginStateSummary(from: settings, message: loginSiteChanged ? "登录站点已更新，请重新检查登录状态。" : nil)

        Task {
            await scheduleAutomaticChecks()
        }
    }

    func currentSettingsSnapshot() -> AppSettingsSnapshot {
        settingsSnapshot
    }

    func currentLoginUserPageURL() -> URL? {
        try? buildLoginUserPageURL(from: settingsSnapshot.loginSiteHost)
    }

    func previewLoginUserPageURL(for rawValue: String) -> URL? {
        try? buildLoginUserPageURL(from: rawValue)
    }

    func hasConfiguredLoginSite() -> Bool {
        !settingsSnapshot.loginSiteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshLoginState(openLoginWindowIfNeeded: Bool = false) async -> Bool {
        guard let userPageURL = currentLoginUserPageURL() else {
            let message = ValidationError.invalidLoginSiteHost.localizedDescription
            applyLoginState(
                LoginStateSummary(status: .unknown, profile: nil, checkedAt: nil, userPageURL: nil, message: message),
                persist: false
            )
            return false
        }

        do {
            let snapshot = try await pageRenderer.loadRenderedHTML(from: userPageURL)
            let summary = loginParser.parseLoginState(from: snapshot.html, userPageURL: snapshot.finalURL)
            applyLoginState(summary, persist: true)
            return openLoginWindowIfNeeded && summary.status == .requiresLogin
        } catch {
            applyLoginState(
                LoginStateSummary(status: .unknown, profile: nil, checkedAt: .now, userPageURL: userPageURL, message: error.localizedDescription),
                persist: false
            )
            return false
        }
    }

    func updateLoginStateFromInteractivePage(html: String, finalURL: URL) {
        let summary = loginParser.parseLoginState(from: html, userPageURL: finalURL)
        applyLoginState(summary, persist: true)
    }

    func clearTransientMessage() {
        transientMessage = nil
    }

    private func scheduleAutomaticChecks() async {
        let interval = max(settingsSnapshot.checkIntervalHours, 1) * 3600
        await scheduler.start(interval: interval) { [weak self] in
            guard let self else { return }
            await self.checkAllNow()
        }
    }

    private func annotateMissingDownloadLinkIfNeeded(for app: TrackedApp, sourceURL: URL) async {
        guard matchesConfiguredLoginSite(sourceURL) else {
            app.lastError = "当前页面未解析到下载链接。"
            return
        }

        let needsLogin = await refreshLoginState(openLoginWindowIfNeeded: false)
        if loginStateSummary.status == .requiresLogin || needsLogin {
            app.lastError = "下载链接可能被登录态隐藏，请先在设置中打开交互式登录窗口完成登录。"
        } else {
            app.lastError = "当前页面未解析到下载链接。"
        }
    }

    private func enqueueDownload(for app: TrackedApp, downloadURL: URL) async throws {
        guard let sourcePageURL = app.sourceURLValue else {
            throw ValidationError.invalidSourceURL
        }

        let backend = try makeDownloadBackend()
        let request = DownloadRequest(
            appId: app.id,
            url: downloadURL,
            sourcePageURL: sourcePageURL,
            referer: sourcePageURL,
            suggestedFilename: suggestedFilename(for: app, downloadURL: downloadURL)
        )

        let job = try await backend.enqueue(request)
        app.lastDownloadURL = downloadURL.absoluteString
        app.activeDownloadID = job.id
        app.status = .downloading
        app.lastError = nil
        app.touch()
        try saveContext()

        activeDownloadPollingTasks[app.id]?.cancel()
        activeDownloadPollingTasks[app.id] = Task { [weak self] in
            guard let self else { return }
            await self.pollDownload(appID: app.id, jobID: job.id, backend: backend)
        }
    }

    private func pollDownload(appID: UUID, jobID: String, backend: HTTPDownloadBackend) async {
        defer {
            activeDownloadPollingTasks[appID] = nil
        }

        for _ in 0..<120 {
            guard let app = try? fetchTrackedApp(id: appID) else { return }

            do {
                let status = try await backend.status(for: jobID)
                switch status.state {
                case .queued, .running, .unknown:
                    app.status = .downloading
                    app.lastError = nil
                    app.touch()
                    try? saveContext()
                case .completed:
                    app.status = .downloadedAwaitingInstall
                    app.lastDownloadedFilePath = status.filePath
                    app.lastError = nil
                    app.activeDownloadID = nil
                    app.touch()
                    try? saveContext()
                    await notifications.sendDownloadCompleted(appName: app.displayName)
                    return
                case .failed:
                    app.status = .failed
                    app.lastError = status.errorMessage ?? "下载失败"
                    app.activeDownloadID = nil
                    app.touch()
                    try? saveContext()
                    return
                }
            } catch {
                app.status = .failed
                app.lastError = error.localizedDescription
                app.activeDownloadID = nil
                app.touch()
                try? saveContext()
                return
            }

            try? await Task.sleep(for: .seconds(3))
        }

        if let app = try? fetchTrackedApp(id: appID) {
            app.status = .failed
            app.lastError = "下载轮询超时"
            app.activeDownloadID = nil
            app.touch()
            try? saveContext()
        }
    }

    private func applyStatusAfterNoVersionChange(for app: TrackedApp, previousStatus: TrackedAppStatus) {
        if app.needsInstallConfirmation {
            if app.lastDownloadedFilePath != nil {
                app.status = .downloadedAwaitingInstall
            } else if app.activeDownloadID != nil || previousStatus == .downloading {
                app.status = .downloading
            } else {
                app.status = .updateAvailable
            }
        } else {
            app.status = .upToDate
        }
        app.lastError = nil
    }

    private func ensureSettings() -> AppSettings {
        if let existing = try? fetchSettings() {
            settingsSnapshot = AppSettingsSnapshot(settings: existing)
            loginStateSummary = makeLoginStateSummary(from: existing, message: nil)
            return existing
        }

        let settings = AppSettings()
        modelContext.insert(settings)
        try? saveContext()
        settingsSnapshot = AppSettingsSnapshot(settings: settings)
        loginStateSummary = makeLoginStateSummary(from: settings, message: nil)
        return settings
    }

    private func makeDownloadBackend() throws -> HTTPDownloadBackend {
        guard let baseURL = URL(string: settingsSnapshot.rpcBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DownloadBackendError.invalidBaseURL(settingsSnapshot.rpcBaseURL)
        }

        return HTTPDownloadBackend(baseURL: baseURL, apiKey: settingsSnapshot.rpcKey)
    }

    private func suggestedFilename(for app: TrackedApp, downloadURL: URL) -> String {
        let baseName = app.displayName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()

        let fallbackExtension = downloadURL.pathExtension.isEmpty ? "bin" : downloadURL.pathExtension
        return "\(baseName.isEmpty ? "download" : baseName)-latest.\(fallbackExtension)"
    }

    private func matchesConfiguredLoginSite(_ sourceURL: URL) -> Bool {
        guard let loginUserPageURL = currentLoginUserPageURL(),
              let loginHost = loginUserPageURL.host?.lowercased(),
              let sourceHost = sourceURL.host?.lowercased() else {
            return false
        }
        return sourceHost == loginHost
    }

    private func buildLoginUserPageURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.invalidLoginSiteHost
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let candidateURL = URL(string: candidate),
              let scheme = candidateURL.scheme,
              let host = candidateURL.host,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw ValidationError.invalidLoginSiteHost
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = candidateURL.port
        components.path = "/user"

        guard let finalURL = components.url else {
            throw ValidationError.invalidLoginSiteHost
        }

        return finalURL
    }

    private func applyLoginState(_ summary: LoginStateSummary, persist: Bool) {
        loginStateSummary = summary
        transientMessage = summary.message

        guard persist else { return }
        let settings = ensureSettings()
        settings.loginState = summary.status
        settings.loginDisplayName = summary.profile?.displayName
        settings.loginMembershipLabel = summary.profile?.membershipLabel
        settings.loginLevelLabel = summary.profile?.levelLabel
        settings.lastLoginCheckAt = summary.checkedAt
        settings.touch()
        try? saveContext()
        settingsSnapshot = AppSettingsSnapshot(settings: settings)
    }

    private func makeLoginStateSummary(from settings: AppSettings, message: String?) -> LoginStateSummary {
        let profile: LoginAccountProfile?
        if let displayName = settings.loginDisplayName, !displayName.isEmpty {
            var badges: [String] = []
            if let membership = settings.loginMembershipLabel, !membership.isEmpty {
                badges.append(membership)
            }
            if let level = settings.loginLevelLabel, !level.isEmpty {
                badges.append(level)
            }
            profile = LoginAccountProfile(
                displayName: displayName,
                membershipLabel: settings.loginMembershipLabel,
                levelLabel: settings.loginLevelLabel,
                badges: badges
            )
        } else {
            profile = nil
        }

        return LoginStateSummary(
            status: settings.loginState,
            profile: profile,
            checkedAt: settings.lastLoginCheckAt,
            userPageURL: try? buildLoginUserPageURL(from: settings.loginSiteHostValue),
            message: message
        )
    }

    private func fetchTrackedApps() throws -> [TrackedApp] {
        try modelContext.fetch(FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\TrackedApp.displayName)]))
    }

    private func fetchTrackedApp(id: UUID) throws -> TrackedApp {
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.id == id })
        guard let app = try modelContext.fetch(descriptor).first else {
            throw ValidationError.trackedAppNotFound
        }
        return app
    }

    private func hasDuplicateTrackedApp(sourcePageURL: String, localAppPath: String) throws -> Bool {
        let descriptor = FetchDescriptor<TrackedApp>()
        let existingApps = try modelContext.fetch(descriptor)
        return existingApps.contains { $0.sourcePageURL == sourcePageURL || $0.localAppPath == localAppPath }
    }

    private func fetchSettings() throws -> AppSettings? {
        let singletonKey = AppSettings.singletonKey
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.key == singletonKey })
        return try modelContext.fetch(descriptor).first
    }

    private func saveContext() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}

enum ValidationError: LocalizedError {
    case invalidSourceURL
    case localAppNotFound
    case duplicateEntry
    case trackedAppNotFound
    case invalidLoginSiteHost

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return "请输入有效的 source page 链接。"
        case .localAppNotFound:
            return "未找到本地 .app 路径。"
        case .duplicateEntry:
            return "该页面或本地 App 已被追踪。"
        case .trackedAppNotFound:
            return "未找到对应的追踪条目。"
        case .invalidLoginSiteHost:
            return "请输入有效的登录站点，例如 example.app。"
        }
    }
}
