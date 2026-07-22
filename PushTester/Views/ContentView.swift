import SwiftUI
import AppKit
import Combine

@MainActor
final class PushTesterViewModel: ObservableObject {
    @Published var teamID: String = ""
    @Published var bundleID: String = ""
    @Published var keyID: String = ""
    @Published var deviceToken: String = ""
    @Published var environment: APNsEnvironment = .sandbox
    @Published var priority: APNsPriority = .immediate
    @Published var pushType: APNsPushType = .alert
    @Published var payload: String = PayloadTemplates.alert
    @Published var statusMessage: String = "Ready"
    @Published var isSending = false
    @Published var p8FileName: String = "No key imported"

    private var p8PEM: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var isRestoring = false

    var canSend: Bool {
        !isSending
    }

    init() {
        restoreLastSession()
        observeChangesForAutosave()
    }

    func applyP8Certificate(_ item: CertificatePresetItem) {
        do {
            let privateKey = try APNsJWT.loadPrivateKey(from: item.content)
            p8PEM = privateKey.pemRepresentation
            p8FileName = item.name
            statusMessage = "Key imported: \(item.name)"
            persistLastSession()
        } catch {
            statusMessage = "키를 적용하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func loadTemplate() {
        guard !isRestoring else { return }
        payload = PayloadTemplates.template(for: pushType)
        statusMessage = "Loaded \(pushType.displayName) template"
    }

    func pushTypeChanged(to newType: APNsPushType) {
        guard !isRestoring else { return }
        payload = PayloadTemplates.template(for: newType)
        statusMessage = "Push Type → \(newType.displayName) (payload template updated)"
    }

    func sendPush(recordingInto historyStore: HistoryStore) {
        guard canSend else { return }

        let sessionSnapshot = currentSession()
        let request = APNsSendRequest(
            teamID: teamID,
            keyID: keyID,
            bundleID: bundleID,
            deviceToken: deviceToken,
            p8PEM: p8PEM,
            environment: environment,
            priority: priority,
            pushType: pushType,
            payload: payload
        )

        isSending = true
        statusMessage = "Sending..."
        persistLastSession()

        Task {
            do {
                let result = try await APNsClient.send(request)
                historyStore.addSuccess(
                    session: sessionSnapshot,
                    apnsID: result.apnsID,
                    statusCode: result.statusCode
                )
                if let apnsID = result.apnsID, !apnsID.isEmpty {
                    statusMessage = "Success (HTTP \(result.statusCode)) · apns-id: \(apnsID)"
                } else {
                    statusMessage = "Success (HTTP \(result.statusCode))"
                }
            } catch {
                statusMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    func applyHistory(_ item: PushHistoryItem) {
        apply(item.session)

        if !item.p8PEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let privateKey = try APNsJWT.loadPrivateKey(from: item.p8PEM)
                p8PEM = privateKey.pemRepresentation
                statusMessage = "히스토리 적용: \(item.title)"
            } catch {
                p8PEM = ""
                p8FileName = "No key imported"
                statusMessage = "히스토리를 적용했습니다. .p8 키를 다시 Import 해 주세요."
            }
        } else {
            statusMessage = "히스토리 적용: \(item.title)"
        }

        persistLastSession()
    }

    func makeSavedConfig(title: String) -> PushHistoryItem {
        PushHistoryItem.makeSaved(from: currentSession(), title: title)
    }

    func applySavedConfig(_ item: PushHistoryItem) {
        applyHistory(item)
        statusMessage = "저장 설정 적용: \(item.title)"
    }

    func exportSession(to url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try SessionStore.export(currentSession(), to: url)
            persistLastSession()
            statusMessage = "Saved: \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadSessionFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.title = "설정 불러오기"
        panel.prompt = "불러오기"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let session = try SessionStore.import(from: url)
                    self.apply(session)
                    self.persistLastSession()
                    self.statusMessage = "Loaded: \(url.lastPathComponent)"
                } catch {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func restoreLastSession() {
        guard let session = SessionStore.loadLastSession() else { return }
        apply(session)
        if !session.p8PEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let privateKey = try APNsJWT.loadPrivateKey(from: session.p8PEM)
                p8PEM = privateKey.pemRepresentation
                statusMessage = "Restored last session"
            } catch {
                p8PEM = ""
                p8FileName = "No key imported"
                statusMessage = "이전 세션을 복원했습니다. .p8 키를 다시 Import 해 주세요."
            }
        } else {
            statusMessage = "Restored last session"
        }
    }

    private func observeChangesForAutosave() {
        let publishers: [AnyPublisher<Void, Never>] = [
            $teamID.map { _ in () }.eraseToAnyPublisher(),
            $bundleID.map { _ in () }.eraseToAnyPublisher(),
            $keyID.map { _ in () }.eraseToAnyPublisher(),
            $deviceToken.map { _ in () }.eraseToAnyPublisher(),
            $environment.map { _ in () }.eraseToAnyPublisher(),
            $priority.map { _ in () }.eraseToAnyPublisher(),
            $pushType.map { _ in () }.eraseToAnyPublisher(),
            $payload.map { _ in () }.eraseToAnyPublisher(),
            $p8FileName.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.persistLastSession()
            }
            .store(in: &cancellables)
    }

    private func persistLastSession() {
        guard !isRestoring else { return }
        try? SessionStore.saveLastSession(currentSession())
    }

    private func currentSession() -> PushSession {
        PushSession(
            teamID: teamID,
            bundleID: bundleID,
            keyID: keyID,
            deviceToken: deviceToken,
            environment: environment.rawValue,
            priority: priority.rawValue,
            pushType: pushType.rawValue,
            payload: payload,
            p8FileName: p8FileName,
            p8PEM: p8PEM
        )
    }

    func resetToDefaults() {
        apply(PushSession.empty)
        statusMessage = "Ready"
        SessionStore.clearLastSession()
    }

    private func apply(_ session: PushSession) {
        isRestoring = true

        teamID = session.teamID
        bundleID = session.bundleID
        keyID = session.keyID
        deviceToken = session.deviceToken
        environment = APNsEnvironment(rawValue: session.environment) ?? .sandbox
        priority = APNsPriority(rawValue: session.priority) ?? .immediate
        pushType = APNsPushType(rawValue: session.pushType) ?? .alert
        payload = session.payload.isEmpty ? PayloadTemplates.alert : session.payload
        p8FileName = session.p8FileName.isEmpty ? "No key imported" : session.p8FileName
        p8PEM = session.p8PEM

        // onChange(pushType)가 복원 직후 템플릿으로 payload를 덮어쓰지 않도록
        // 다음 런루프까지 isRestoring을 유지합니다.
        DispatchQueue.main.async { [weak self] in
            self?.isRestoring = false
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = PushTesterViewModel()
    @StateObject private var androidViewModel = AndroidPushViewModel()
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var savedConfigStore: SavedConfigStore
    @EnvironmentObject private var fieldPresetStore: FieldPresetStore
    @EnvironmentObject private var certificatePresetStore: CertificatePresetStore
    @State private var selectedHistoryID: PushHistoryItem.ID?
    @State private var selectedSavedConfigID: PushHistoryItem.ID?
    @State private var platform: PushPlatform = .ios
    @State private var showIOSSaveSheet = false
    @State private var showHistorySidebar = true
    @State private var showSavedConfigSidebar = true
    @State private var showSettings = false

    private let labelWidth: CGFloat = 110

    /// 펼쳐진 패널 기준으로 창이 더 작아지지 않게 해 가운데 최소 너비를 지킵니다.
    private var effectiveWindowMinWidth: CGFloat {
        MainLayoutMetrics.windowMinWidth(
            sidebarVisible: showHistorySidebar,
            inspectorVisible: showSavedConfigSidebar
        )
    }

    var body: some View {
        // NavigationSplitView/inspector 는 컬럼이 줄어들 때 실제 제안 너비와
        // 클리핑이 어긋나 leading/trailing이 잘리는 경우가 있어 HSplitView 를 씁니다.
        HSplitView {
            if showHistorySidebar {
                HistorySidebar(
                    platform: platform,
                    selection: $selectedHistoryID
                ) { item in
                    applyHistoryItem(item)
                }
                .frame(
                    minWidth: MainLayoutMetrics.sideMin,
                    idealWidth: MainLayoutMetrics.sideIdeal,
                    maxWidth: MainLayoutMetrics.sideMax
                )
            }

            detailColumn
                .frame(minWidth: MainLayoutMetrics.centerMin)
                .layoutPriority(1)

            if showSavedConfigSidebar {
                SavedConfigSidebar(
                    platform: platform,
                    selection: $selectedSavedConfigID,
                    makeItem: { title in
                        switch platform {
                        case .ios:
                            return viewModel.makeSavedConfig(title: title)
                        case .android:
                            return androidViewModel.makeSavedConfig(title: title)
                        }
                    },
                    onApply: { item in
                        applySavedConfigItem(item)
                    }
                )
                .frame(
                    minWidth: MainLayoutMetrics.sideMin,
                    idealWidth: MainLayoutMetrics.sideIdeal,
                    maxWidth: MainLayoutMetrics.sideMax
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showHistorySidebar.toggle()
                } label: {
                    Label(
                        "히스토리",
                        systemImage: showHistorySidebar ? "sidebar.leading" : "sidebar.left"
                    )
                }
                .help(showHistorySidebar ? "히스토리 접기" : "히스토리 펼치기")
            }
            // 가운데: 앱 타이틀 + 바로 오른쪽 설정 (글래스/라운드 그룹 배경 제거)
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .principal) {
                    titleWithSettingsControl
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) {
                    titleWithSettingsControl
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSavedConfigSidebar.toggle()
                } label: {
                    Label(
                        "저장목록",
                        systemImage: showSavedConfigSidebar ? "sidebar.trailing" : "sidebar.right"
                    )
                }
                .help(showSavedConfigSidebar ? "저장목록 접기" : "저장목록 펼치기")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView { itemID in
                handleSettingsAction(itemID)
            }
        }
        .onChange(of: platform) { _, _ in
            selectedHistoryID = nil
            selectedSavedConfigID = nil
        }
        .onChange(of: showHistorySidebar) { _, _ in
            enforceWindowMinWidth()
        }
        .onChange(of: showSavedConfigSidebar) { _, _ in
            enforceWindowMinWidth()
        }
        .background(WindowMinWidthEnforcer(minWidth: effectiveWindowMinWidth))
        .onAppear {
            enforceWindowMinWidth()
        }
    }

    /// 흰색 계열 — 순백보다 살짝 부드러운 쿨 화이트
    private var brandTitleColor: Color {
        Color(red: 0.93, green: 0.94, blue: 0.97)
    }

    private var titleWithSettingsControl: some View {
        HStack(spacing: 10) {
            Text("PushTester")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(brandTitleColor)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("설정")
            .accessibilityLabel("설정")
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            Picker("Platform", selection: $platform) {
                ForEach(PushPlatform.allCases) { item in
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(maxWidth: 520, minHeight: 40)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch platform {
                case .ios:
                    iosDetailContent
                case .android:
                    AndroidPushView(viewModel: androidViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func enforceWindowMinWidth() {
        DispatchQueue.main.async {
            WindowMinWidthEnforcer.apply(minWidth: effectiveWindowMinWidth, animated: true)
        }
    }

    private func handleSettingsAction(_ itemID: AppSettingsItemID) {
        switch itemID {
        case .resetAllData:
            AppDataReset.resetPersistedStores(
                history: historyStore,
                savedConfigs: savedConfigStore,
                fieldPresets: fieldPresetStore,
                certificates: certificatePresetStore
            )
            viewModel.resetToDefaults()
            androidViewModel.resetToDefaults()
            selectedHistoryID = nil
            selectedSavedConfigID = nil
        }
    }

    private func applyHistoryItem(_ item: PushHistoryItem) {
        switch item.pushPlatform {
        case .ios:
            platform = .ios
            viewModel.applyHistory(item)
        case .android:
            platform = .android
            androidViewModel.applyHistory(item)
        }
    }

    private func applySavedConfigItem(_ item: PushHistoryItem) {
        switch item.pushPlatform {
        case .ios:
            platform = .ios
            viewModel.applySavedConfig(item)
        case .android:
            platform = .android
            androidViewModel.applySavedConfig(item)
        }
    }

    private var iosDetailContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        PresetLabeledTextField(
                            title: "Bundle ID",
                            fieldKey: .bundleID,
                            text: $viewModel.bundleID,
                            labelWidth: labelWidth
                        )

                        PresetLabeledTextField(
                            title: "Team ID",
                            fieldKey: .teamID,
                            text: $viewModel.teamID,
                            labelWidth: labelWidth
                        )

                        PresetLabeledTextField(
                            title: "Key ID",
                            fieldKey: .keyID,
                            text: $viewModel.keyID,
                            labelWidth: labelWidth
                        )

                        CertificatePresetField(
                            title: "인증서",
                            kind: .apnsP8,
                            fileName: $viewModel.p8FileName,
                            labelWidth: labelWidth
                        ) { item in
                            viewModel.applyP8Certificate(item)
                        }

                        PresetLabeledTextField(
                            title: "Device Token",
                            fieldKey: .deviceToken,
                            text: $viewModel.deviceToken,
                            labelWidth: labelWidth,
                            monospace: true
                        )

                        LabeledContent {
                            Picker("", selection: $viewModel.environment) {
                                ForEach(APNsEnvironment.allCases) { env in
                                    Text(env.rawValue).tag(env)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 260, alignment: .leading)
                        } label: {
                            formLabel("APN Server")
                        }

                        LabeledContent {
                            Picker("", selection: $viewModel.priority) {
                                ForEach(APNsPriority.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .horizontalRadioGroupLayout()
                            .labelsHidden()
                        } label: {
                            formLabel("APNs Priority")
                        }

                        LabeledContent {
                            HStack(spacing: 10) {
                                Picker("", selection: $viewModel.pushType) {
                                    ForEach(APNsPushType.allCases) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 180)
                                .onChange(of: viewModel.pushType) { _, newValue in
                                    viewModel.pushTypeChanged(to: newValue)
                                }

                                Button("Load Template") {
                                    viewModel.loadTemplate()
                                }
                                .help("선택한 Push Type에 맞는 예시 Payload로 다시 채웁니다.")
                            }
                        } label: {
                            formLabel("Push Type")
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Payload")
                                .font(.headline)
                            Spacer()

                            Button {
                                viewModel.sendPush(recordingInto: historyStore)
                            } label: {
                                Label(
                                    viewModel.isSending ? "Sending..." : "Push Notification",
                                    systemImage: "paperplane.circle.fill"
                                )
                            }
                            .pushNotificationButtonStyle()
                            .disabled(!viewModel.canSend)
                            .keyboardShortcut(.return, modifiers: .command)
                        }

                        TextEditor(text: $viewModel.payload)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 260, idealHeight: 280)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: statusIconName)
                    .foregroundStyle(statusColor)
                Text(viewModel.statusMessage)
                    .font(.system(.callout, design: .default))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("파일로 저장")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("불러오기") {
                    viewModel.loadSessionFromFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("저장") {
                    showIOSSaveSheet = true
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showIOSSaveSheet) {
            SessionSaveSheet(
                title: "설정 저장",
                defaultFileName: "PushTester-session.json"
            ) { url in
                viewModel.exportSession(to: url)
            }
        }
    }

    private func formLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: labelWidth, alignment: .trailing)
    }

    private var statusIconName: String {
        let message = viewModel.statusMessage.lowercased()
        if viewModel.isSending {
            return "arrow.triangle.2.circlepath"
        }
        if message.hasPrefix("success") || message.hasPrefix("saved") || message.hasPrefix("loaded") || message.hasPrefix("restored") || message.hasPrefix("key imported") {
            return "checkmark.circle.fill"
        }
        if message == "ready" {
            return "info.circle"
        }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        let message = viewModel.statusMessage.lowercased()
        if viewModel.isSending {
            return .secondary
        }
        if message.hasPrefix("success") || message.hasPrefix("saved") || message.hasPrefix("loaded") || message.hasPrefix("restored") || message.hasPrefix("key imported") {
            return .green
        }
        if message == "ready" {
            return .secondary
        }
        return .orange
    }
}

extension View {
    /// 앱/윈도우 포커스에 따라 노란색 농도를 조절하는 푸시 버튼 스타일
    func pushNotificationButtonStyle() -> some View {
        modifier(PushNotificationButtonStyleModifier())
    }
}

private struct PushNotificationButtonStyleModifier: ViewModifier {
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isAppActive = NSApp.isActive

    private var isActive: Bool {
        isAppActive && controlActiveState != .inactive
    }

    func body(content: Content) -> some View {
        content
            .buttonStyle(PushNotificationButtonStyle(isActive: isActive))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isAppActive = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                isAppActive = false
            }
    }
}

/// 활성: 선명한 노랑 / 비활성: 노란 계열을 유지한 채 한 단계 어두운 톤
struct PushNotificationButtonStyle: ButtonStyle {
    var isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor(isPressed: configuration.isPressed))
            )
            .foregroundStyle(Color.black.opacity(labelOpacity))
    }

    private var labelOpacity: Double {
        if !isEnabled { return 0.45 }
        return isActive ? 1 : 0.75
    }

    private func fillColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return inactiveYellow.opacity(0.55)
        }
        if isPressed {
            return inactiveYellow
        }
        return isActive ? Color.yellow : inactiveYellow
    }

    /// 검정 계열이 아니라, 확실히 구분되는 어두운 노란색
    private var inactiveYellow: Color {
        Color(red: 0.62, green: 0.48, blue: 0.0)
    }
}

#Preview {
    ContentView()
        .environmentObject(HistoryStore())
        .environmentObject(SavedConfigStore())
        .environmentObject(FieldPresetStore())
        .environmentObject(CertificatePresetStore())
        .frame(width: 1280, height: 940)
}
