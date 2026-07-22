import SwiftUI
import AppKit

/// 메인 화면 오른쪽 스플릿 — 앱 내에 저장한 설정 목록
struct SavedConfigSidebar: View {
    @EnvironmentObject private var savedConfigStore: SavedConfigStore

    var platform: PushPlatform
    @Binding var selection: PushHistoryItem.ID?
    var makeItem: (String) -> PushHistoryItem
    var onApply: (PushHistoryItem) -> Void

    @State private var editingItem: PushHistoryItem?
    @State private var showDeleteConfirm = false
    @State private var showAddSheet = false
    @State private var newTitle = ""
    /// 시트 닫힌 뒤에 선택·스크롤을 적용해 List 첫 행이 헤더에 가려지지 않게 합니다.
    @State private var pendingRevealID: PushHistoryItem.ID?

    private var filteredItems: [PushHistoryItem] {
        savedConfigStore.items(for: platform)
    }

    private var selectedItem: PushHistoryItem? {
        guard let selection else { return nil }
        return filteredItems.first { $0.id == selection }
    }

    private var suggestedTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return "\(platform.title) 설정 · \(formatter.string(from: Date()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("저장목록")
                        .font(.headline)
                    Text(platform.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    newTitle = suggestedTitle
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("현재 입력값을 앱에 저장")
                .accessibilityLabel("설정 저장")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                Group {
                    if filteredItems.isEmpty {
                        ContentUnavailableView(
                            "저장된 설정 없음",
                            systemImage: "square.and.arrow.down",
                            description: Text("오른쪽 위 + 로\n현재 입력값을 저장하세요.")
                        )
                    } else {
                        List(filteredItems, selection: $selection) { item in
                            SavedConfigRow(item: item)
                                .tag(item.id)
                                .id(item.id)
                                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
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
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.top, 4, for: .scrollContent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: showAddSheet) { _, isPresented in
                    guard !isPresented, let id = pendingRevealID else { return }
                    selection = id
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .top)
                        pendingRevealID = nil
                    }
                }
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

                Spacer(minLength: 0)

                Button("적용") {
                    if let selectedItem {
                        onApply(selectedItem)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil)
                .layoutPriority(1)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onChange(of: platform) { _, _ in
            selection = nil
        }
        .sheet(isPresented: $showAddSheet) {
            SavedConfigNameSheet(title: $newTitle) {
                let item = makeItem(newTitle)
                savedConfigStore.add(item)
                pendingRevealID = item.id
            }
        }
        .sheet(item: $editingItem) { item in
            HistoryEditView(item: item, mode: .savedConfig) { updated in
                savedConfigStore.update(updated)
                selection = updated.id
            }
        }
        .alert("선택한 저장 항목을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let selectedItem {
                    let id = selectedItem.id
                    savedConfigStore.delete(id: id)
                    if selection == id {
                        selection = nil
                    }
                }
            }
        } message: {
            Text("삭제하면 되돌릴 수 없습니다.")
        }
    }
}

private struct SavedConfigRow: View {
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
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(item.pushPlatform.title)
                Text("·")
                Text(Self.dateFormatter.string(from: item.sentAt))
                Text("·")
                Text(item.environmentDisplay)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SavedConfigNameSheet: View {
    @Binding var title: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("설정 저장")
                .font(.headline)

            Text("현재 입력값을 앱에 저장합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("이름", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340, height: 150)
        .background(SavedConfigSheetSizer(size: CGSize(width: 340, height: 150)))
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave()
        dismiss()
    }
}

private struct SavedConfigSheetSizer: NSViewRepresentable {
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
