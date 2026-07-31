import SwiftUI
import AppKit

/// JSON Payload용 텍스트 에디터.
/// macOS 스마트 따옴표(`"` → `“”`) 치환을 끄고, 한글 IME 입력도 깨지지 않게 합니다.
struct PayloadTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.focusRingType = .none

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.enabledTextCheckingTypes = 0

        guard textView.string != text else { return }

        let selectedRanges = textView.selectedRanges
        textView.string = text
        if selectedRanges.allSatisfy({ range in
            let nsRange = range.rangeValue
            return NSMaxRange(nsRange) <= (text as NSString).length
        }) {
            textView.selectedRanges = selectedRanges
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Payload 에디터 우상단 JSON 유효성 배지
struct PayloadJSONStatusBadge: View {
    let payload: String

    private var check: PayloadJSONValidator.CheckResult {
        PayloadJSONValidator.check(payload)
    }

    var body: some View {
        Text(check.isValid ? "JSON 유효" : "JSON 오류")
            .font(.caption.weight(.semibold))
            .foregroundStyle(check.isValid ? Color.green : Color.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.92),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
            )
            .help(check.message)
            .lineLimit(1)
            .allowsHitTesting(false)
    }
}

extension View {
    /// 테두리 + 우상단 JSON 상태 오버레이
    func payloadEditorChrome(payload: String, cornerRadius: CGFloat = 8) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            PayloadJSONStatusBadge(payload: payload)
                .padding(8)
        }
    }
}
