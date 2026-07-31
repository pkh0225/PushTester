import SwiftUI
import AppKit

/// 메인 화면 오른쪽 스플릿 — 앱 내에 저장한 설정 목록
struct SavedConfigSidebar: View {
    @EnvironmentObject private var savedConfigStore: SavedConfigStore
    @EnvironmentObject private var appAlertCenter: AppAlertCenter

    var platform: PushPlatform
    @Binding var selection: PushHistoryItem.ID?
    @Binding var showAddOverlay: Bool
    @Binding var addTitle: String
    @Binding var revealID: PushHistoryItem.ID?
    var onApply: (PushHistoryItem) -> Void

    @State private var editingItem: PushHistoryItem?

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
                    addTitle = suggestedTitle
                    showAddOverlay = true
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
                                        confirmDeleteSelected()
                                    }
                                }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.top, 4, for: .scrollContent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: revealID) { _, id in
                    guard let id else { return }
                    selection = id
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .top)
                        revealID = nil
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
                    confirmDeleteSelected()
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
        .sheet(item: $editingItem) { item in
            HistoryEditView(item: item, mode: .savedConfig) { updated in
                savedConfigStore.update(updated)
                selection = updated.id
            }
            .environmentObject(appAlertCenter)
            .appAlertOverlay(using: appAlertCenter)
        }
    }

    private func confirmDeleteSelected() {
        appAlertCenter.confirm(
            title: "선택한 저장 항목을 삭제할까요?",
            message: "삭제하면 되돌릴 수 없습니다.",
            confirmTitle: "삭제",
            isDestructive: true
        ) {
            if let selectedItem {
                let id = selectedItem.id
                savedConfigStore.delete(id: id)
                if selection == id {
                    selection = nil
                }
            }
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

/// 설정 저장 이름 입력 패널 (가운데 오버레이용)
struct SavedConfigNamePanel: View {
    @Binding var title: String
    var onSave: () -> Void
    var onCancel: () -> Void

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
                Spacer(minLength: 0)
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave()
    }
}

/// 메인 창 가운데에 설정 저장을 띄우는 딤드 오버레이
struct SavedConfigNameOverlay: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var title: String
    var onSave: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                isPresented = false
                            }

                        SavedConfigNamePanel(
                            title: $title,
                            onSave: {
                                onSave()
                                isPresented = false
                            },
                            onCancel: {
                                isPresented = false
                            }
                        )
                    }
                    .transition(.opacity)
                    .zIndex(2000)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isPresented)
    }
}

extension View {
    func savedConfigNameOverlay(
        isPresented: Binding<Bool>,
        title: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(
            SavedConfigNameOverlay(
                isPresented: isPresented,
                title: title,
                onSave: onSave
            )
        )
    }
}
