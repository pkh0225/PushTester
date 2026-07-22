import Foundation

enum AndroidSessionStore {
    private static let fileName = "android-last-session.json"

    private static var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    static func loadLastSession() -> AndroidSession? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AndroidSession.self, from: data)
        } catch {
            return nil
        }
    }

    static func saveLastSession(_ session: AndroidSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: .atomic)
    }

    static func clearLastSession() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func export(_ session: AndroidSession, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
    }

    static func `import`(from url: URL) throws -> AndroidSession {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AndroidSession.self, from: data)
    }
}
