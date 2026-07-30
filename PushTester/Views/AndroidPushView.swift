import SwiftUI
import AppKit
import Combine

@MainActor
final class AndroidPushViewModel: ObservableObject {
    @Published var projectID: String = ""
    @Published var deviceToken: String = ""
    @Published var priority: FCMPriority = .high
    @Published var payload: String = AndroidPayloadTemplates.notification
    @Published var statusMessage: String = "Ready"
    @Published var isSending = false
    @Published var serviceAccountFileName: String = "No JSON imported"

    private var serviceAccountJSON: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var isRestoring = false

    var canSend: Bool { !isSending }

    init() {
        restoreLastSession()
        observeChangesForAutosave()
    }

    func applyServiceAccount(_ item: CertificatePresetItem) {
        do {
            let account = try GoogleServiceAccount.parse(from: item.content)
            serviceAccountJSON = item.content
            serviceAccountFileName = item.name
            if projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectID = account.projectID
            }
            statusMessage = "Service account imported: \(item.name)"
            persistLastSession()
        } catch {
            statusMessage = "서비스 계정을 적용하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func loadTemplate() {
        guard !isRestoring else { return }
        payload = AndroidPayloadTemplates.notification
        statusMessage = "Loaded Android notification template"
    }

    func sendPush(recordingInto historyStore: HistoryStore) {
        guard canSend else { return }

        let normalizedPayload = JSONTextNormalizer.normalizeQuotes(payload)
        if normalizedPayload != payload {
            payload = normalizedPayload
        }

        let sessionSnapshot = currentSession()
        let request = FCMSendRequest(
            projectID: projectID,
            deviceToken: deviceToken,
            priority: priority,
            serviceAccountJSON: serviceAccountJSON,
            payload: payload
        )

        isSending = true
        statusMessage = "Sending..."
        persistLastSession()

        Task {
            do {
                let result = try await FCMClient.send(request)
                historyStore.addAndroidSuccess(
                    session: sessionSnapshot,
                    messageName: result.messageName,
                    statusCode: result.statusCode
                )
                if let name = result.messageName, !name.isEmpty {
                    statusMessage = "Success (HTTP \(result.statusCode)) · \(name)"
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
        apply(item.androidSession)
        statusMessage = "히스토리 적용: \(item.title)"
        persistLastSession()
    }

    func makeSavedConfig(title: String) -> PushHistoryItem {
        PushHistoryItem.makeAndroidSaved(from: currentSession(), title: title)
    }

    func applySavedConfig(_ item: PushHistoryItem) {
        applyHistory(item)
        statusMessage = "저장 설정 적용: \(item.title)"
    }

    func exportSession(to url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            try AndroidSessionStore.export(currentSession(), to: url)
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
        panel.title = "Android 설정 불러오기"
        panel.prompt = "불러오기"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                do {
                    let session = try AndroidSessionStore.import(from: url)
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
        guard let session = AndroidSessionStore.loadLastSession() else { return }
        apply(session)
        statusMessage = "Restored last Android session"
    }

    private func observeChangesForAutosave() {
        let publishers: [AnyPublisher<Void, Never>] = [
            $projectID.map { _ in () }.eraseToAnyPublisher(),
            $deviceToken.map { _ in () }.eraseToAnyPublisher(),
            $priority.map { _ in () }.eraseToAnyPublisher(),
            $payload.map { _ in () }.eraseToAnyPublisher(),
            $serviceAccountFileName.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistLastSession() }
            .store(in: &cancellables)
    }

    private func persistLastSession() {
        guard !isRestoring else { return }
        try? AndroidSessionStore.saveLastSession(currentSession())
    }

    private func currentSession() -> AndroidSession {
        AndroidSession(
            projectID: projectID,
            deviceToken: deviceToken,
            priority: priority.rawValue,
            payload: payload,
            serviceAccountFileName: serviceAccountFileName,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    func resetToDefaults() {
        apply(AndroidSession.empty)
        statusMessage = "Ready"
        AndroidSessionStore.clearLastSession()
    }

    private func apply(_ session: AndroidSession) {
        isRestoring = true
        projectID = session.projectID
        deviceToken = session.deviceToken
        priority = FCMPriority(rawValue: session.priority) ?? .high
        let rawPayload = session.payload.isEmpty
            ? AndroidPayloadTemplates.notification
            : session.payload
        payload = JSONTextNormalizer.normalizeQuotes(rawPayload)
        serviceAccountFileName = session.serviceAccountFileName.isEmpty
            ? "No JSON imported"
            : session.serviceAccountFileName
        serviceAccountJSON = session.serviceAccountJSON
        DispatchQueue.main.async { [weak self] in
            self?.isRestoring = false
        }
    }
}

struct AndroidPushView: View {
    @ObservedObject var viewModel: AndroidPushViewModel
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var showSaveSheet = false

    private let labelWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        PresetLabeledTextField(
                            title: "Project ID",
                            fieldKey: .projectID,
                            text: $viewModel.projectID,
                            labelWidth: labelWidth
                        )

                        CertificatePresetField(
                            title: "인증서",
                            kind: .fcmServiceAccount,
                            fileName: $viewModel.serviceAccountFileName,
                            labelWidth: labelWidth
                        ) { item in
                            viewModel.applyServiceAccount(item)
                        }

                        PresetLabeledTextField(
                            title: "Device Token",
                            fieldKey: .deviceToken,
                            text: $viewModel.deviceToken,
                            labelWidth: labelWidth,
                            monospace: true
                        )

                        LabeledContent {
                            Picker("", selection: $viewModel.priority) {
                                ForEach(FCMPriority.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .leading)
                        } label: {
                            formLabel("Priority")
                        }

                        LabeledContent {
                            Button("Load Template") {
                                viewModel.loadTemplate()
                            }
                        } label: {
                            formLabel("Template")
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Payload")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            PayloadKeyControls(payload: $viewModel.payload) { message in
                                viewModel.statusMessage = message
                            }

                            HStack {
                                Spacer(minLength: 0)
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
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        PayloadTextEditor(text: $viewModel.payload)
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
                    .font(.system(.callout))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("파일로 저장")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("불러오기") { viewModel.loadSessionFromFile() }
                Button("저장") { showSaveSheet = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSaveSheet) {
            SessionSaveSheet(
                title: "Android 설정 저장",
                defaultFileName: "PushTester-android-session.json"
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
        if viewModel.isSending { return "arrow.triangle.2.circlepath" }
        if message.hasPrefix("success") || message.hasPrefix("saved") || message.hasPrefix("loaded")
            || message.hasPrefix("restored") || message.hasPrefix("service account")
            || message.hasPrefix("히스토리") {
            return "checkmark.circle.fill"
        }
        if message == "ready" { return "info.circle" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        let message = viewModel.statusMessage.lowercased()
        if viewModel.isSending { return .secondary }
        if message.hasPrefix("success") || message.hasPrefix("saved") || message.hasPrefix("loaded")
            || message.hasPrefix("restored") || message.hasPrefix("service account")
            || message.hasPrefix("히스토리") {
            return .green
        }
        if message == "ready" { return .secondary }
        return .orange
    }
}
