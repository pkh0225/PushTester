import Foundation
import Combine

enum FieldPresetKey: String, CaseIterable, Identifiable, Codable {
    case bundleID
    case teamID
    case keyID
    case deviceToken
    case projectID
    case title

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .bundleID: return "Bundle ID"
        case .teamID: return "Team ID"
        case .keyID: return "Key ID"
        case .deviceToken: return "Device Token"
        case .projectID: return "Project ID"
        case .title: return "제목"
        }
    }
}

@MainActor
final class FieldPresetStore: ObservableObject {
    @Published private(set) var valuesByKey: [String: [String]] = [:]

    private static let fileName = "field-presets.json"

    private static var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    init(previewValues: [FieldPresetKey: [String]]) {
        var mapped: [String: [String]] = [:]
        for (key, values) in previewValues {
            mapped[key.rawValue] = Self.normalized(values)
        }
        valuesByKey = mapped
    }

    func values(for key: FieldPresetKey) -> [String] {
        valuesByKey[key.rawValue] ?? []
    }

    func save(values: [String], for key: FieldPresetKey) {
        valuesByKey[key.rawValue] = Self.normalized(values)
        persist()
    }

    func clearAll() {
        valuesByKey = [:]
        persist()
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            valuesByKey = [:]
            return
        }

        var cleaned: [String: [String]] = [:]
        for (key, values) in decoded {
            cleaned[key] = Self.normalized(values)
        }
        valuesByKey = cleaned
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(valuesByKey) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
