import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow

    @State private var snapshot = AppSettingsSnapshot()
    @State private var saveMessage: String?
    @State private var errorMessage: String?
    @State private var isRefreshingLoginState = false

    var body: some View {
        Form {
            Section("检查频率") {
                Stepper(value: $snapshot.checkIntervalHours, in: 1 ... 48, step: 1) {
                    Text("每 \(Int(snapshot.checkIntervalHours)) 小时自动检查一次")
                }
            }

            Section("RPC 下载器") {
                TextField("RPC Base URL", text: $snapshot.rpcBaseURL)
                SecureField("RPC Key", text: $snapshot.rpcKey)
            }

            Section("登录站点") {
                TextField("站点 Host，例如 example.app", text: $snapshot.loginSiteHost)

                if let previewURL = controller.previewLoginUserPageURL(for: snapshot.loginSiteHost) {
                    LabeledContent("用户页") {
                        Text(previewURL.absoluteString)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("保存后将使用 https://<你的站点>/user 检查登录状态。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LoginStateSummaryView(summary: controller.loginStateSummary)

                HStack {
                    Button {
                        Task {
                            await refreshLoginState()
                        }
                    } label: {
                        Label(isRefreshingLoginState ? "检查中…" : "检查登录状态", systemImage: "person.crop.circle.badge.questionmark")
                    }
                    .disabled(isRefreshingLoginState)

                    Button {
                        openInteractiveLoginWindow()
                    } label: {
                        Label("打开交互式登录窗口", systemImage: "safari")
                    }
                    .disabled(snapshot.loginSiteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("若用户页显示“Hi！Please log in / Hi！请登录”，应用会打开交互式窗口，并自动尝试点击登录入口；登录成功后会共享同一登录态给后台检查器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("恢复默认") {
                        snapshot = AppSettingsSnapshot()
                        saveMessage = nil
                        errorMessage = nil
                    }

                    Spacer()

                    Button("保存设置") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .foregroundStyle(.green)
                        .font(.footnote)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 560)
        .onAppear {
            snapshot = controller.currentSettingsSnapshot()
        }
    }

    private func saveSettings() {
        do {
            try controller.saveSettings(snapshot)
            snapshot = controller.currentSettingsSnapshot()
            errorMessage = nil
            saveMessage = "设置已保存，并重新安排自动检查。"
        } catch {
            saveMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func saveSettingsForLoginAction() throws {
        try controller.saveSettings(snapshot)
        snapshot = controller.currentSettingsSnapshot()
        errorMessage = nil
    }

    private func openInteractiveLoginWindow() {
        do {
            try saveSettingsForLoginAction()
            openWindow(id: SceneIdentifier.loginBrowser)
        } catch {
            errorMessage = error.localizedDescription
            saveMessage = nil
        }
    }

    @MainActor
    private func refreshLoginState() async {
        do {
            try saveSettingsForLoginAction()
            isRefreshingLoginState = true
            let shouldOpenLoginWindow = await controller.refreshLoginState(openLoginWindowIfNeeded: true)
            isRefreshingLoginState = false
            if shouldOpenLoginWindow {
                openWindow(id: SceneIdentifier.loginBrowser)
            }
            saveMessage = "登录状态已刷新。"
            errorMessage = nil
        } catch {
            isRefreshingLoginState = false
            saveMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoginStateSummaryView: View {
    let summary: LoginStateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(summary.status.displayName, systemImage: iconName)
                    .foregroundStyle(iconColor)
                Spacer()
                if let checkedAt = summary.checkedAt {
                    Text(Self.dateFormatter.string(from: checkedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary.primaryText)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let profile = summary.profile {
                if let membership = profile.membershipLabel, !membership.isEmpty {
                    LabeledContent("会员/身份") {
                        Text(membership)
                            .foregroundStyle(.secondary)
                    }
                }
                if let level = profile.levelLabel, !level.isEmpty {
                    LabeledContent("等级") {
                        Text(level)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let userPageURL = summary.userPageURL {
                LabeledContent("检查地址") {
                    Text(userPageURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconName: String {
        switch summary.status {
        case .unknown:
            return "questionmark.circle"
        case .requiresLogin:
            return "person.crop.circle.badge.exclamationmark"
        case .loggedIn:
            return "person.crop.circle.badge.checkmark"
        }
    }

    private var iconColor: Color {
        switch summary.status {
        case .unknown:
            return .secondary
        case .requiresLogin:
            return .orange
        case .loggedIn:
            return .green
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct LoginBrowserWindowView: View {
    @EnvironmentObject private var controller: AppController
    @StateObject private var viewModel = LoginBrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("交互式登录")
                        .font(.title3.weight(.semibold))
                    Text(viewModel.helperText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let currentURLString = viewModel.currentURLString {
                        Text(currentURLString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                HStack {
                    Button {
                        viewModel.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canGoBack)

                    Button {
                        viewModel.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding(16)

            Divider()

            if viewModel.hasConfiguredSite {
                InteractiveLoginWebView(webView: viewModel.webView)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.isLoading {
                            ProgressView()
                                .padding(12)
                        }
                    }
            } else {
                ContentUnavailableView(
                    "请先在设置中填写登录站点",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("填写 example.app 这类站点 Host 后，再打开交互式登录窗口。")
                )
            }

            Divider()

            LoginStateSummaryView(summary: controller.loginStateSummary)
                .padding(16)
        }
        .frame(minWidth: 960, minHeight: 720)
        .task {
            await viewModel.configureIfNeeded(controller: controller)
        }
    }
}

@MainActor
private final class LoginBrowserViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var helperText = "准备打开用户页…"
    @Published var currentURLString: String?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var hasConfiguredSite = false

    let webView: WKWebView

    private weak var controller: AppController?
    private let parser = LoginStatusParser()
    private var didAttemptAutoClick = false
    private var lastConfiguredURLString: String?

    override init() {
        webView = WKWebView(frame: .zero, configuration: SharedWebSession.makeConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func configureIfNeeded(controller: AppController) async {
        self.controller = controller
        hasConfiguredSite = controller.hasConfiguredLoginSite()
        guard let userPageURL = controller.currentLoginUserPageURL() else {
            helperText = "请先在设置中配置登录站点。"
            currentURLString = nil
            return
        }

        if lastConfiguredURLString != userPageURL.absoluteString {
            lastConfiguredURLString = userPageURL.absoluteString
            didAttemptAutoClick = false
            load(url: userPageURL)
        }
    }

    func reload() {
        didAttemptAutoClick = false
        if webView.url == nil, let url = controller?.currentLoginUserPageURL() {
            load(url: url)
        } else {
            webView.reload()
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        currentURLString = webView.url?.absoluteString
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURLString = webView.url?.absoluteString
        canGoBack = webView.canGoBack
        helperText = "页面已加载，正在检测登录状态…"
        Task { @MainActor in
            await inspectCurrentPage()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        helperText = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        helperText = error.localizedDescription
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }

    private func load(url: URL) {
        hasConfiguredSite = true
        currentURLString = url.absoluteString
        helperText = "正在打开用户页…"
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45))
    }

    private func inspectCurrentPage() async {
        do {
            let html = try await webView.evaluateJavaScriptString("document.documentElement.outerHTML")
            let finalURLString = try await webView.evaluateJavaScriptString("document.location.href")
            let finalURL = URL(string: finalURLString) ?? webView.url ?? controller?.currentLoginUserPageURL()
            let summary = parser.parseLoginState(from: html, userPageURL: finalURL)
            if let finalURL {
                controller?.updateLoginStateFromInteractivePage(html: html, finalURL: finalURL)
            }
            helperText = summary.primaryText

            if summary.status == .requiresLogin, !didAttemptAutoClick {
                didAttemptAutoClick = true
                let clicked = try await webView.evaluateJavaScriptBool(Self.autoClickLoginScript)
                if clicked {
                    helperText = "已尝试点击登录入口，请在网页弹出的窗口/弹层中完成登录。"
                }
            } else if summary.status == .loggedIn {
                didAttemptAutoClick = false
            }
        } catch {
            helperText = error.localizedDescription
        }
    }

    private static let autoClickLoginScript = #"""
    (() => {
      const candidates = Array.from(document.querySelectorAll('a.display-name'));
      const target = candidates.find((node) => {
        const text = (node.textContent || '').trim().toLowerCase();
        return text.includes('please log in') || text.includes('请登录');
      });
      if (!target) return false;
      target.click();
      return true;
    })();
    """#
}

private struct InteractiveLoginWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
