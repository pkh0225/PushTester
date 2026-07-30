import SwiftUI
import AppKit

/// 앱 설정 시트. `AppSettingsCatalog`에 항목을 추가하면 목록이 확장됩니다.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var onSelect: (AppSettingsItemID) -> Void

    @State private var pendingDestructiveItem: AppSettingsItem?

    var body: some View {
        NavigationStack {
            List {
                Section("앱 정보") {
                    appInfoHeader

                    LabeledContent("버전", value: appVersionText)
                    LabeledContent("플랫폼", value: "macOS")
                    LabeledContent("GitHub") {
                        Link("github.com/pkh0225/PushTester", destination: appRepositoryURL)
                            .font(.body)
                    }
                    Text("APNs(iOS) · FCM(Android) 푸시 알림을 빠르게 보내 보고 검증하는 개발용 도구입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                }

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
        .frame(minWidth: 420, idealWidth: 440, minHeight: 320, idealHeight: 380)
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

    private var appInfoHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(appDisplayName)
                    .font(.headline)
                Text("Push Notification Tester")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "PushTester"
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    private var appRepositoryURL: URL {
        URL(string: "https://github.com/pkh0225/PushTester")!
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
