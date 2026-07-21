import Foundation

struct FCMSendRequest {
    let projectID: String
    let deviceToken: String
    let priority: FCMPriority
    let serviceAccountJSON: String
    let payload: String
}

struct FCMSendResult {
    let statusCode: Int
    let messageName: String?
    let body: String
}

enum FCMClientError: LocalizedError {
    case missingField(String)
    case invalidJSONPayload
    case httpError(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let name):
            return "\(name)을(를) 입력해 주세요."
        case .invalidJSONPayload:
            return "Payload가 올바른 JSON 형식이 아닙니다."
        case .httpError(let message):
            return message
        }
    }
}

enum FCMClient {
    static func validate(_ request: FCMSendRequest) throws {
        if request.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FCMClientError.missingField("Project ID")
        }
        if request.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FCMClientError.missingField("Device Token")
        }
        if request.serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FCMClientError.missingField("Service Account JSON")
        }
        guard
            let data = request.payload.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            throw FCMClientError.invalidJSONPayload
        }
    }

    static func send(_ request: FCMSendRequest) async throws -> FCMSendResult {
        try validate(request)

        let auth = try await FCMAuth.accessToken(serviceAccountJSON: request.serviceAccountJSON)
        let projectID = request.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? auth.projectID
            : request.projectID.trimmingCharacters(in: .whitespacesAndNewlines)

        let messageObject = try buildMessageObject(request: request)
        let bodyObject: [String: Any] = ["message": messageObject]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObject, options: [.sortedKeys])

        guard let url = URL(string: "https://fcm.googleapis.com/v1/projects/\(projectID)/messages:send") else {
            throw FCMClientError.httpError("요청 URL을 만들 수 없습니다.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw FCMClientError.httpError("응답을 해석할 수 없습니다.")
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let messageName = object?["name"] as? String
        let succeeded = (200..<300).contains(http.statusCode)

        if !succeeded {
            let message = parseError(from: object) ?? body
            throw FCMClientError.httpError("FCM 오류 (HTTP \(http.statusCode)): \(message)")
        }

        return FCMSendResult(statusCode: http.statusCode, messageName: messageName, body: body)
    }

    private static func buildMessageObject(request: FCMSendRequest) throws -> [String: Any] {
        guard
            let data = request.payload.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw FCMClientError.invalidJSONPayload
        }

        var message: [String: Any]
        if let nested = root["message"] as? [String: Any] {
            message = nested
        } else {
            message = root
        }

        message["token"] = request.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)

        var android = (message["android"] as? [String: Any]) ?? [:]
        android["priority"] = request.priority.rawValue
        message["android"] = android

        return message
    }

    private static func parseError(from object: [String: Any]?) -> String? {
        guard let error = object?["error"] as? [String: Any] else { return nil }
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let status = error["status"] as? String, !status.isEmpty {
            return status
        }
        return nil
    }
}
