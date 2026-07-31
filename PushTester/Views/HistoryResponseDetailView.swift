import SwiftUI
import AppKit

/// 히스토리에 저장된 APNs/FCM 응답 헤더·바디 상세 보기 (가운데 오버레이)
struct HistoryResponseDetailView: View {
    let item: PushHistoryItem
    var onClose: () -> Void

    private var headersText: String {
        let text = item.responseHeaders?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "(헤더 없음)" : text
    }

    private var hasEmptyBody: Bool {
        (item.responseBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private var bodyText: String {
        guard !hasEmptyBody else {
            if item.pushPlatform == .ios, let code = item.statusCode, (200..<300).contains(code) {
                return "(비어 있음 — APNs 성공 응답은 바디 없이 헤더만 오는 경우가 많습니다)"
            }
            return "(비어 있음)"
        }
        return item.responseBody ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("응답 상세")
                    .font(.headline)
                Spacer()
                Button("전체 복사") {
                    copyToPasteboard(fullText)
                }
                .controlSize(.small)
                Button("닫기") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("요약") {
                    LabeledContent("플랫폼", value: item.pushPlatform.title)
                    if let code = item.statusCodeDisplay {
                        LabeledContent("상태", value: code)
                    }
                    if let apnsID = item.apnsID, !apnsID.isEmpty {
                        LabeledContent(item.pushPlatform == .android ? "Message" : "apns-id") {
                            Text(apnsID)
                                .textSelection(.enabled)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("토큰")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.deviceToken)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section {
                    Text(headersText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("응답 헤더")
                        Spacer()
                        Button("복사") {
                            copyToPasteboard(headersText)
                        }
                        .controlSize(.small)
                    }
                }

                Section {
                    Text(bodyText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                } header: {
                    HStack {
                        Text("응답 바디")
                        Spacer()
                        Button("복사") {
                            copyToPasteboard(bodyText)
                        }
                        .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
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

    private static let panelSize = CGSize(width: 560, height: 520)

    private var fullText: String {
        var lines: [String] = []
        if let code = item.statusCodeDisplay {
            lines.append(code)
        }
        if let apnsID = item.apnsID, !apnsID.isEmpty {
            lines.append("id: \(apnsID)")
        }
        lines.append("")
        lines.append("[Headers]")
        lines.append(headersText)
        lines.append("")
        lines.append("[Body]")
        lines.append(bodyText)
        return lines.joined(separator: "\n")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 메인 창 가운데에 응답 상세를 띄우는 딤드 오버레이
struct HistoryResponseDetailOverlay: ViewModifier {
    @Binding var item: PushHistoryItem?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                self.item = nil
                            }

                        HistoryResponseDetailView(item: item) {
                            self.item = nil
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: item?.id)
    }
}

extension View {
    func historyResponseDetailOverlay(item: Binding<PushHistoryItem?>) -> some View {
        modifier(HistoryResponseDetailOverlay(item: item))
    }
}
