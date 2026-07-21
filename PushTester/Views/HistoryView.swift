import SwiftUI

/// 메인 화면 왼쪽 스플릿에 표시되는 히스토리 목록
struct HistorySidebar: View {
    @EnvironmentObject private var historyStore: HistoryStore

    var platform: PushPlatform
    @Binding var selection: PushHistoryItem.ID?
    var onApply: (PushHistoryItem) -> Void

    @State private var editingItem: PushHistoryItem?
    @State private var showDeleteConfirm = false

    private var filteredItems: [PushHistoryItem] {
        historyStore.items(for: platform)
    }

    private var selectedItem: PushHistoryItem? {
        guard let selection else { return nil }
        return filteredItems.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "히스토리 없음",
                    systemImage: "clock",
                    description: Text("\(platform.title) 푸시 발송에 성공하면\n여기에 기록됩니다.")
                )
            } else {
                List(filteredItems, selection: $selection) { item in
                    HistoryRow(item: item)
                        .tag(item.id)
                        // simultaneousGesture로 단일 클릭 선택은 유지하고 더블클릭만 적용
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selection = item.id
                                onApply(item)
                            }
                        )
                        .contextMenu {
                            Button("적용") {
                                selection = item.id
                                onApply(item)
                            }
                            Button("편집") {
                                editingItem = item
                            }
                            Divider()
                            Button("삭제", role: .destructive) {
                                selection = item.id
                                showDeleteConfirm = true
                            }
                        }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 8) {
                Button("편집") {
                    editingItem = selectedItem
                }
                .disabled(selectedItem == nil)

                Button("삭제", role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(selectedItem == nil)

                Spacer()

                Button("적용") {
                    if let selectedItem {
                        onApply(selectedItem)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("\(platform.title) 히스토리")
        .onChange(of: platform) { _, _ in
            selection = nil
        }
        .sheet(item: $editingItem) { item in
            HistoryEditView(item: item) { updated in
                historyStore.update(updated)
                selection = updated.id
            }
        }
        .confirmationDialog(
            "선택한 히스토리를 삭제할까요?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let selectedItem {
                    let id = selectedItem.id
                    historyStore.delete(id: id)
                    if selection == id {
                        selection = nil
                    }
                }
            }
            Button("취소", role: .cancel) {}
        }
    }
}

private struct HistoryRow: View {
    let item: PushHistoryItem

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            Text(item.bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(item.pushPlatform.title)
                Text("·")
                Text(Self.dateFormatter.string(from: item.sentAt))
                Text("·")
                Text(item.environmentDisplay)
                Text("·")
                Text(item.pushTypeDisplay)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct HistoryEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PushHistoryItem
    let onSave: (PushHistoryItem) -> Void

    init(item: PushHistoryItem, onSave: @escaping (PushHistoryItem) -> Void) {
        _draft = State(initialValue: item)
        self.onSave = onSave
    }

    private var isAndroid: Bool {
        draft.pushPlatform == .android
    }

    var body: some View {
        NavigationStack {
            Form {
                PresetFormTextField(
                    title: "제목",
                    fieldKey: .title,
                    text: $draft.title
                )

                if isAndroid {
                    PresetFormTextField(
                        title: "Project ID",
                        fieldKey: .projectID,
                        text: $draft.bundleID
                    )
                    PresetFormTextField(
                        title: "Device Token",
                        fieldKey: .deviceToken,
                        text: $draft.deviceToken,
                        monospace: true
                    )
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(FCMPriority.allCases) { value in
                            Text(value.title).tag(value.historyValue)
                        }
                    }
                    CertificatePresetFormField(
                        title: "인증서",
                        kind: .fcmServiceAccount,
                        fileName: $draft.p8FileName
                    ) { item in
                        draft.p8FileName = item.name
                        draft.p8PEM = item.content
                    }
                } else {
                    PresetFormTextField(
                        title: "Bundle ID",
                        fieldKey: .bundleID,
                        text: $draft.bundleID
                    )
                    PresetFormTextField(
                        title: "Team ID",
                        fieldKey: .teamID,
                        text: $draft.teamID
                    )
                    PresetFormTextField(
                        title: "Key ID",
                        fieldKey: .keyID,
                        text: $draft.keyID
                    )
                    PresetFormTextField(
                        title: "Device Token",
                        fieldKey: .deviceToken,
                        text: $draft.deviceToken,
                        monospace: true
                    )

                    Picker("APN Server", selection: $draft.environment) {
                        ForEach(APNsEnvironment.allCases) { env in
                            Text(env.rawValue).tag(env.rawValue)
                        }
                    }

                    Picker("Priority", selection: $draft.priority) {
                        ForEach(APNsPriority.allCases) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                    }

                    Picker("Push Type", selection: $draft.pushType) {
                        ForEach(APNsPushType.allCases) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }

                    CertificatePresetFormField(
                        title: "인증서",
                        kind: .apnsP8,
                        fileName: $draft.p8FileName
                    ) { item in
                        draft.p8FileName = item.name
                        draft.p8PEM = item.content
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payload")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.payload)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("히스토리 편집")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

#if DEBUG
private enum HistoryPreviewData {
    static let sampleItem = PushHistoryItem(
        id: UUID(),
        title: "[테스트] 텍스트 푸시",
        sentAt: Date(),
        teamID: "TEAMID1234",
        bundleID: "com.example.app",
        keyID: "KEYID12345",
        deviceToken: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        environment: APNsEnvironment.sandbox.rawValue,
        priority: APNsPriority.immediate.rawValue,
        pushType: APNsPushType.alert.rawValue,
        payload: PayloadTemplates.alert,
        p8FileName: "AuthKey_TEST.p8",
        p8PEM: "",
        apnsID: "00000000-0000-0000-0000-000000000000",
        statusCode: 200
    )

    static let items: [PushHistoryItem] = [
        sampleItem,
        PushHistoryItem(
            id: UUID(),
            title: "백그라운드 갱신",
            sentAt: Date().addingTimeInterval(-3600),
            teamID: "TEAMID1234",
            bundleID: "com.example.app",
            keyID: "KEYID12345",
            deviceToken: "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
            environment: APNsEnvironment.production.rawValue,
            priority: APNsPriority.powerConsiderations.rawValue,
            pushType: APNsPushType.background.rawValue,
            payload: PayloadTemplates.background,
            p8FileName: "AuthKey_TEST.p8",
            p8PEM: "",
            apnsID: nil,
            statusCode: 200
        )
    ]
}

#Preview("히스토리 사이드바") {
    NavigationSplitView {
        HistorySidebar(
            platform: .ios,
            selection: .constant(HistoryPreviewData.sampleItem.id),
            onApply: { _ in }
        )
        .environmentObject(HistoryStore(previewItems: HistoryPreviewData.items))
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
    } detail: {
        Text("메인 입력 영역")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 900, height: 640)
}

#Preview("히스토리 비어 있음") {
    HistorySidebar(platform: .ios, selection: .constant(nil), onApply: { _ in })
        .environmentObject(HistoryStore(previewItems: []))
        .frame(width: 280, height: 640)
}

#Preview("히스토리 편집") {
    HistoryEditView(item: HistoryPreviewData.sampleItem, onSave: { _ in })
        .environmentObject(FieldPresetStore())
        .environmentObject(CertificatePresetStore())
}
#endif

