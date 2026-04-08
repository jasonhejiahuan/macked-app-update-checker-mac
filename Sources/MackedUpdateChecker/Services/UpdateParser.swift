import Foundation

protocol UpdateSourceParsing {
    func parsePublishedAt(from html: String) throws -> Date
    func parseDownloadLink(from html: String, baseURL: URL) throws -> URL
    func parseRemoteVersionInfo(from html: String, baseURL: URL) throws -> RemoteVersionInfo
}

protocol LoginStatusParsing {
    func parseLoginState(from html: String, userPageURL: URL?) -> LoginStateSummary
}

enum UpdateParserError: LocalizedError, Equatable {
    case missingPublishedAt
    case invalidPublishedAt(String)
    case missingDownloadLink
    case invalidDownloadLink(String)

    var errorDescription: String? {
        switch self {
        case .missingPublishedAt:
            return "未找到发布时间。"
        case let .invalidPublishedAt(value):
            return "无法解析发布时间：\(value)"
        case .missingDownloadLink:
            return "未找到下载链接。"
        case let .invalidDownloadLink(value):
            return "无效的下载链接：\(value)"
        }
    }
}

struct UpdateParser: UpdateSourceParsing {
    private static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    func parsePublishedAt(from html: String) throws -> Date {
        let fixedPositionCandidates = extractFixedSidebarPublishedAtCandidates(from: html)
        let fixedPositionDates = fixedPositionCandidates.compactMap(Self.parsePublishedDate)
        if let fixedPositionDate = fixedPositionDates.first {
            return fixedPositionDate
        }

        if let rawFixedPositionCandidate = extractRawFixedSidebarPublishedAtCandidate(from: html) {
            throw UpdateParserError.invalidPublishedAt(rawFixedPositionCandidate)
        }

        throw UpdateParserError.missingPublishedAt
    }

    func parseDownloadLink(from html: String, baseURL: URL) throws -> URL {
        if let specific = bestDownloadCandidate(in: html, baseURL: baseURL) {
            return specific
        }

        throw UpdateParserError.missingDownloadLink
    }

    func parseRemoteVersionInfo(from html: String, baseURL: URL) throws -> RemoteVersionInfo {
        let publishedAt = try parsePublishedAt(from: html)
        let version = parseSoftwareVersion(from: html)
        let downloadURL = try? parseDownloadLink(from: html, baseURL: baseURL)
        return RemoteVersionInfo(publishedAt: publishedAt, version: version, downloadURL: downloadURL)
    }

    private func bestDownloadCandidate(in html: String, baseURL: URL) -> URL? {
        var scoredCandidates: [(score: Int, url: URL)] = []

        let butDownloadPattern = #"(?is)<div[^>]*class=["'][^"']*but-download[^"']*["'][^>]*>.*?<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        for match in html.matches(for: butDownloadPattern) {
            guard let rawURL = match.capture(at: 1),
                  let url = resolveURL(rawURL, baseURL: baseURL) else {
                continue
            }

            let anchorText = match.capture(at: 2)?.strippingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isLatest = anchorText.contains("最新版本") || rawURL.contains("download.php")
            scoredCandidates.append((score: isLatest ? 10 : 7, url: url))
        }

        let anchorPattern = #"(?is)<a\b([^>]*)href=["']([^"']+)["']([^>]*)>(.*?)</a>"#
        for match in html.matches(for: anchorPattern) {
            guard let rawURL = match.capture(at: 2),
                  let url = resolveURL(rawURL, baseURL: baseURL) else {
                continue
            }

            let beforeAttributes = match.capture(at: 1) ?? ""
            let afterAttributes = match.capture(at: 3) ?? ""
            let innerText = (match.capture(at: 4) ?? "")
                .strippingHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let anchorHTML = match.fullMatch

            var score = 0
            if innerText.contains("最新版本") {
                score += 6
            }
            if rawURL.contains("download.php") {
                score += 4
            }
            if beforeAttributes.contains("b-theme") || afterAttributes.contains("b-theme") || anchorHTML.contains("but-download") {
                score += 2
            }

            if score > 0 {
                scoredCandidates.append((score: score, url: url))
            }
        }

        return scoredCandidates.max { lhs, rhs in lhs.score < rhs.score }?.url
    }

    private func extractAttributeValues(named attribute: String, from html: String) -> [String] {
        let pattern = #"(?is)\b"# + NSRegularExpression.escapedPattern(for: attribute) + #"\s*=\s*["']([^"']+)["']"#
        return html.matches(for: pattern).compactMap { $0.capture(at: 1) }
    }

    private func extractFixedSidebarPublishedAtCandidates(from html: String) -> [String] {
        guard let candidate = extractRawFixedSidebarPublishedAtCandidate(from: html),
              Self.parsePublishedDate(candidate) != nil else {
            return []
        }
        return [candidate]
    }

    private func extractRawFixedSidebarPublishedAtCandidate(from html: String) -> String? {
        for blockHTML in extractPayAttrBlocks(from: html) {
            let orderedValues = orderedMetadataValues(in: blockHTML)
            guard orderedValues.indices.contains(8) else { continue }

            let candidate = orderedValues[8].normalizedWhitespace()
            if !candidate.isEmpty {
                return candidate
            }
        }

        return nil
    }

    private func extractPayAttrBlocks(from html: String) -> [String] {
        let openingTagPattern = #"<div\b[^>]*class=["'][^"']*pay-attr[^"']*mt10[^"']*["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: openingTagPattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)

        return regex.matches(in: html, options: [], range: fullRange).compactMap { match in
            let openingTagEnd = match.range.location + match.range.length
            let contentStart = openingTagEnd
            var searchLocation = openingTagEnd
            var depth = 1

            while searchLocation < nsHTML.length {
                let remainingRange = NSRange(location: searchLocation, length: nsHTML.length - searchLocation)
                let nextOpen = nsHTML.range(of: "<div", options: [.caseInsensitive], range: remainingRange)
                let nextClose = nsHTML.range(of: "</div>", options: [.caseInsensitive], range: remainingRange)

                if nextClose.location == NSNotFound {
                    return nil
                }

                let shouldConsumeOpen = nextOpen.location != NSNotFound && nextOpen.location < nextClose.location
                if shouldConsumeOpen {
                    depth += 1
                    searchLocation = nextOpen.location + nextOpen.length
                } else {
                    depth -= 1
                    if depth == 0 {
                        let contentRange = NSRange(location: contentStart, length: nextClose.location - contentStart)
                        return nsHTML.substring(with: contentRange)
                    }
                    searchLocation = nextClose.location + nextClose.length
                }
            }

            return nil
        }
    }

    private func parseSoftwareVersion(from html: String) -> String? {
        metadataValues(forKeys: ["software version", "软件版本", "版本", "版本号"], in: html)
            .first(where: { !$0.isEmpty })
    }

    private func metadataValues(forKeys keys: Set<String>, in html: String) -> [String] {
        orderedMetadataRows(in: html).compactMap { row in
            guard keys.contains(Self.normalizeMetadataKey(row.key)) else { return nil }
            return row.value.isEmpty ? nil : row.value
        }
    }

    private func orderedMetadataValues(in html: String) -> [String] {
        orderedMetadataRows(in: html).map(\.value)
    }

    private func orderedMetadataRows(in html: String) -> [(key: String, value: String)] {
        let blockPattern = #"(?is)<div\b[^>]*class=["'][^"']*flex[^"']*jsb[^"']*["'][^>]*>.*?<span\b[^>]*class=["'][^"']*attr-key[^"']*["'][^>]*>(.*?)</span>.*?<span\b[^>]*class=["'][^"']*attr-value[^"']*["'][^>]*>(.*?)</span>.*?</div>"#

        return html.matches(for: blockPattern).map { match in
            let rawKey = (match.capture(at: 1) ?? "").strippingHTMLTags().normalizedWhitespace()
            let rawValue = (match.capture(at: 2) ?? "").strippingHTMLTags().normalizedWhitespace()
            return (key: rawKey, value: rawValue)
        }
    }

    private func resolveURL(_ rawURL: String, baseURL: URL) -> URL? {
        let unescaped = rawURL.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)

        if let absolute = URL(string: unescaped), absolute.scheme != nil {
            return absolute
        }

        return URL(string: unescaped, relativeTo: baseURL)?.absoluteURL
    }

    private static func parsePublishedDate(_ value: String) -> Date? {
        let normalized = value.normalizedWhitespace()
        return parseChinesePublishedDate(normalized)
            ?? parseDashSeparatedPublishedDate(normalized)
            ?? parseDateOnly(normalized)
    }

    private static func parseChinesePublishedDate(_ value: String) -> Date? {
        let pattern = #"(\d{4})年(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})(?::(\d{2}))?"#
        guard let match = value.matches(for: pattern).first,
              let year = Int(match.capture(at: 1) ?? ""),
              let month = Int(match.capture(at: 2) ?? ""),
              let day = Int(match.capture(at: 3) ?? ""),
              let hour = Int(match.capture(at: 4) ?? ""),
              let minute = Int(match.capture(at: 5) ?? "") else {
            return nil
        }

        let second = Int(match.capture(at: 6) ?? "") ?? 0
        return makeDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    private static func parseDashSeparatedPublishedDate(_ value: String) -> Date? {
        let pattern = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})\s*[T ]\s*(\d{1,2}):(\d{2})(?::(\d{2}))?"#
        guard let match = value.matches(for: pattern).first,
              let year = Int(match.capture(at: 1) ?? ""),
              let month = Int(match.capture(at: 2) ?? ""),
              let day = Int(match.capture(at: 3) ?? ""),
              let hour = Int(match.capture(at: 4) ?? ""),
              let minute = Int(match.capture(at: 5) ?? "") else {
            return nil
        }

        let second = Int(match.capture(at: 6) ?? "") ?? 0
        return makeDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let pattern = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#
        guard let match = value.matches(for: pattern).first,
              let year = Int(match.capture(at: 1) ?? ""),
              let month = Int(match.capture(at: 2) ?? ""),
              let day = Int(match.capture(at: 3) ?? "") else {
            return nil
        }

        return makeDate(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
    }

    private static func normalizeMetadataKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "：", with: "")
            .normalizedWhitespace()
    }

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = shanghaiTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }
}

struct LoginStatusParser: LoginStatusParsing {
    func parseLoginState(from html: String, userPageURL: URL?) -> LoginStateSummary {
        if containsLoginPrompt(in: html) {
            return LoginStateSummary(
                status: .requiresLogin,
                profile: nil,
                checkedAt: .now,
                userPageURL: userPageURL,
                message: "当前账号未登录，请在交互式窗口中完成登录。"
            )
        }

        if let profile = extractProfile(from: html) {
            return LoginStateSummary(
                status: .loggedIn,
                profile: profile,
                checkedAt: .now,
                userPageURL: userPageURL,
                message: "检测到已登录账号。"
            )
        }

        return LoginStateSummary(
            status: .unknown,
            profile: nil,
            checkedAt: .now,
            userPageURL: userPageURL,
            message: "未能从用户页识别登录状态。"
        )
    }

    private func containsLoginPrompt(in html: String) -> Bool {
        let anchorPattern = #"(?is)<a\b[^>]*class=["'][^"']*display-name[^"']*["'][^>]*>(.*?)</a>"#
        for match in html.matches(for: anchorPattern) {
            let text = (match.capture(at: 1) ?? "")
                .strippingHTMLTags()
                .normalizedWhitespace()
                .lowercased()
            if text.contains("please log in") || text.contains("请登录") {
                return true
            }
        }
        return false
    }

    private func extractProfile(from html: String) -> LoginAccountProfile? {
        let spanPattern = #"(?is)<span\b[^>]*class=["'][^"']*display-name[^"']*["'][^>]*>(.*?)</span>"#
        for match in html.matches(for: spanPattern) {
            let innerHTML = match.capture(at: 1) ?? ""
            let displayName = innerHTML.strippingHTMLTags().normalizedWhitespace()
            if displayName.isEmpty || displayName.lowercased().contains("please log in") || displayName.contains("请登录") {
                continue
            }

            let badges = extractBadgeLabels(from: innerHTML)
            let levelLabel = badges.first { $0.range(of: #"^LV\d+$"#, options: .regularExpression) != nil }
            let membershipLabel = badges.first {
                $0.range(of: #"^LV\d+$"#, options: .regularExpression) == nil && $0.lowercased() != "example"
            }

            return LoginAccountProfile(
                displayName: displayName,
                membershipLabel: membershipLabel,
                levelLabel: levelLabel,
                badges: badges
            )
        }

        return nil
    }

    private func extractBadgeLabels(from html: String) -> [String] {
        let imagePattern = #"(?is)<img\b([^>]*)>"#
        var labels: [String] = []

        for match in html.matches(for: imagePattern) {
            let attributes = match.capture(at: 1) ?? ""
            let candidates = [
                extractAttributeValue(named: "data-original-title", from: attributes),
                extractAttributeValue(named: "title", from: attributes),
                extractAttributeValue(named: "alt", from: attributes),
            ]

            for candidate in candidates.compactMap({ $0?.normalizedWhitespace() }) where !candidate.isEmpty {
                if !labels.contains(candidate) {
                    labels.append(candidate)
                }
            }
        }

        return labels
    }

    private func extractAttributeValue(named attribute: String, from attributes: String) -> String? {
        let pattern = #"(?is)\b"# + NSRegularExpression.escapedPattern(for: attribute) + #"\s*=\s*["']([^"']+)["']"#
        return attributes.matches(for: pattern).first?.capture(at: 1)
    }
}

private struct RegexMatch {
    let fullMatch: String
    let captures: [String]

    func capture(at index: Int) -> String? {
        guard index > 0 else { return fullMatch }
        let captureIndex = index - 1
        guard captures.indices.contains(captureIndex) else { return nil }
        let value = captures[captureIndex]
        return value.isEmpty ? nil : value
    }
}

private extension String {
    func matches(for pattern: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, options: [], range: range).compactMap { result in
            guard let fullRange = Range(result.range(at: 0), in: self) else {
                return nil
            }

            let captures = (1..<result.numberOfRanges).compactMap { index -> String? in
                let nsRange = result.range(at: index)
                guard nsRange.location != NSNotFound, let captureRange = Range(nsRange, in: self) else {
                    return ""
                }
                return String(self[captureRange])
            }

            return RegexMatch(fullMatch: String(self[fullRange]), captures: captures)
        }
    }

    func strippingHTMLTags() -> String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func normalizedWhitespace() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func decodingHTMLEntities() -> String {
        var decoded = self
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
        ]

        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }
}
