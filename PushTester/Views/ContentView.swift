import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

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

    func importP8Key() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "p8") ?? .data,
            .plainText
        ]
        panel.message = "APNs Auth Key (.p8) 파일을 선택하세요"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let contents = try readP8File(from: url)
            guard contents.localizedCaseInsensitiveContains("BEGIN"),
                  contents.localizedCaseInsensitiveContains("PRIVATE KEY") else {
                statusMessage = "선택한 파일이 유효한 .p8 키가 아닙니다."
                return
            }
            // 파싱 가능한지 검증하고, CryptoKit 표준 PEM으로 정규화해 저장합니다.
            let privateKey = try APNsJWT.loadPrivateKey(from: contents)
            p8PEM = privateKey.pemRepresentation
            p8FileName = url.lastPathComponent
            statusMessage = "Key imported: \(url.lastPathComponent)"
            persistLastSession()
        } catch {
            statusMessage = "키 파일을 읽지 못했습니다: \(error.localizedDescription)"
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

    func saveSessionToFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "설정 저장"
        panel.nameFieldStringValue = "PushTester-session.json"
        panel.allowedContentTypes = [.json]
        panel.message = "현재 입력값을 JSON 파일로 저장합니다."

        guard panel.runModal() == .OK, let url = panel.url else { return }

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
        panel.message = "저장된 PushTester 설정 JSON을 선택하세요"
        panel.prompt = "불러오기"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let session = try SessionStore.import(from: url)
            apply(session)
            persistLastSession()
            statusMessage = "Loaded: \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
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

    private func readP8File(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        if let utf16 = try? String(contentsOf: url, encoding: .utf16) {
            return utf16
        }
        let data = try Data(contentsOf: url)
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        throw APNsJWTError.invalidP8Key
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
    @State private var selectedHistoryID: PushHistoryItem.ID?
    @State private var platform: PushPlatform = .ios

    private let labelWidth: CGFloat = 110

    var body: some View {
        NavigationSplitView {
            HistorySidebar(
                platform: platform,
                selection: $selectedHistoryID
            ) { item in
                switch item.pushPlatform {
                case .ios:
                    platform = .ios
                    viewModel.applyHistory(item)
                case .android:
                    platform = .android
                    androidViewModel.applyHistory(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        } detail: {
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
                .frame(width: 520, height: 40)
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
            }
        }
        .onChange(of: platform) { _, _ in
            selectedHistoryID = nil
        }
    }

    private var iosDetailContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Form {
                        LabeledContent {
                            TextField("", text: $viewModel.bundleID)
                                .textFieldStyle(.roundedBorder)
                        } label: {
                            formLabel("Bundle ID")
                        }

                        LabeledContent {
                            TextField("", text: $viewModel.teamID)
                                .textFieldStyle(.roundedBorder)
                        } label: {
                            formLabel("Team ID")
                        }

                        LabeledContent {
                            HStack(spacing: 10) {
                                TextField("", text: $viewModel.keyID)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } label: {
                            formLabel("Key ID")
                        }

                        LabeledContent {
                            Button {
                                viewModel.importP8Key()
                            } label: {
                                Label("Import Key (*.p8)", systemImage: "plus.circle.fill")
                            }
                            .tint(.green)

                            Text(viewModel.p8FileName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

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
                    .font(.system(.callout, design: .default))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("불러오기") {
                    viewModel.loadSessionFromFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("저장") {
                    viewModel.saveSessionToFile()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

#Preview {
    ContentView()
        .environmentObject(HistoryStore())
        .frame(width: 1100, height: 940)
}
