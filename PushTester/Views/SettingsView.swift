import SwiftUI
import AppKit

private struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 앱 설정 패널. `AppSettingsCatalog`에 항목을 추가하면 목록이 확장됩니다.
struct SettingsView: View {
    @EnvironmentObject private var appAlertCenter: AppAlertCenter

    var onSelect: (AppSettingsItemID) -> Void
    var onClose: () -> Void
    /// 메인 창을 넘지 않도록 오버레이에서 넘기는 상한
    var maxHeight: CGFloat

    @State private var contentHeight: CGFloat = 0

    private let panelWidth: CGFloat = 440
    private let headerHeight: CGFloat = 49

    private var panelHeight: CGFloat {
        let fitting = contentHeight + headerHeight
        guard fitting > 0 else { return min(360, maxHeight) }
        return min(fitting, maxHeight)
    }

    private var needsScroll: Bool {
        contentHeight + headerHeight > maxHeight + 0.5
    }

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
            .frame(height: headerHeight)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsSection("앱 정보") {
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
                        settingsSection(section.title) {
                            ForEach(section.items) { item in
                                switch item.control {
                                case .action:
                                    Button {
                                        handleTap(item)
                                    } label: {
                                        settingsRow(item)
                                    }
                                    .buttonStyle(.plain)
                                case .toggle(let defaultsKey, let defaultValue):
                                    settingsToggleRow(
                                        item,
                                        defaultsKey: defaultsKey,
                                        defaultValue: defaultValue
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SettingsContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .scrollDisabled(!needsScroll)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onPreferenceChange(SettingsContentHeightKey.self) { contentHeight = $0 }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        switch item.id {
        case .checkForUpdateOnLaunch:
            break
        case .checkForUpdate:
            AppUpdateChecker.checkFromSettings(using: appAlertCenter)
        case .resetAllData:
            appAlertCenter.confirm(
                title: item.title,
                message: item.subtitle,
                confirmTitle: "초기화",
                isDestructive: true
            ) {
                onSelect(item.id)
                onClose()
            }
        }
    }

    @ViewBuilder
    private func settingsToggleRow(
        _ item: AppSettingsItem,
        defaultsKey: String,
        defaultValue: Bool
    ) -> some View {
        SettingsToggleRow(
            item: item,
            defaultsKey: defaultsKey,
            defaultValue: defaultValue
        )
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

/// `@AppStorage` 키를 항목별로 받기 위한 토글 행
private struct SettingsToggleRow: View {
    let item: AppSettingsItem
    let defaultsKey: String
    let defaultValue: Bool

    @AppStorage private var isOn: Bool

    init(item: AppSettingsItem, defaultsKey: String, defaultValue: Bool) {
        self.item = item
        self.defaultsKey = defaultsKey
        self.defaultValue = defaultValue
        _isOn = AppStorage(wrappedValue: defaultValue, defaultsKey)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.toggle()
        }
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
                    GeometryReader { proxy in
                        let maxHeight = max(proxy.size.height * 0.9, 240)

                        ZStack {
                            Color.black.opacity(0.45)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    isPresented = false
                                }

                            SettingsView(
                                onSelect: onSelect,
                                onClose: { isPresented = false },
                                maxHeight: maxHeight
                            )
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
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
    SettingsView(onSelect: { _ in }, onClose: {}, maxHeight: 700)
        .environmentObject(AppAlertCenter())
}
