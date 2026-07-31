import SwiftUI

/// Push 버튼 + 프리셋 토큰 일괄 전송 메뉴
struct PushSendControls: View {
    var isSending: Bool
    var canSend: Bool
    var presetTokens: [String]
    var onSendCurrent: () -> Void
    var onSendPresets: ([String]) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSendCurrent) {
                Label(
                    isSending ? "Sending..." : "Push Notification",
                    systemImage: "paperplane.circle.fill"
                )
            }
            .pushNotificationButtonStyle()
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)

            Menu {
                Button("현재 Device Token으로 전송") {
                    onSendCurrent()
                }
                .disabled(!canSend)

                Divider()

                if presetTokens.isEmpty {
                    Text("저장된 Device Token 프리셋 없음")
                } else {
                    ForEach(presetTokens, id: \.self) { token in
                        Button(truncatedTokenLabel(token)) {
                            onSendPresets([token])
                        }
                        .disabled(!canSend)
                    }

                    Divider()

                    Button("프리셋 토큰 전체 전송 (\(presetTokens.count))") {
                        onSendPresets(presetTokens)
                    }
                    .disabled(!canSend)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(!canSend)
            .help("현재 토큰 또는 저장된 Device Token 프리셋으로 전송")
        }
    }

    private func truncatedTokenLabel(_ token: String) -> String {
        if token.count <= 24 { return token }
        let prefix = token.prefix(10)
        let suffix = token.suffix(8)
        return "\(prefix)…\(suffix)"
    }
}
