import SwiftData
import SwiftUI

@main
struct MackedUpdateCheckerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller: AppController

    init() {
        let modelContainer = PersistenceController.shared
        _controller = StateObject(wrappedValue: AppController(modelContainer: modelContainer))
    }

    var body: some Scene {
        MenuBarExtra("Macked Checker", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
            MenuBarRootView()
                .environmentObject(controller)
                .modelContainer(controller.modelContainer)
                .task {
                    await controller.startIfNeeded()
                }
        }

        Window("Tracked Apps", id: SceneIdentifier.trackedApps) {
            TrackedAppsWindowView()
                .environmentObject(controller)
                .modelContainer(controller.modelContainer)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    await controller.startIfNeeded()
                }
        }
        .defaultSize(width: 980, height: 640)

        Window("账号登录", id: SceneIdentifier.loginBrowser) {
            LoginBrowserWindowView()
                .environmentObject(controller)
                .modelContainer(controller.modelContainer)
                .task {
                    await controller.startIfNeeded()
                }
        }
        .defaultSize(width: 980, height: 760)

        Settings {
            SettingsView()
                .environmentObject(controller)
                .modelContainer(controller.modelContainer)
                .task {
                    await controller.startIfNeeded()
                }
        }
    }
}

enum SceneIdentifier {
    static let trackedApps = "tracked-apps-window"
    static let loginBrowser = "login-browser-window"
}
