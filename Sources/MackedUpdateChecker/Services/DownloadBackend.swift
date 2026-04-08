import Foundation

protocol DownloadBackend {
    func enqueue(_ request: DownloadRequest) async throws -> DownloadJob
    func status(for jobID: String) async throws -> DownloadJobStatus
}

enum DownloadBackendError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case invalidResponse
    case unsuccessfulStatusCode(Int)
    case missingJobID

    var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "无效的 RPC 地址：\(value)"
        case .invalidResponse:
            return "下载服务返回了无法识别的响应。"
        case let .unsuccessfulStatusCode(code):
            return "下载服务返回错误状态码：\(code)"
        case .missingJobID:
            return "下载服务未返回任务 ID。"
        }
    }
}

struct HTTPDownloadBackend: DownloadBackend {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func enqueue(_ request: DownloadRequest) async throws -> DownloadJob {
        let urlRequest = try makeEnqueueURLRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response)

        let payload = try decodeDictionary(from: data)
        let jobID = payload.string(forKeys: ["downloadId", "id", "jobId"])
        guard let jobID, !jobID.isEmpty else {
            throw DownloadBackendError.missingJobID
        }

        return DownloadJob(id: jobID, state: payload.downloadState(forKeys: ["status", "state"]))
    }

    func status(for jobID: String) async throws -> DownloadJobStatus {
        let urlRequest = makeStatusURLRequest(for: jobID)
        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response)

        let payload = try decodeDictionary(from: data)
        let filePath = payload.string(forKeys: ["filePath", "localPath", "path"])
        let errorMessage = payload.string(forKeys: ["errorMessage", "error", "message"])

        return DownloadJobStatus(
            jobID: payload.string(forKeys: ["downloadId", "id", "jobId"]) ?? jobID,
            state: payload.downloadState(forKeys: ["status", "state"]),
            filePath: filePath,
            errorMessage: errorMessage
        )
    }

    func makeEnqueueURLRequest(for request: DownloadRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "downloads"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }

    func makeStatusURLRequest(for jobID: String) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "downloads").appending(path: jobID))
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadBackendError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadBackendError.unsuccessfulStatusCode(httpResponse.statusCode)
        }
    }

    private func decodeDictionary(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadBackendError.invalidResponse
        }

        return object
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(forKeys keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                return value
            }
            if let value = self[key] as? CustomStringConvertible {
                return value.description
            }
        }
        return nil
    }

    func downloadState(forKeys keys: [String]) -> DownloadState {
        guard let rawValue = string(forKeys: keys)?.lowercased() else {
            return .unknown
        }

        switch rawValue {
        case "queued", "pending", "waiting":
            return .queued
        case "running", "downloading", "in_progress", "processing":
            return .running
        case "completed", "success", "done", "finished":
            return .completed
        case "failed", "error", "cancelled":
            return .failed
        default:
            return .unknown
        }
    }
}
