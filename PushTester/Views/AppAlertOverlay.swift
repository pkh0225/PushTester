import SwiftUI
import AppKit
import Combine

/// 메인 창 가운데 확인/알림 오버레이용 상태
@MainActor
final class AppAlertCenter: ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let cancelTitle: String
        let confirmTitle: String
        let isDestructive: Bool
        /// false면 확인 버튼만 표시 (단순 알림)
        let showsCancel: Bool
        let onConfirm: () -> Void
        let onCancel: () -> Void
    }

    @Published var request: Request?

    func confirm(
        title: String,
        message: String,
        cancelTitle: String = "취소",
        confirmTitle: String = "삭제",
        isDestructive: Bool = true,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void
    ) {
        request = Request(
            title: title,
            message: message,
            cancelTitle: cancelTitle,
            confirmTitle: confirmTitle,
            isDestructive: isDestructive,
            showsCancel: true,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    func notice(
        title: String,
        message: String,
        buttonTitle: String = "확인",
        onDismiss: @escaping () -> Void = {}
    ) {
        request = Request(
            title: title,
            message: message,
            cancelTitle: buttonTitle,
            confirmTitle: buttonTitle,
            isDestructive: false,
            showsCancel: false,
            onConfirm: onDismiss,
            onCancel: onDismiss
        )
    }

    func dismiss() {
        request = nil
    }
}

private struct AppAlertPanel: View {
    let request: AppAlertCenter.Request
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title)
                .font(.headline)

            Text(request.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                if request.showsCancel {
                    Button(request.cancelTitle, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                Button(request.confirmTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(request.isDestructive ? .red : Color.accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

private struct AppAlertOverlayContent: View {
    @ObservedObject var alertCenter: AppAlertCenter

    var body: some View {
        Group {
            if let request = alertCenter.request {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            request.onCancel()
                            alertCenter.dismiss()
                        }

                    AppAlertPanel(
                        request: request,
                        onConfirm: {
                            request.onConfirm()
                            alertCenter.dismiss()
                        },
                        onCancel: {
                            request.onCancel()
                            alertCenter.dismiss()
                        }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: alertCenter.request?.id)
    }
}

extension View {
    /// `AppAlertCenter`를 직접 넘겨 environmentObject 누락 크래시를 방지합니다.
    func appAlertOverlay(using alertCenter: AppAlertCenter) -> some View {
        overlay {
            AppAlertOverlayContent(alertCenter: alertCenter)
                .zIndex(3000)
        }
    }
}
