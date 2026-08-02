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
        /// nil이면 체크박스 숨김
        let checkboxTitle: String?
        let onConfirm: () -> Void
        let onCancel: () -> Void
        /// 체크박스가 있을 때 닫기 직전에 체크 여부를 전달합니다.
        let onCheckboxResult: ((Bool) -> Void)?
    }

    @Published var request: Request?

    func confirm(
        title: String,
        message: String,
        cancelTitle: String = "취소",
        confirmTitle: String = "삭제",
        isDestructive: Bool = true,
        checkboxTitle: String? = nil,
        onCancel: @escaping () -> Void = {},
        onCheckboxResult: ((Bool) -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) {
        request = Request(
            title: title,
            message: message,
            cancelTitle: cancelTitle,
            confirmTitle: confirmTitle,
            isDestructive: isDestructive,
            showsCancel: true,
            checkboxTitle: checkboxTitle,
            onConfirm: onConfirm,
            onCancel: onCancel,
            onCheckboxResult: onCheckboxResult
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
            checkboxTitle: nil,
            onConfirm: onDismiss,
            onCancel: onDismiss,
            onCheckboxResult: nil
        )
    }

    func dismiss() {
        request = nil
    }
}

private struct AppAlertPanel: View {
    let request: AppAlertCenter.Request
    let onConfirm: (_ checkboxChecked: Bool) -> Void
    let onCancel: (_ checkboxChecked: Bool) -> Void

    @State private var checkboxChecked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title)
                .font(.headline)

            Text(request.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let checkboxTitle = request.checkboxTitle {
                Toggle(isOn: $checkboxChecked) {
                    Text(checkboxTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer(minLength: 0)
                if request.showsCancel {
                    Button(request.cancelTitle) {
                        onCancel(checkboxChecked)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(request.confirmTitle) {
                    onConfirm(checkboxChecked)
                }
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
                            // 배경 탭은 체크박스 미적용 취소로 처리
                            request.onCancel()
                            alertCenter.dismiss()
                        }

                    AppAlertPanel(
                        request: request,
                        onConfirm: { checked in
                            if request.checkboxTitle != nil {
                                request.onCheckboxResult?(checked)
                            }
                            request.onConfirm()
                            alertCenter.dismiss()
                        },
                        onCancel: { checked in
                            if request.checkboxTitle != nil {
                                request.onCheckboxResult?(checked)
                            }
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
