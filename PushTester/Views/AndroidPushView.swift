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

    func sendPush(recordingInto historyStore: HistoryStore, tokens: [String]? = nil) {
        guard canSend else { return }

        let normalizedPayload = JSONTextNormalizer.normalizeQuotes(payload)
        if normalizedPayload != payload {
            payload = normalizedPayload
        }

        let jsonCheck = PayloadJSONValidator.check(payload)
        guard jsonCheck.isValid else {
            statusMessage = "Payload JSON 오류: \(jsonCheck.message)"
            return
        }

        let targetTokens = Self.normalizedTokens(tokens ?? [deviceToken])
        guard !targetTokens.isEmpty else {
            statusMessage = "Device Token이 비어 있습니다."
            return
        }

        isSending = true
        statusMessage = targetTokens.count == 1 ? "Sending..." : "Sending \(targetTokens.count) tokens..."
        persistLastSession()

        Task {
            var successCount = 0
            var lastSuccessMessage = ""
            var failures: [String] = []

            for token in targetTokens {
                var sessionSnapshot = currentSession()
                sessionSnapshot.deviceToken = token
                let request = FCMSendRequest(
                    projectID: projectID,
                    deviceToken: token,
                    priority: priority,
                    serviceAccountJSON: serviceAccountJSON,
                    payload: payload
                )

                do {
                    let result = try await FCMClient.send(request)
                    historyStore.addAndroidSuccess(
                        session: sessionSnapshot,
                        messageName: result.messageName,
                        statusCode: result.statusCode,
                        responseHeaders: result.headersText,
                        responseBody: HTTPResponseFormatting.prettyBody(result.body)
                    )
                    if result.succeeded {
                        successCount += 1
                        if let name = result.messageName, !name.isEmpty {
                            lastSuccessMessage = "Success (HTTP \(result.statusCode)) · \(name)"
                        } else {
                            lastSuccessMessage = "Success (HTTP \(result.statusCode))"
                        }
                    } else {
                        let short = token.count > 12 ? "\(token.prefix(8))…" : token
                        failures.append("\(short): \(result.errorMessage ?? "HTTP \(result.statusCode)")")
                    }
                } catch {
                    let short = token.count > 12 ? "\(token.prefix(8))…" : token
                    failures.append("\(short): \(error.localizedDescription)")
                }
            }

            if targetTokens.count == 1 {
                statusMessage = failures.first ?? lastSuccessMessage
            } else if failures.isEmpty {
                statusMessage = "Success \(successCount)/\(targetTokens.count) tokens"
            } else {
                statusMessage = "Success \(successCount)/\(targetTokens.count) · 실패 \(failures.count) · \(failures[0])"
            }
            isSending = false
        }
    }

    private static func normalizedTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
        }
        return result
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

    func makeExportData() throws -> Data {
        try AndroidSessionStore.encode(currentSession())
    }

    func markExported(to url: URL) {
        persistLastSession()
        statusMessage = "Saved: \(url.lastPathComponent)"
    }

    func importSession(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let session = try AndroidSessionStore.import(from: url)
            apply(session)
            persistLastSession()
            statusMessage = "Loaded: \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
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
    @EnvironmentObject private var fieldPresetStore: FieldPresetStore
    var onRequestFileSave: () -> Void
    var onRequestFileLoad: () -> Void

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
                        HStack(alignment: .center, spacing: 12) {
                            Text("Payload")
                                .font(.headline)
                            Spacer(minLength: 0)
                            PushSendControls(
                                isSending: viewModel.isSending,
                                canSend: viewModel.canSend,
                                presetTokens: fieldPresetStore.values(for: .deviceToken),
                                onSendCurrent: {
                                    viewModel.sendPush(recordingInto: historyStore)
                                },
                                onSendPresets: { tokens in
                                    viewModel.sendPush(recordingInto: historyStore, tokens: tokens)
                                }
                            )
                        }

                        HStack(alignment: .center, spacing: 12) {
                            PayloadTemplateControls(
                                platform: .android,
                                payload: $viewModel.payload
                            ) { message in
                                viewModel.statusMessage = message
                            }

                            PayloadKeyControls(payload: $viewModel.payload) { message in
                                viewModel.statusMessage = message
                            }

                            Spacer(minLength: 0)
                        }

                        PayloadTextEditor(text: $viewModel.payload)
                            .frame(minHeight: 260, idealHeight: 280)
                            .frame(maxWidth: .infinity)
                            .payloadEditorChrome(payload: viewModel.payload)
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

                Button("불러오기", action: onRequestFileLoad)
                Button("저장", action: onRequestFileSave)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
