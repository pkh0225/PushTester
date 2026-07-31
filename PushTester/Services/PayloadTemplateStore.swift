import Foundation
import Combine

enum PayloadTemplatePlatform: String, CaseIterable, Identifiable, Codable {
    case ios
    case android

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}

struct PayloadTemplateItem: Identifiable, Codable, Equatable, Hashable {
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
final class PayloadTemplateStore: ObservableObject {
    @Published private(set) var itemsByPlatform: [String: [PayloadTemplateItem]] = [:]

    private static let fileName = "payload-templates.json"

    private static var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    init(previewItems: [PayloadTemplatePlatform: [PayloadTemplateItem]]) {
        var mapped: [String: [PayloadTemplateItem]] = [:]
        for (platform, items) in previewItems {
            mapped[platform.rawValue] = Self.normalized(items)
        }
        itemsByPlatform = mapped
    }

    func items(for platform: PayloadTemplatePlatform) -> [PayloadTemplateItem] {
        itemsByPlatform[platform.rawValue] ?? []
    }

    func save(items: [PayloadTemplateItem], for platform: PayloadTemplatePlatform) {
        itemsByPlatform[platform.rawValue] = Self.normalized(items)
        persist()
    }

    func upsert(_ item: PayloadTemplateItem, for platform: PayloadTemplatePlatform) {
        var items = items(for: platform)
        if let index = items.firstIndex(where: { $0.name == item.name }) {
            items[index].content = item.content
        } else {
            items.append(item)
        }
        save(items: items, for: platform)
    }

    func clearAll() {
        itemsByPlatform = [:]
        persist()
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [PayloadTemplateItem]].self, from: data) else {
            itemsByPlatform = [:]
            return
        }

        var cleaned: [String: [PayloadTemplateItem]] = [:]
        for (key, items) in decoded {
            cleaned[key] = Self.normalized(items)
        }
        itemsByPlatform = cleaned
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(itemsByPlatform) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static func normalized(_ items: [PayloadTemplateItem]) -> [PayloadTemplateItem] {
        var seenNames = Set<String>()
        var result: [PayloadTemplateItem] = []
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !content.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)
            result.append(PayloadTemplateItem(id: item.id, name: name, content: content))
        }
        return result
    }
}
