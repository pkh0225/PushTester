import Foundation
import Combine

/// 앱 내에 수동 저장한 설정 목록 (파일보내기와 별개)
@MainActor
final class SavedConfigStore: ObservableObject {
    @Published private(set) var items: [PushHistoryItem] = []

    private let maxItems = 200
    private let fileName = "saved-configs.json"

    private var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    init(previewItems: [PushHistoryItem]) {
        items = previewItems
    }

    func items(for platform: PushPlatform) -> [PushHistoryItem] {
        items.filter { $0.pushPlatform == platform }
    }

    func add(_ item: PushHistoryItem) {
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        persist()
    }

    func update(_ item: PushHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        persist()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        items = []
        persist()
    }

    private func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([PushHistoryItem].self, from: data)
                .sorted { $0.sentAt > $1.sentAt }
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 저장 실패는 UI를 막지 않습니다.
        }
    }
}
