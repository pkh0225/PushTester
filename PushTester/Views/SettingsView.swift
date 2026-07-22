import SwiftUI

/// 앱 설정 시트. `AppSettingsCatalog`에 항목을 추가하면 목록이 확장됩니다.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var onSelect: (AppSettingsItemID) -> Void

    @State private var pendingDestructiveItem: AppSettingsItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppSettingsCatalog.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Button {
                                handleTap(item)
                            } label: {
                                settingsRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 440, minHeight: 280, idealHeight: 320)
        .alert(
            pendingDestructiveItem?.title ?? "확인",
            isPresented: Binding(
                get: { pendingDestructiveItem != nil },
                set: { if !$0 { pendingDestructiveItem = nil } }
            )
        ) {
            Button("취소", role: .cancel) {
                pendingDestructiveItem = nil
            }
            Button("초기화", role: .destructive) {
                if let item = pendingDestructiveItem {
                    onSelect(item.id)
                }
                pendingDestructiveItem = nil
                dismiss()
            }
        } message: {
            Text(pendingDestructiveItem?.subtitle ?? "")
        }
    }

    private func handleTap(_ item: AppSettingsItem) {
        switch item.role {
        case .destructive:
            pendingDestructiveItem = item
        case .normal:
            onSelect(item.id)
        }
    }

    @ViewBuilder
    private func settingsRow(_ item: AppSettingsItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.role == .destructive ? Color.red : Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(item.role == .destructive ? Color.red : Color.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsView(onSelect: { _ in })
}
