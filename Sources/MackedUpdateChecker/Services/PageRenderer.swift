import Foundation
import WebKit

@MainActor
enum SharedWebSession {
    static let websiteDataStore = WKWebsiteDataStore.default()

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = websiteDataStore
        configuration.suppressesIncrementalRendering = false
        return configuration
    }
}

@MainActor
protocol PageSnapshotProvider {
    func loadRenderedHTML(from url: URL) async throws -> RenderedPageSnapshot
}

enum PageRendererError: LocalizedError {
    case failedToRenderHTML
    case javaScriptEvaluationFailed
    case navigationFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .failedToRenderHTML:
            return "无法获取渲染后的 HTML。"
        case .javaScriptEvaluationFailed:
            return "JavaScript 执行失败。"
        case let .navigationFailed(reason):
            return "页面加载失败：\(reason)"
        case .timeout:
            return "页面渲染超时。"
        }
    }
}

@MainActor
final class WebKitPageRenderer: NSObject, PageSnapshotProvider {
    func loadRenderedHTML(from url: URL) async throws -> RenderedPageSnapshot {
        let session = PageLoadSession()
        return try await session.loadRenderedHTML(from: url)
    }
}

@MainActor
private final class PageLoadSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        webView = WKWebView(frame: .zero, configuration: SharedWebSession.makeConfiguration())
        webView.isHidden = true
        super.init()
        webView.navigationDelegate = self
    }

    func loadRenderedHTML(from url: URL) async throws -> RenderedPageSnapshot {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 45
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            self.timeoutTask?.cancel()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                await self?.resume(with: .failure(PageRendererError.timeout))
            }
            webView.load(request)
        }

        try await waitForDOMStability()
        let html = try await webView.evaluateJavaScriptString("document.documentElement.outerHTML")
        let finalURLString = try await webView.evaluateJavaScriptString("document.location.href")

        guard !html.isEmpty else {
            throw PageRendererError.failedToRenderHTML
        }

        return RenderedPageSnapshot(
            html: html,
            finalURL: URL(string: finalURLString) ?? webView.url ?? url,
            loadedAt: .now
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await resume(with: .success(()))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            await resume(with: .failure(PageRendererError.navigationFailed(error.localizedDescription)))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            await resume(with: .failure(PageRendererError.navigationFailed(error.localizedDescription)))
        }
    }

    private func waitForDOMStability() async throws {
        var previousSignature: String?
        var stableSamples = 0

        for _ in 0..<8 {
            let readyState = try await webView.evaluateJavaScriptString("document.readyState")
            let outerHTMLLength = try await webView.evaluateJavaScriptInt("document.documentElement.outerHTML.length")
            let bodyTextLength = try await webView.evaluateJavaScriptInt("document.body ? document.body.innerText.length : 0")
            let signature = "\(readyState)|\(outerHTMLLength)|\(bodyTextLength)"

            if signature == previousSignature, readyState == "complete" {
                stableSamples += 1
            } else {
                stableSamples = 0
                previousSignature = signature
            }

            if stableSamples >= 2 {
                return
            }

            try await Task.sleep(for: .milliseconds(700))
        }
    }

    private func resume(with result: Result<Void, Error>) async {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

@MainActor
extension WKWebView {
    func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: PageRendererError.failedToRenderHTML)
                }
            }
        }
    }

    func evaluateJavaScriptInt(_ script: String) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let intValue = result as? Int {
                    continuation.resume(returning: intValue)
                } else if let number = result as? NSNumber {
                    continuation.resume(returning: number.intValue)
                } else {
                    continuation.resume(throwing: PageRendererError.javaScriptEvaluationFailed)
                }
            }
        }
    }

    func evaluateJavaScriptBool(_ script: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let boolValue = result as? Bool {
                    continuation.resume(returning: boolValue)
                } else if let number = result as? NSNumber {
                    continuation.resume(returning: number.boolValue)
                } else {
                    continuation.resume(throwing: PageRendererError.javaScriptEvaluationFailed)
                }
            }
        }
    }
}
