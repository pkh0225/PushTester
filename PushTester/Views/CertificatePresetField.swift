import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 인증서 라벨 옆 설정 + Import/파일명 + 드롭다운 선택
struct CertificatePresetField: View {
    let title: String
    let kind: CertificatePresetKind
    @Binding var fileName: String
    var labelWidth: CGFloat = 110
    var onApply: (CertificatePresetItem) -> Void

    @EnvironmentObject private var certificateStore: CertificatePresetStore
    @EnvironmentObject private var appAlertCenter: AppAlertCenter
    @State private var showEditor = false

    private var presets: [CertificatePresetItem] {
        certificateStore.items(for: kind)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    importCertificate()
                } label: {
                    Label(kind.importButtonTitle, systemImage: "plus.circle.fill")
                }
                .tint(.green)
                .fixedSize()

                Menu {
                    if presets.isEmpty {
                        Text("저장된 항목 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(presets) { item in
                            Button(item.name) {
                                onApply(item)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("저장된 \(title) 선택")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .frame(width: labelWidth, alignment: .trailing)

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(title) 목록 관리")
                .popover(isPresented: $showEditor, arrowEdge: .leading) {
                    CertificatePresetEditorView(
                        kind: kind,
                        onApply: onApply,
                        onRequestAddFile: {
                            showEditor = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                importCertificate()
                            }
                        }
                    )
                    .environmentObject(certificateStore)
                }
            }
        }
    }

    private func importCertificate() {
        let store = certificateStore
        let apply = onApply
        let alerts = appAlertCenter
        CertificateFileImporter.pick(kind: kind) { result in
            switch result {
            case .success(let item):
                store.upsert(item, for: kind)
                apply(item)
            case .failure(let error):
                if case CertificateImportError.cancelled = error { return }
                alerts.notice(
                    title: "가져오기 실패",
                    message: error.localizedDescription
                )
            }
        }
    }
}

/// 히스토리 편집용 인증서 프리셋 필드
struct CertificatePresetFormField: View {
    let title: String
    let kind: CertificatePresetKind
    @Binding var fileName: String
    var onApply: (CertificatePresetItem) -> Void

    @EnvironmentObject private var certificateStore: CertificatePresetStore
    @EnvironmentObject private var appAlertCenter: AppAlertCenter
    @State private var showEditor = false

    private var presets: [CertificatePresetItem] {
        certificateStore.items(for: kind)
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("\(title) 목록 관리")
                .popover(isPresented: $showEditor, arrowEdge: .leading) {
                    CertificatePresetEditorView(
                        kind: kind,
                        onApply: onApply,
                        onRequestAddFile: {
                            showEditor = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // 히스토리 편집에서는 Import 버튼이 없어 여기서 직접 추가
                                let store = certificateStore
                                let apply = onApply
                                let alerts = appAlertCenter
                                CertificateFileImporter.pick(kind: kind) { result in
                                    switch result {
                                    case .success(let item):
                                        store.upsert(item, for: kind)
                                        apply(item)
                                    case .failure(let error):
                                        if case CertificateImportError.cancelled = error { return }
                                        alerts.notice(
                                            title: "추가 실패",
                                            message: error.localizedDescription
                                        )
                                    }
                                }
                            }
                        }
                    )
                    .environmentObject(certificateStore)
                }
            }
            .frame(width: 160, alignment: .leading)

            Text(fileName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )

            Menu {
                if presets.isEmpty {
                    Text("저장된 항목 없음")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets) { item in
                        Button(item.name) {
                            onApply(item)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("저장된 \(title) 선택")
        }
    }
}

struct CertificatePresetEditorView: View {
    let kind: CertificatePresetKind
    var onApply: (CertificatePresetItem) -> Void
    var onRequestAddFile: () -> Void

    @EnvironmentObject private var certificateStore: CertificatePresetStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [CertificatePresetItem] = []
    @State private var isReady = false
    @State private var pendingDeleteIndex: Int?
    @State private var showDeleteConfirm = false
    @State private var scrollToIndex: Int?

    private var pendingDeleteLabel: String {
        guard let index = pendingDeleteIndex, draft.indices.contains(index) else {
            return ""
        }
        return draft[index].name
    }

    private static let panelSize = CGSize(width: 360, height: 280)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(kind.displayTitle) 목록")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if draft.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("목록이 비어 있습니다")
                        .font(.subheadline)
                    Text("아래에서 인증서 파일을 추가하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(draft.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("이름", text: nameBinding(at: index))
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    pendingDeleteIndex = index
                                    showDeleteConfirm = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("삭제")
                            }
                            .id(index)
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: scrollToIndex) { _, index in
                        guard let index else { return }
                        scrollToAddedItem(proxy: proxy, index: index)
                    }
                    .onAppear {
                        if let index = scrollToIndex {
                            scrollToAddedItem(proxy: proxy, index: index)
                        }
                    }
                }
            }

            Divider()

            if showDeleteConfirm {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("삭제할까요?")
                            .font(.subheadline.weight(.semibold))
                        if !pendingDeleteLabel.isEmpty {
                            Text(pendingDeleteLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("취소") {
                        showDeleteConfirm = false
                        pendingDeleteIndex = nil
                    }
                    .controlSize(.small)

                    Button("삭제", role: .destructive) {
                        if let index = pendingDeleteIndex {
                            deleteItem(at: index)
                        }
                        showDeleteConfirm = false
                        pendingDeleteIndex = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
            } else {
                HStack {
                    Button {
                        // 팝오버 안에서는 파일 패널이 취소되는 경우가 있어
                        // 닫은 뒤 부모에서 파일을 선택합니다.
                        onRequestAddFile()
                    } label: {
                        Label("파일 추가", systemImage: "plus.circle.fill")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .onAppear {
            draft = certificateStore.items(for: kind)
            DispatchQueue.main.async {
                isReady = true
            }
        }
        .onChange(of: certificateStore.itemsByKind) { _, _ in
            let storeItems = certificateStore.items(for: kind)
            if draft.count != storeItems.count || draft.map(\.content) != storeItems.map(\.content) {
                draft = storeItems
            }
        }
        .onChange(of: draft) { _, newValue in
            guard isReady else { return }
            certificateStore.save(items: newValue, for: kind)
        }
    }

    private func nameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft[index].name },
            set: { draft[index].name = $0 }
        )
    }

    private func deleteItem(at index: Int) {
        guard draft.indices.contains(index) else { return }
        draft.remove(at: index)
    }

    private func scrollToAddedItem(proxy: ScrollViewProxy, index: Int) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(index, anchor: .bottom)
            }
            scrollToIndex = nil
        }
    }
}

enum CertificateImportError: LocalizedError {
    case cancelled
    case invalidP8
    case invalidServiceAccount(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .invalidP8:
            return "선택한 파일이 유효한 .p8 키가 아닙니다."
        case .invalidServiceAccount(let message):
            return "서비스 계정을 읽지 못했습니다: \(message)"
        case .readFailed(let message):
            return "파일을 읽지 못했습니다: \(message)"
        }
    }
}

enum CertificateFileImporter {
    @MainActor
    static func pick(
        kind: CertificatePresetKind,
        completion: @escaping (Result<CertificatePresetItem, CertificateImportError>) -> Void
    ) {
        let panel = makePanel(for: kind)

        // 팝오버/시트 위 runModal은 취소되는 경우가 많아 앱 모달 begin을 사용합니다.
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else {
                    completion(.failure(.cancelled))
                    return
                }
                completion(readItem(kind: kind, from: url))
            }
        }
    }

    private static func makePanel(for kind: CertificatePresetKind) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "추가"

        switch kind {
        case .apnsP8:
            panel.allowedContentTypes = [
                UTType(filenameExtension: "p8") ?? .data,
                .plainText
            ]
            panel.message = "APNs Auth Key (.p8) 파일을 선택하세요"
        case .fcmServiceAccount:
            panel.allowedContentTypes = [.json]
            panel.message = "Firebase 서비스 계정 JSON 파일을 선택하세요"
        }
        return panel
    }

    private static func readItem(
        kind: CertificatePresetKind,
        from url: URL
    ) -> Result<CertificatePresetItem, CertificateImportError> {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        switch kind {
        case .apnsP8:
            do {
                let contents = try readTextFile(from: url)
                guard contents.localizedCaseInsensitiveContains("BEGIN"),
                      contents.localizedCaseInsensitiveContains("PRIVATE KEY") else {
                    return .failure(.invalidP8)
                }
                let privateKey = try APNsJWT.loadPrivateKey(from: contents)
                return .success(
                    CertificatePresetItem(
                        name: url.lastPathComponent,
                        content: privateKey.pemRepresentation
                    )
                )
            } catch let error as CertificateImportError {
                return .failure(error)
            } catch {
                return .failure(.readFailed(error.localizedDescription))
            }

        case .fcmServiceAccount:
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                _ = try GoogleServiceAccount.parse(from: contents)
                return .success(
                    CertificatePresetItem(
                        name: url.lastPathComponent,
                        content: contents
                    )
                )
            } catch {
                return .failure(.invalidServiceAccount(error.localizedDescription))
            }
        }
    }

    private static func readTextFile(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        if let utf16 = try? String(contentsOf: url, encoding: .utf16) {
            return utf16
        }
        let data = try Data(contentsOf: url)
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        throw CertificateImportError.readFailed("지원하지 않는 인코딩입니다.")
    }
}
