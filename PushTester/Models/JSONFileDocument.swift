import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI `fileExporter` / `fileImporter` 용 JSON 문서.
/// AppKit `NSSavePanel` 시트를 쓰지 않고 시스템 파일 UI를 표준 API로 띄웁니다.
struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
