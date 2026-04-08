import SwiftUI

struct TrackedAppRowView: View {
    @EnvironmentObject private var controller: AppController

    let app: TrackedApp

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: app.status.systemImage)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(app.displayName)
                            .font(.headline)
                        Spacer()
                        StatusBadge(text: app.status.displayName, color: statusColor)
                    }

                    Text(app.sourcePageURL)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    LabeledContent("本地 App") {
                        Text(app.localAppPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("已安装日期") {
                        Text(Self.publishedDateFormatter.string(from: app.installedPublishedAt))
                            .foregroundStyle(.secondary)
                    }

                    if let installedVersion = app.installedBundleVersionValue ?? app.installedVersionValue {
                        LabeledContent("已安装版本号") {
                            Text(installedVersion)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("远端更新日期") {
                        Text(Self.publishedDateFormatter.string(from: app.lastSeenRemotePublishedAt))
                            .foregroundStyle(.secondary)
                    }

                    if let remoteVersion = app.lastSeenRemoteVersionValue {
                        LabeledContent("远端版本号") {
                            Text(remoteVersion)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastCheckedAt = app.lastCheckedAt {
                        LabeledContent("上次检查") {
                            Text(Self.dateFormatter.string(from: lastCheckedAt))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastError = app.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await controller.checkTrackedApp(id: app.id)
                    }
                } label: {
                    Label("检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    controller.openLocalAppDirectory(id: app.id)
                } label: {
                    Label("打开本地 App", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if app.status == .updateAvailable || app.status == .failed {
                    Button {
                        Task {
                            await controller.retryDownload(id: app.id)
                        }
                    } label: {
                        Label("下载更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if app.lastDownloadedFilePath != nil {
                    Button {
                        controller.revealDownloadedFile(id: app.id)
                    } label: {
                        Label("显示下载文件", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)
                }

                if app.needsInstallConfirmation {
                    Button {
                        controller.markInstalled(id: app.id)
                    } label: {
                        Label("我已完成安装", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch app.status {
        case .idle:
            return .secondary
        case .checking:
            return .blue
        case .upToDate:
            return .green
        case .updateAvailable:
            return .orange
        case .downloading:
            return .blue
        case .downloadedAwaitingInstall:
            return .mint
        case .failed:
            return .red
        }
    }

    private static let publishedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
