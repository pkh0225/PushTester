import Foundation
import Combine

enum CertificatePresetKind: String, CaseIterable, Identifiable, Codable {
    case apnsP8
    case fcmServiceAccount

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .apnsP8: return "인증서 (.p8)"
        case .fcmServiceAccount: return "인증서 (JSON)"
        }
    }

    var emptyDisplayName: String {
        switch self {
        case .apnsP8: return "No key imported"
        case .fcmServiceAccount: return "No JSON imported"
        }
    }

    var importButtonTitle: String {
        switch self {
        case .apnsP8: return "Import Key (*.p8)"
        case .fcmServiceAccount: return "Import JSON"
        }
    }
}

struct CertificatePresetItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var content: String

    init(id: UUID = UUID(), name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
    }
}

@MainActor
final class CertificatePresetStore: ObservableObject {
    @Published private(set) var itemsByKind: [String: [CertificatePresetItem]] = [:]

    private static let fileName = "certificate-presets.json"

    private static var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    init(previewItems: [CertificatePresetKind: [CertificatePresetItem]]) {
        var mapped: [String: [CertificatePresetItem]] = [:]
        for (kind, items) in previewItems {
            mapped[kind.rawValue] = Self.normalized(items)
        }
        itemsByKind = mapped
    }

    func items(for kind: CertificatePresetKind) -> [CertificatePresetItem] {
        itemsByKind[kind.rawValue] ?? []
    }

    func save(items: [CertificatePresetItem], for kind: CertificatePresetKind) {
        itemsByKind[kind.rawValue] = Self.normalized(items)
        persist()
    }

    /// 같은 이름이면 내용을 갱신하고, 없으면 추가합니다.
    func upsert(_ item: CertificatePresetItem, for kind: CertificatePresetKind) {
        var items = items(for: kind)
        if let index = items.firstIndex(where: { $0.name == item.name }) {
            items[index].content = item.content
        } else {
            items.append(item)
        }
        save(items: items, for: kind)
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [CertificatePresetItem]].self, from: data) else {
            itemsByKind = [:]
            return
        }

        var cleaned: [String: [CertificatePresetItem]] = [:]
        for (key, items) in decoded {
            cleaned[key] = Self.normalized(items)
        }
        itemsByKind = cleaned
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(itemsByKind) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static func normalized(_ items: [CertificatePresetItem]) -> [CertificatePresetItem] {
        var seenNames = Set<String>()
        var result: [CertificatePresetItem] = []
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !content.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)
            result.append(CertificatePresetItem(id: item.id, name: name, content: content))
        }
        return result
    }
}
