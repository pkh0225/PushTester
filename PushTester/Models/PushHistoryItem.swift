import Foundation

struct PushHistoryItem: Codable, Identifiable, Equatable {
    var id: UUID
    var platform: String
    var title: String
    var sentAt: Date
    var teamID: String
    var bundleID: String
    var keyID: String
    var deviceToken: String
    var environment: String
    var priority: Int
    var pushType: String
    var payload: String
    var p8FileName: String
    var p8PEM: String
    var apnsID: String?
    var statusCode: Int?
    /// 응답 헤더 (줄 단위 `Key: Value`)
    var responseHeaders: String?
    /// 응답 바디 (원문 또는 pretty JSON)
    var responseBody: String?

    var pushPlatform: PushPlatform {
        PushPlatform(rawValue: platform) ?? .ios
    }

    var session: PushSession {
        PushSession(
            teamID: teamID,
            bundleID: bundleID,
            keyID: keyID,
            deviceToken: deviceToken,
            environment: environment,
            priority: priority,
            pushType: pushType,
            payload: payload,
            p8FileName: p8FileName,
            p8PEM: p8PEM
        )
    }

    var androidSession: AndroidSession {
        AndroidSession(
            projectID: bundleID,
            deviceToken: deviceToken,
            priority: FCMPriority.from(historyValue: priority).rawValue,
            payload: payload,
            serviceAccountFileName: p8FileName,
            serviceAccountJSON: p8PEM
        )
    }

    var environmentDisplay: String {
        switch pushPlatform {
        case .ios:
            return environment
        case .android:
            return "FCM"
        }
    }

    var pushTypeDisplay: String {
        switch pushPlatform {
        case .ios:
            return APNsPushType(rawValue: pushType)?.displayName ?? pushType
        case .android:
            return FCMPriority.from(historyValue: priority).title
        }
    }

    var shortDeviceToken: String {
        let token = deviceToken
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
        guard token.count > 12 else { return token }
        return "\(token.prefix(6))…\(token.suffix(6))"
    }

    var hasResponseDetail: Bool {
        let headers = responseHeaders?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = responseBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (statusCode ?? 0) > 0 || !headers.isEmpty || !body.isEmpty
    }

    var statusCodeDisplay: String? {
        guard let statusCode, statusCode > 0 else { return nil }
        return "HTTP \(statusCode)"
    }

    enum CodingKeys: String, CodingKey {
        case id, platform, title, sentAt, teamID, bundleID, keyID, deviceToken
        case environment, priority, pushType, payload, p8FileName, p8PEM, apnsID, statusCode
        case responseHeaders, responseBody
    }

    init(
        id: UUID,
        platform: String = PushPlatform.ios.rawValue,
        title: String,
        sentAt: Date,
        teamID: String,
        bundleID: String,
        keyID: String,
        deviceToken: String,
        environment: String,
        priority: Int,
        pushType: String,
        payload: String,
        p8FileName: String,
        p8PEM: String,
        apnsID: String?,
        statusCode: Int?,
        responseHeaders: String? = nil,
        responseBody: String? = nil
    ) {
        self.id = id
        self.platform = platform
        self.title = title
        self.sentAt = sentAt
        self.teamID = teamID
        self.bundleID = bundleID
        self.keyID = keyID
        self.deviceToken = deviceToken
        self.environment = environment
        self.priority = priority
        self.pushType = pushType
        self.payload = payload
        self.p8FileName = p8FileName
        self.p8PEM = p8PEM
        self.apnsID = apnsID
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? PushPlatform.ios.rawValue
        title = try container.decode(String.self, forKey: .title)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        teamID = try container.decode(String.self, forKey: .teamID)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        keyID = try container.decode(String.self, forKey: .keyID)
        deviceToken = try container.decode(String.self, forKey: .deviceToken)
        environment = try container.decode(String.self, forKey: .environment)
        priority = try container.decode(Int.self, forKey: .priority)
        pushType = try container.decode(String.self, forKey: .pushType)
        payload = try container.decode(String.self, forKey: .payload)
        p8FileName = try container.decode(String.self, forKey: .p8FileName)
        p8PEM = try container.decode(String.self, forKey: .p8PEM)
        apnsID = try container.decodeIfPresent(String.self, forKey: .apnsID)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        responseHeaders = try container.decodeIfPresent(String.self, forKey: .responseHeaders)
        responseBody = try container.decodeIfPresent(String.self, forKey: .responseBody)
    }

    static func make(
        from session: PushSession,
        apnsID: String?,
        statusCode: Int,
        responseHeaders: String? = nil,
        responseBody: String? = nil,
        sentAt: Date = Date()
    ) -> PushHistoryItem {
        PushHistoryItem(
            id: UUID(),
            platform: PushPlatform.ios.rawValue,
            title: defaultTitle(from: session.payload, fallback: session.bundleID, sentAt: sentAt, isAndroid: false),
            sentAt: sentAt,
            teamID: session.teamID,
            bundleID: session.bundleID,
            keyID: session.keyID,
            deviceToken: session.deviceToken,
            environment: session.environment,
            priority: session.priority,
            pushType: session.pushType,
            payload: session.payload,
            p8FileName: session.p8FileName,
            p8PEM: session.p8PEM,
            apnsID: apnsID,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody
        )
    }

    /// 앱 내 저장 목록용 (발송 결과 없이 현재 입력값 스냅샷)
    static func makeSaved(
        from session: PushSession,
        title: String,
        savedAt: Date = Date()
    ) -> PushHistoryItem {
        var item = make(from: session, apnsID: nil, statusCode: 0, sentAt: savedAt)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
        }
        return item
    }

    static func makeAndroidSaved(
        from session: AndroidSession,
        title: String,
        savedAt: Date = Date()
    ) -> PushHistoryItem {
        var item = makeAndroid(from: session, messageName: nil, statusCode: 0, sentAt: savedAt)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
        }
        return item
    }

    static func makeAndroid(
        from session: AndroidSession,
        messageName: String?,
        statusCode: Int,
        responseHeaders: String? = nil,
        responseBody: String? = nil,
        sentAt: Date = Date()
    ) -> PushHistoryItem {
        let priority = FCMPriority(rawValue: session.priority) ?? .high
        return PushHistoryItem(
            id: UUID(),
            platform: PushPlatform.android.rawValue,
            title: defaultTitle(from: session.payload, fallback: session.projectID, sentAt: sentAt, isAndroid: true),
            sentAt: sentAt,
            teamID: "",
            bundleID: session.projectID,
            keyID: "",
            deviceToken: session.deviceToken,
            environment: "FCM",
            priority: priority.historyValue,
            pushType: "fcm",
            payload: session.payload,
            p8FileName: session.serviceAccountFileName,
            p8PEM: session.serviceAccountJSON,
            apnsID: messageName,
            statusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody
        )
    }

    private static func defaultTitle(from payload: String, fallback: String, sentAt: Date, isAndroid: Bool) -> String {
        if let title = extractTitle(from: payload, isAndroid: isAndroid), !title.isEmpty {
            return title
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let name = fallback.isEmpty ? "Push" : fallback
        return "\(name) · \(formatter.string(from: sentAt))"
    }

    private static func extractTitle(from payload: String, isAndroid: Bool) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if isAndroid {
            let root = (object["message"] as? [String: Any]) ?? object
            if let notification = root["notification"] as? [String: Any] {
                if let title = notification["title"] as? String, !title.isEmpty { return title }
                if let body = notification["body"] as? String, !body.isEmpty { return body }
            }
            return nil
        }

        guard let aps = object["aps"] as? [String: Any] else { return nil }
        if let alert = aps["alert"] as? [String: Any] {
            if let title = alert["title"] as? String, !title.isEmpty { return title }
            if let body = alert["body"] as? String, !body.isEmpty { return body }
        }
        if let alert = aps["alert"] as? String, !alert.isEmpty {
            return alert
        }
        return nil
    }
}
