import Foundation

struct APNsSendRequest {
    let teamID: String
    let keyID: String
    let bundleID: String
    let deviceToken: String
    let p8PEM: String
    let environment: APNsEnvironment
    let priority: APNsPriority
    let pushType: APNsPushType
    let payload: String
}

struct APNsSendResult {
    let statusCode: Int
    let apnsID: String?
    let body: String
    let succeeded: Bool
}

enum APNsClientError: LocalizedError {
    case missingField(String)
    case invalidJSONPayload
    case invalidDeviceToken
    case httpError(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let name):
            return "\(name)을(를) 입력해 주세요."
        case .invalidJSONPayload:
            return "Payload가 올바른 JSON 형식이 아닙니다."
        case .invalidDeviceToken:
            return "Device Token 형식이 올바르지 않습니다."
        case .httpError(let message):
            return message
        }
    }
}

enum APNsClient {
    static func validate(_ request: APNsSendRequest) throws {
        if request.teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APNsClientError.missingField("Team ID")
        }
        if request.keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APNsClientError.missingField("Key ID")
        }
        if request.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APNsClientError.missingField("Bundle ID")
        }
        if request.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APNsClientError.missingField("Device Token")
        }
        if request.p8PEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APNsClientError.missingField(".p8 Key")
        }

        let token = normalizedDeviceToken(request.deviceToken)
        guard !token.isEmpty, token.count % 2 == 0, token.allSatisfy(\.isHexDigit) else {
            throw APNsClientError.invalidDeviceToken
        }

        let payloadData = Data(request.payload.utf8)
        guard (try? JSONSerialization.jsonObject(with: payloadData)) != nil else {
            throw APNsClientError.invalidJSONPayload
        }
    }

    static func send(_ request: APNsSendRequest) async throws -> APNsSendResult {
        try validate(request)

        let jwt = try APNsJWT.makeToken(
            teamID: request.teamID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: request.keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            p8PEM: request.p8PEM
        )

        let token = normalizedDeviceToken(request.deviceToken)
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.environment.host
        components.path = "/3/device/\(token)"

        guard let url = components.url else {
            throw APNsClientError.httpError("요청 URL을 만들 수 없습니다.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        urlRequest.setValue(request.bundleID.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "apns-topic")
        urlRequest.setValue(request.pushType.rawValue, forHTTPHeaderField: "apns-push-type")
        urlRequest.setValue(String(request.priority.rawValue), forHTTPHeaderField: "apns-priority")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = Data(request.payload.utf8)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APNsClientError.httpError("응답을 해석할 수 없습니다.")
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let apnsID = http.value(forHTTPHeaderField: "apns-id")
        let succeeded = (200..<300).contains(http.statusCode)

        if !succeeded {
            let reason = parseReason(from: body) ?? body
            let message: String
            if reason == "TooManyProviderTokenUpdates" {
                message = """
                APNs 오류 (HTTP \(http.statusCode)): TooManyProviderTokenUpdates
                인증 JWT를 너무 자주 갱신해서 일시적으로 거부된 상태입니다. 잠시 후 다시 시도해 주세요.
                """
            } else if reason.isEmpty {
                message = "APNs 오류 (HTTP \(http.statusCode))"
            } else {
                message = "APNs 오류 (HTTP \(http.statusCode)): \(reason)"
            }
            throw APNsClientError.httpError(message)
        }

        return APNsSendResult(
            statusCode: http.statusCode,
            apnsID: apnsID,
            body: body,
            succeeded: succeeded
        )
    }

    private static func normalizedDeviceToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .lowercased()
    }

    private static func parseReason(from body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let reason = object["reason"] as? String
        else {
            return nil
        }
        return reason
    }
}
