import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

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

    func importServiceAccount() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Firebase 서비스 계정 JSON 파일을 선택하세요"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let account = try GoogleServiceAccount.parse(from: contents)
            serviceAccountJSON = contents
            serviceAccountFileName = url.lastPathComponent
            if projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectID = account.projectID
            }
            statusMessage = "Service account imported: \(url.lastPathComponent)"
            persistLastSession()
        } catch {
            statusMessage = "서비스 계정을 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    func loadTemplate() {
        guard !isRestoring else { return }
        payload = AndroidPayloadTemplates.notification
        statusMessage = "Loaded Android notification template"
    }

    func sendPush(recordingInto historyStore: HistoryStore) {
        guard canSend else { return }

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

    func saveSessionToFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PushTester-android-session.json"
        panel.message = "현재 Android 설정을 JSON 파일로 저장합니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }

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
        panel.allowedContentTypes = [.json]
        panel.message = "저장된 Android 설정 JSON을 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }

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

    private func apply(_ session: AndroidSession) {
        isRestoring = true
        projectID = session.projectID
        deviceToken = session.deviceToken
        priority = FCMPriority(rawValue: session.priority) ?? .high
        payload = session.payload.isEmpty ? AndroidPayloadTemplates.notification : session.payload
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

    private let labelWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        LabeledContent {
                            TextField("", text: $viewModel.projectID)
                                .textFieldStyle(.roundedBorder)
                        } label: {
                            formLabel("Project ID")
                        }

                        LabeledContent {
                            HStack(spacing: 8) {
                                Button {
                                    viewModel.importServiceAccount()
                                } label: {
                                    Label("Import JSON", systemImage: "plus.circle.fill")
                                }
                                .tint(.green)
                                .fixedSize()

                                Text(viewModel.serviceAccountFileName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } label: {
                            formLabel("인증서")
                        }

                        LabeledContent {
                            TextField("", text: $viewModel.deviceToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } label: {
                            formLabel("Device Token")
                        }

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
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .foregroundStyle(.black)
                            .disabled(!viewModel.canSend)
                            .keyboardShortcut(.return, modifiers: .command)
                        }

                        TextEditor(text: $viewModel.payload)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 260, idealHeight: 280)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: statusIconName)
                    .foregroundStyle(statusColor)
                Text(viewModel.statusMessage)
                    .font(.system(.callout))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("불러오기") { viewModel.loadSessionFromFile() }
                Button("저장") { viewModel.saveSessionToFile() }
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
