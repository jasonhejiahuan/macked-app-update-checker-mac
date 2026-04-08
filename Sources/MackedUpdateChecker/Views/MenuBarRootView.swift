import AppKit
import SwiftData
import SwiftUI

struct MenuBarRootView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TrackedApp.displayName) private var trackedApps: [TrackedApp]

    private var updateCount: Int {
        trackedApps.filter { $0.needsInstallConfirmation || $0.status == .updateAvailable || $0.status == .downloading || $0.status == .downloadedAwaitingInstall }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Macked Checker")
                    .font(.headline)
                Text("已追踪 \(trackedApps.count) 个应用，\(updateCount) 个需要处理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if controller.hasConfiguredLoginSite() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("账号状态：\(controller.loginStateSummary.status.displayName)")
                        .font(.subheadline.weight(.medium))
                    Text(controller.loginStateSummary.primaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    openWindow(id: SceneIdentifier.loginBrowser)
                } label: {
                    Label(
                        controller.loginStateSummary.status == .loggedIn ? "查看账号窗口" : "打开登录窗口",
                        systemImage: controller.loginStateSummary.status == .loggedIn ? "person.crop.circle" : "person.crop.circle.badge.plus"
                    )
                }
            }

            Button {
                Task {
                    await controller.checkAllNow()
                }
            } label: {
                Label(controller.isCheckingAll ? "检查中…" : "立即检查全部", systemImage: "arrow.clockwise")
            }
            .disabled(controller.isCheckingAll)

            Button {
                openWindow(id: SceneIdentifier.trackedApps)
            } label: {
                Label("管理应用", systemImage: "list.bullet.rectangle.portrait")
            }

            Divider()

            if trackedApps.isEmpty {
                Text("还没有追踪任何应用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(trackedApps.prefix(5))) { app in
                    HStack {
                        Image(systemName: app.status.systemImage)
                            .foregroundStyle(statusColor(for: app.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .lineLimit(1)
                            Text(app.status.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Divider()

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func statusColor(for status: TrackedAppStatus) -> Color {
        switch status {
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
}
