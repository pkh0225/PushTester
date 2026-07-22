import Foundation
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [PushHistoryItem] = []

    private let maxItems = 200
    private let fileName = "push-history.json"

    private var fileURL: URL {
        AppSupportPaths.directoryURL.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    /// Canvas 미리보기용. 디스크를 읽지 않습니다.
    init(previewItems: [PushHistoryItem]) {
        items = previewItems
    }

    func items(for platform: PushPlatform) -> [PushHistoryItem] {
        items.filter { $0.pushPlatform == platform }
    }

    func addSuccess(
        session: PushSession,
        apnsID: String?,
        statusCode: Int
    ) {
        insert(PushHistoryItem.make(
            from: session,
            apnsID: apnsID,
            statusCode: statusCode
        ))
    }

    func addAndroidSuccess(
        session: AndroidSession,
        messageName: String?,
        statusCode: Int
    ) {
        insert(PushHistoryItem.makeAndroid(
            from: session,
            messageName: messageName,
            statusCode: statusCode
        ))
    }

    private func insert(_ item: PushHistoryItem) {
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

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    /// 특정 플랫폼 히스토리만 삭제합니다.
    func deleteAll(for platform: PushPlatform) {
        items.removeAll { $0.pushPlatform == platform }
        persist()
    }

    /// 모든 히스토리를 삭제합니다.
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
            // 히스토리 저장 실패는 발송 성공 UX를 막지 않습니다.
        }
    }
}
