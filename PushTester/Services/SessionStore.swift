import Foundation

struct PushSession: Codable, Equatable {
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

    static let empty = PushSession(
        teamID: "",
        bundleID: "",
        keyID: "",
        deviceToken: "",
        environment: APNsEnvironment.sandbox.rawValue,
        priority: APNsPriority.immediate.rawValue,
        pushType: APNsPushType.alert.rawValue,
        payload: PayloadTemplates.alert,
        p8FileName: "No key imported",
        p8PEM: ""
    )
}

enum SessionStoreError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case writeFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "설정을 저장용 형식으로 변환하지 못했습니다."
        case .decodeFailed:
            return "설정 파일 형식이 올바르지 않습니다."
        case .writeFailed(let message):
            return "저장에 실패했습니다: \(message)"
        case .readFailed(let message):
            return "불러오기에 실패했습니다: \(message)"
        }
    }
}

enum SessionStore {
    private static let lastSessionFileName = "last-session.json"

    private static var lastSessionURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(lastSessionFileName)
    }

    static func loadLastSession() -> PushSession? {
        let url = lastSessionURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decode(from: url)
        } catch {
            return nil
        }
    }

    static func saveLastSession(_ session: PushSession) throws {
        try write(session, to: lastSessionURL)
    }

    static func clearLastSession() {
        try? FileManager.default.removeItem(at: lastSessionURL)
    }

    static func export(_ session: PushSession, to url: URL) throws {
        try write(session, to: url)
    }

    static func `import`(from url: URL) throws -> PushSession {
        try decode(from: url)
    }

    private static func write(_ session: PushSession, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else {
            throw SessionStoreError.encodeFailed
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SessionStoreError.writeFailed(error.localizedDescription)
        }
    }

    private static func decode(from url: URL) throws -> PushSession {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PushSession.self, from: data)
        } catch is DecodingError {
            throw SessionStoreError.decodeFailed
        } catch {
            throw SessionStoreError.readFailed(error.localizedDescription)
        }
    }
}
