import SwiftUI

/// 라벨 옆 설정 아이콘 + 텍스트필드 옆 드롭다운으로 프리셋을 관리/선택하는 필드
struct PresetLabeledTextField: View {
    let title: String
    let fieldKey: FieldPresetKey
    @Binding var text: String
    var labelWidth: CGFloat = 110
    var monospace: Bool = false

    @EnvironmentObject private var presetStore: FieldPresetStore
    @State private var showEditor = false

    private var presets: [String] {
        presetStore.values(for: fieldKey)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                Group {
                    if monospace {
                        TextField("", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        TextField("", text: $text)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Menu {
                    if presets.isEmpty {
                        Text("저장된 항목 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(presets, id: \.self) { value in
                            Button(value) {
                                text = value
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
                    FieldPresetEditorView(fieldKey: fieldKey, title: title)
                        .environmentObject(presetStore)
                }
            }
        }
    }
}

/// 히스토리 편집 등 Form 안에서 쓰는 프리셋 텍스트 필드 (라벨이 Form에 붙는 형태)
struct PresetFormTextField: View {
    let title: String
    let fieldKey: FieldPresetKey
    @Binding var text: String
    var monospace: Bool = false

    @EnvironmentObject private var presetStore: FieldPresetStore
    @State private var showEditor = false

    private var presets: [String] {
        presetStore.values(for: fieldKey)
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
                    FieldPresetEditorView(fieldKey: fieldKey, title: title)
                        .environmentObject(presetStore)
                }
            }
            .frame(width: 160, alignment: .leading)

            if monospace {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
            }

            Menu {
                if presets.isEmpty {
                    Text("저장된 항목 없음")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets, id: \.self) { value in
                        Button(value) {
                            text = value
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

struct FieldPresetEditorView: View {
    let fieldKey: FieldPresetKey
    let title: String

    @EnvironmentObject private var presetStore: FieldPresetStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [String] = []
    @State private var newValue: String = ""
    @State private var isReady = false
    @State private var pendingDeleteIndex: Int?
    @State private var showDeleteConfirm = false
    @State private var scrollToIndex: Int?

    private var pendingDeleteLabel: String {
        guard let index = pendingDeleteIndex, draft.indices.contains(index) else {
            return ""
        }
        return draft[index]
    }

    private static let panelSize = CGSize(width: 360, height: 280)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title) 목록")
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
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("목록이 비어 있습니다")
                        .font(.subheadline)
                    Text("아래에서 \(title) 값을 추가하세요.")
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
                                TextField("값", text: binding(at: index))
                                    .textFieldStyle(.roundedBorder)
                                    .font(fieldKey == .deviceToken
                                          ? .system(.body, design: .monospaced)
                                          : .body)

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
                HStack(spacing: 8) {
                    TextField("새 \(title)", text: $newValue)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addNew)

                    Button("추가") {
                        addNew()
                    }
                    .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .onAppear {
            draft = presetStore.values(for: fieldKey)
            DispatchQueue.main.async {
                isReady = true
            }
        }
        .onChange(of: draft) { _, newValue in
            guard isReady else { return }
            presetStore.save(values: newValue, for: fieldKey)
        }
    }

    private func binding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft[index] },
            set: { draft[index] = $0 }
        )
    }

    private func addNew() {
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !draft.contains(where: { $0 == value }) {
            draft.append(value)
            scrollToIndex = draft.count - 1
        }
        newValue = ""
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
