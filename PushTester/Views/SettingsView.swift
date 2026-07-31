import SwiftUI
import AppKit

/// 앱 설정 패널. `AppSettingsCatalog`에 항목을 추가하면 목록이 확장됩니다.
struct SettingsView: View {
    @EnvironmentObject private var appAlertCenter: AppAlertCenter

    var onSelect: (AppSettingsItemID) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정")
                    .font(.headline)
                Spacer()
                Button("닫기") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

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
            .listStyle(.inset)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private static let panelSize = CGSize(width: 440, height: 420)

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
            appAlertCenter.confirm(
                title: item.title,
                message: item.subtitle,
                confirmTitle: "초기화",
                isDestructive: true
            ) {
                onSelect(item.id)
                onClose()
            }
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

/// 메인 창 가운데에 설정을 띄우는 딤드 오버레이
struct SettingsOverlay: ViewModifier {
    @Binding var isPresented: Bool
    var onSelect: (AppSettingsItemID) -> Void

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

                        SettingsView(
                            onSelect: onSelect,
                            onClose: { isPresented = false }
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
    func settingsOverlay(
        isPresented: Binding<Bool>,
        onSelect: @escaping (AppSettingsItemID) -> Void
    ) -> some View {
        modifier(SettingsOverlay(isPresented: isPresented, onSelect: onSelect))
    }
}

#Preview {
    SettingsView(onSelect: { _ in }, onClose: {})
        .environmentObject(AppAlertCenter())
}
