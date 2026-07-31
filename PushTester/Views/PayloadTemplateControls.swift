import SwiftUI

/// 커스텀 Payload 템플릿 불러오기/저장
struct PayloadTemplateControls: View {
    let platform: PayloadTemplatePlatform
    @Binding var payload: String
    var onStatus: (String) -> Void

    @EnvironmentObject private var templateStore: PayloadTemplateStore
    @State private var showSaveSheet = false
    @State private var saveName = ""
    @State private var showEditor = false

    private var templates: [PayloadTemplateItem] {
        templateStore.items(for: platform)
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                if templates.isEmpty {
                    Text("저장된 템플릿 없음")
                } else {
                    ForEach(templates) { item in
                        Button(item.name) {
                            payload = item.content
                            onStatus("템플릿 적용: \(item.name)")
                        }
                    }
                }
            } label: {
                Label("템플릿", systemImage: "doc.text")
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .help("저장해 둔 Payload 템플릿을 불러옵니다.")

            Divider()
                .frame(height: 16)

            Button("저장") {
                saveName = ""
                showSaveSheet = true
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .help("현재 Payload를 템플릿으로 저장합니다.")

            Divider()
                .frame(height: 16)

            Button {
                showEditor = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Payload 템플릿 목록 관리")
            .popover(isPresented: $showEditor, arrowEdge: .bottom) {
                PayloadTemplateEditorView(platform: platform) { item in
                    payload = item.content
                    onStatus("템플릿 적용: \(item.name)")
                    showEditor = false
                }
                .environmentObject(templateStore)
            }
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .fixedSize()
        .sheet(isPresented: $showSaveSheet) {
            PayloadTemplateSaveSheet(name: $saveName) {
                let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                templateStore.upsert(
                    PayloadTemplateItem(name: trimmed, content: payload),
                    for: platform
                )
                onStatus("템플릿 저장: \(trimmed)")
                showSaveSheet = false
            } onCancel: {
                showSaveSheet = false
            }
        }
    }
}

private struct PayloadTemplateSaveSheet: View {
    @Binding var name: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Payload 템플릿 저장")
                .font(.headline)
            TextField("템플릿 이름", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct PayloadTemplateEditorView: View {
    let platform: PayloadTemplatePlatform
    var onApply: (PayloadTemplateItem) -> Void

    @EnvironmentObject private var templateStore: PayloadTemplateStore
    @EnvironmentObject private var appAlertCenter: AppAlertCenter
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [PayloadTemplateItem] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(platform.displayTitle) Payload 템플릿")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if draft.isEmpty {
                ContentUnavailableView(
                    "템플릿 없음",
                    systemImage: "doc.text",
                    description: Text("Payload 옆 저장으로 추가할 수 있습니다.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(draft.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                Text(item.content.replacingOccurrences(of: "\n", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("적용") {
                                onApply(item)
                            }
                            Button {
                                confirmDelete(at: index, item: item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 280)
        .onAppear {
            draft = templateStore.items(for: platform)
        }
    }

    private func confirmDelete(at index: Int, item: PayloadTemplateItem) {
        appAlertCenter.confirm(
            title: "템플릿 삭제",
            message: "‘\(item.name)’ 템플릿을 삭제할까요?",
            confirmTitle: "삭제",
            isDestructive: true
        ) {
            guard draft.indices.contains(index), draft[index].id == item.id else {
                draft.removeAll { $0.id == item.id }
                templateStore.save(items: draft, for: platform)
                return
            }
            draft.remove(at: index)
            templateStore.save(items: draft, for: platform)
        }
    }
}
