import Foundation
import XCTest
@testable import MackedUpdateChecker

final class UpdateParserTests: XCTestCase {
    func testParsesSoftwareVersionFromMetadataField() throws {
        let html = #"""
        <div class="pay-attr mt10">
          <div class="flex jsb"><span class="attr-key">Software name</span><span class="attr-value">MacParakeet</span></div>
          <div class="flex jsb"><span class="attr-key">Software version</span><span class="attr-value">0.5.5</span></div>
          <div class="flex jsb"><span class="attr-key">File size</span><span class="attr-value">200 MB</span></div>
          <div class="flex jsb"><span class="attr-key">Software language</span><span class="attr-value">English</span></div>
          <div class="flex jsb"><span class="attr-key">Activation method</span><span class="attr-value">Open source</span></div>
          <div class="flex jsb"><span class="attr-key">System requirements:</span><span class="attr-value">&gt;= 14</span></div>
          <div class="flex jsb"><span class="attr-key">System compatibility</span><span class="attr-value">Ventura</span></div>
          <div class="flex jsb"><span class="attr-key">Apple Silicon compatibility</span><span class="attr-value">Compatible</span></div>
          <div class="flex jsb"><span class="attr-key">Recently updated</span><span class="attr-value">2026-04-07</span></div>
        </div>
        """#

        let info = try UpdateParser().parseRemoteVersionInfo(from: html, baseURL: URL(string: "https://example.app/page.html")!)
        XCTAssertEqual(info.version, "0.5.5")
    }

    func testParsesChineseSoftwareVersionFromMetadataField() throws {
        let html = #"""
        <div class="pay-attr mt10">
          <div class="flex jsb"><span class="attr-key">软件名称</span><span class="attr-value">MacParakeet</span></div>
          <div class="flex jsb"><span class="attr-key">软件版本</span><span class="attr-value">2.1.0</span></div>
          <div class="flex jsb"><span class="attr-key">文件大小</span><span class="attr-value">200 MB</span></div>
          <div class="flex jsb"><span class="attr-key">软件语言</span><span class="attr-value">English</span></div>
          <div class="flex jsb"><span class="attr-key">激活方式</span><span class="attr-value">Open source</span></div>
          <div class="flex jsb"><span class="attr-key">系统要求</span><span class="attr-value">&gt;= 14</span></div>
          <div class="flex jsb"><span class="attr-key">系统兼容性</span><span class="attr-value">Ventura</span></div>
          <div class="flex jsb"><span class="attr-key">Apple Silicon 兼容性</span><span class="attr-value">Compatible</span></div>
          <div class="flex jsb"><span class="attr-key">最近更新</span><span class="attr-value">2026-04-07</span></div>
        </div>
        """#

        let info = try UpdateParser().parseRemoteVersionInfo(from: html, baseURL: URL(string: "https://example.app/page.html")!)
        XCTAssertEqual(info.version, "2.1.0")
    }

    func testPrefersNinthMetadataValueInPayAttrBlock() throws {
        let html = #"""
        <span class="flex0 icon-spot muted-3-color" title="2026-04-08 10:04:20">1小时前</span>
        <main>
          <div class="sidebar">
            <div>ignore</div>
            <div>
              <div>
                <div class="box-body">
                  <div class="pay-attr mt10" style="font-size:15px">
                    <div class="flex jsb"><span class="attr-key">Software name</span><span class="attr-value">MacParakeet</span></div>
                    <div class="flex jsb"><span class="attr-key">Software version</span><span class="attr-value">0.5.5</span></div>
                    <div class="flex jsb"><span class="attr-key">File size</span><span class="attr-value">200 MB</span></div>
                    <div class="flex jsb"><span class="attr-key">Software language</span><span class="attr-value">English</span></div>
                    <div class="flex jsb"><span class="attr-key">Activation method</span><span class="attr-value">Open source</span></div>
                    <div class="flex jsb"><span class="attr-key">System requirements:</span><span class="attr-value">&gt;= 14</span></div>
                    <div class="flex jsb"><span class="attr-key">System compatibility</span><span class="attr-value">Ventura</span></div>
                    <div class="flex jsb"><span class="attr-key">Apple Silicon compatibility</span><span class="attr-value">Compatible</span></div>
                    <div class="flex jsb"><span class="attr-key">Recently updated</span><span class="attr-value">2026-04-07</span></div>
                    <div class="flex jsb"><span class="attr-key">Software category</span><span class="attr-value">Translation tools</span></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
        <div class="px12-sm muted-2-color text-ellipsis"><span data-toggle="tooltip" data-placement="bottom" title="" data-original-title="2026年02月01日 21:20发布">1个月前更新</span></div>
        """#

        let date = try UpdateParser().parsePublishedAt(from: html)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "Asia/Shanghai") ?? .current, from: date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 7)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testDoesNotFallBackToArticleOrCommentTime() throws {
        let html = #"""
        <span class="flex0 icon-spot muted-3-color" title="2026-04-08 10:04:20">1小时前</span>
        <div class="px12-sm muted-2-color text-ellipsis"><span data-toggle="tooltip" data-placement="bottom" title="" data-original-title="2026年02月01日 21:20发布">1个月前更新</span></div>
        """#

        XCTAssertThrowsError(try UpdateParser().parsePublishedAt(from: html)) { error in
            XCTAssertEqual(error as? UpdateParserError, .missingPublishedAt)
        }
    }

    func testThrowsInvalidPublishedAtWhenNinthValueIsNotDate() throws {
        let html = #"""
        <div class="pay-attr mt10">
          <div class="flex jsb"><span class="attr-key">Software name</span><span class="attr-value">MacParakeet</span></div>
          <div class="flex jsb"><span class="attr-key">Software version</span><span class="attr-value">0.5.5</span></div>
          <div class="flex jsb"><span class="attr-key">File size</span><span class="attr-value">200 MB</span></div>
          <div class="flex jsb"><span class="attr-key">Software language</span><span class="attr-value">English</span></div>
          <div class="flex jsb"><span class="attr-key">Activation method</span><span class="attr-value">Open source</span></div>
          <div class="flex jsb"><span class="attr-key">System requirements:</span><span class="attr-value">&gt;= 14</span></div>
          <div class="flex jsb"><span class="attr-key">System compatibility</span><span class="attr-value">Ventura</span></div>
          <div class="flex jsb"><span class="attr-key">Apple Silicon compatibility</span><span class="attr-value">Compatible</span></div>
          <div class="flex jsb"><span class="attr-key">Recently updated</span><span class="attr-value">Translation tools</span></div>
        </div>
        """#

        XCTAssertThrowsError(try UpdateParser().parsePublishedAt(from: html)) { error in
            XCTAssertEqual(error as? UpdateParserError, .invalidPublishedAt("Translation tools"))
        }
    }

    func testParsesDownloadLinkFromButDownloadMarkup() throws {
        let html = #"""
        <div class="hidden-box show">
          <div class="hidden-text">资源下载</div>
          <div>
            <div class="but-download">
              <a target="_blank" href="https://example.app/wp-content/themes/zibll/zibpay/download.php?post_id=50154&amp;key=b80914319e&amp;down_id=0" class="mr10 but b-theme">最新版本</a>
            </div>
          </div>
        </div>
        """#

        let url = try UpdateParser().parseDownloadLink(from: html, baseURL: URL(string: "https://example.app/tablepro-tableplus.html")!)
        XCTAssertEqual(url.absoluteString, "https://example.app/wp-content/themes/zibll/zibpay/download.php?post_id=50154&key=b80914319e&down_id=0")
    }

    func testFallsBackToLatestVersionAnchor() throws {
        let html = #"""
        <a href="/downloads/latest.zip" class="button">最新版本</a>
        """#

        let url = try UpdateParser().parseDownloadLink(from: html, baseURL: URL(string: "https://example.app/page.html")!)
        XCTAssertEqual(url.absoluteString, "https://example.app/downloads/latest.zip")
    }
}

final class LoginStatusParserTests: XCTestCase {
    func testDetectsEnglishLoginPrompt() {
        let html = #"""
        <a href="javascript:;" class="display-name">Hi！ Please log in</a>
        """#

        let summary = LoginStatusParser().parseLoginState(from: html, userPageURL: URL(string: "https://example.app/user"))
        XCTAssertEqual(summary.status, .requiresLogin)
        XCTAssertNil(summary.profile)
    }

    func testDetectsChineseLoginPrompt() {
        let html = #"""
        <a href="javascript:;" class="display-name">Hi！请登录</a>
        """#

        let summary = LoginStatusParser().parseLoginState(from: html, userPageURL: URL(string: "https://example.app/user"))
        XCTAssertEqual(summary.status, .requiresLogin)
        XCTAssertNil(summary.profile)
    }

    func testExtractsLoggedInProfileAndLevel() {
        let html = #"""
        <span class="display-name"><img class="img-icon mr3 lazyloaded" src="https://example.app/wp-content/themes/zibll/img/vip-1.svg" data-src="https://example.app/wp-content/themes/zibll/img/vip-1.svg" data-toggle="tooltip" title="" alt="赞助" data-original-title="赞助">原始人<img class="img-icon ml3 lazyloaded" src="https://example.app/wp-content/themes/zibll/img/user-level-4.png" data-src="https://example.app/wp-content/themes/zibll/img/user-level-4.png" data-toggle="tooltip" title="" alt="example" data-original-title="LV4"></span>
        """#

        let summary = LoginStatusParser().parseLoginState(from: html, userPageURL: URL(string: "https://example.app/user"))
        XCTAssertEqual(summary.status, .loggedIn)
        XCTAssertEqual(summary.profile?.displayName, "原始人")
        XCTAssertEqual(summary.profile?.membershipLabel, "赞助")
        XCTAssertEqual(summary.profile?.levelLabel, "LV4")
    }
}

final class DownloadBackendTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    func testBuildsAuthorizedEnqueueRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let backend = HTTPDownloadBackend(baseURL: URL(string: "http://127.0.0.1:16800")!, apiKey: "secret", session: session)

        let request = DownloadRequest(
            appId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            url: URL(string: "https://example.app/download.zip")!,
            sourcePageURL: URL(string: "https://example.app/page.html")!,
            referer: URL(string: "https://example.app/page.html")!,
            suggestedFilename: "test.zip"
        )

        let builtRequest = try backend.makeEnqueueURLRequest(for: request)
        XCTAssertEqual(builtRequest.httpMethod, "POST")
        XCTAssertEqual(builtRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(builtRequest.url?.absoluteString, "http://127.0.0.1:16800/downloads")

        let body = try XCTUnwrap(builtRequest.httpBody)
        let payload = try JSONDecoder().decode(DownloadRequest.self, from: body)
        XCTAssertEqual(payload, request)

        MockURLProtocol.requestHandler = { capturedRequest in
            let response = HTTPURLResponse(url: capturedRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: ["downloadId": "job-1", "status": "queued"])
            return (response, data)
        }

        let job = try await backend.enqueue(request)
        XCTAssertEqual(job.id, "job-1")
        XCTAssertEqual(job.state, .queued)
    }

    func testParsesCompletedDownloadStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let backend = HTTPDownloadBackend(baseURL: URL(string: "http://127.0.0.1:16800")!, apiKey: "secret", session: session)

        MockURLProtocol.requestHandler = { capturedRequest in
            XCTAssertEqual(capturedRequest.httpMethod, "GET")
            XCTAssertEqual(capturedRequest.url?.absoluteString, "http://127.0.0.1:16800/downloads/job-99")

            let response = HTTPURLResponse(url: capturedRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "downloadId": "job-99",
                "state": "completed",
                "filePath": "/tmp/latest.zip"
            ])
            return (response, data)
        }

        let status = try await backend.status(for: "job-99")
        XCTAssertEqual(status.jobID, "job-99")
        XCTAssertEqual(status.state, .completed)
        XCTAssertEqual(status.filePath, "/tmp/latest.zip")
    }

    func testReturnsFailedStatusFromErrorResponseShape() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let backend = HTTPDownloadBackend(baseURL: URL(string: "http://127.0.0.1:16800")!, apiKey: "secret", session: session)

        MockURLProtocol.requestHandler = { capturedRequest in
            let response = HTTPURLResponse(url: capturedRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "id": "job-100",
                "status": "failed",
                "message": "permission denied"
            ])
            return (response, data)
        }

        let status = try await backend.status(for: "job-100")
        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.errorMessage, "permission denied")
    }
}

final class TrackedAppTests: XCTestCase {
    func testReadsInstalledVersionFromAppBundle() throws {
        let appURL = try makeTemporaryAppBundle(
            shortVersion: "1.2.3",
            bundleVersion: "123"
        )

        let trackedApp = TrackedApp(
            displayName: "Demo",
            sourcePageURL: "https://example.app/demo",
            localAppPath: appURL.path,
            lastSeenRemotePublishedAt: .now,
            installedPublishedAt: .now,
            lastSeenRemoteVersion: "1.2.3"
        )

        XCTAssertEqual(trackedApp.installedBundleVersionValue, "1.2.3")
        XCTAssertFalse(trackedApp.needsInstallConfirmation)
    }

    func testIgnoresVersionDifferenceWhenCheckingInstallConfirmation() throws {
        let appURL = try makeTemporaryAppBundle(
            shortVersion: "1.0.0",
            bundleVersion: "100"
        )

        let trackedApp = TrackedApp(
            displayName: "Demo",
            sourcePageURL: "https://example.app/demo",
            localAppPath: appURL.path,
            lastSeenRemotePublishedAt: .now,
            installedPublishedAt: .now,
            lastSeenRemoteVersion: "9.9.9",
            installedVersion: "1.0.0"
        )

        XCTAssertFalse(trackedApp.needsInstallConfirmation)
    }

    func testFallsBackToBundleVersionWhenShortVersionMissing() throws {
        let appURL = try makeTemporaryAppBundle(
            shortVersion: nil,
            bundleVersion: "456"
        )

        let trackedApp = TrackedApp(
            displayName: "Demo",
            sourcePageURL: "https://example.app/demo",
            localAppPath: appURL.path,
            lastSeenRemotePublishedAt: .now,
            installedPublishedAt: .now,
            lastSeenRemoteVersion: "456"
        )

        XCTAssertEqual(trackedApp.installedBundleVersionValue, "456")
        XCTAssertFalse(trackedApp.needsInstallConfirmation)
    }

    private func makeTemporaryAppBundle(shortVersion: String?, bundleVersion: String?) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = rootURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": "cc.jasonstu.tests.demo",
            "CFBundleName": "Demo",
            "CFBundlePackageType": "APPL",
        ]

        if let shortVersion {
            plist["CFBundleShortVersionString"] = shortVersion
        }

        if let bundleVersion {
            plist["CFBundleVersion"] = bundleVersion
        }

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
        return rootURL
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
