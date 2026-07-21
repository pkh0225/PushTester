import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// NSSavePanel 대신 쓰는 작은 설정 저장 시트
struct SessionSaveSheet: View {
    let title: String
    let defaultFileName: String
    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fileName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField("파일명", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveToDownloads)

            Text("기본으로 다운로드 폴더에 저장합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("다른 위치…") {
                    saveWithPanel()
                }

                Spacer()

                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("저장") {
                    saveToDownloads()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sanitizedFileName.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360, height: 150)
        .background(CompactSheetSizer(size: CGSize(width: 360, height: 150)))
        .onAppear {
            fileName = defaultFileName
        }
    }

    private var sanitizedFileName: String {
        var name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        if !name.lowercased().hasSuffix(".json") {
            name += ".json"
        }
        return name
    }

    private func saveToDownloads() {
        let name = sanitizedFileName
        guard !name.isEmpty else { return }
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            saveWithPanel()
            return
        }
        let url = downloads.appendingPathComponent(name)
        onSave(url)
        dismiss()
    }

    private func saveWithPanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = sanitizedFileName.isEmpty ? defaultFileName : sanitizedFileName
        panel.title = title
        panel.prompt = "저장"
        // message를 넣지 않아 패널이 불필요하게 커지지 않게 합니다.

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                onSave(url)
                dismiss()
            }
        }
    }
}

/// macOS 시트 창 크기를 콘텐츠에 맞게 고정합니다.
private struct CompactSheetSizer: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.styleMask.remove(.resizable)
        window.setContentSize(size)
    }
}
