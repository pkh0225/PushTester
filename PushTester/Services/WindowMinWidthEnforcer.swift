import SwiftUI
import AppKit

/// 펼쳐진 패널 합에 맞춰 NSWindow.minSize / contentMinSize를 강제합니다.
/// SwiftUI `.frame(minWidth:)` 만으로는 macOS에서 창 축소가 막히지 않는 경우가 많습니다.
struct WindowMinWidthEnforcer: NSViewRepresentable {
    let minWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.minWidth = minWidth
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.minWidth = minWidth
        context.coordinator.attach(to: nsView)
        context.coordinator.apply(animated: false)
    }

    static func apply(minWidth: CGFloat, animated: Bool, anchor: NSView? = nil) {
        let window = anchor?.window
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.styleMask.contains(.titled) })
        guard let window else { return }
        Coordinator.apply(minWidth: minWidth, to: window, animated: animated)
    }

    final class Coordinator {
        var minWidth: CGFloat = MainLayoutMetrics.windowMinWidthCollapsed
        private weak var view: NSView?
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        deinit {
            detach()
        }

        func attach(to view: NSView) {
            self.view = view
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.view?.window else { return }
                self.observe(window)
                self.apply(animated: false)
            }
        }

        func apply(animated: Bool) {
            guard let window = view?.window ?? observedWindow else { return }
            Self.apply(minWidth: minWidth, to: window, animated: animated)
        }

        static func apply(minWidth: CGFloat, to window: NSWindow, animated: Bool) {
            let target = max(minWidth, MainLayoutMetrics.windowMinWidthCollapsed)
            let minHeight = MainLayoutMetrics.windowMinHeight

            var nextMin = window.minSize
            nextMin.width = target
            nextMin.height = max(nextMin.height, minHeight)
            if window.minSize != nextMin {
                window.minSize = nextMin
            }

            var nextContentMin = window.contentMinSize
            nextContentMin.width = target
            nextContentMin.height = max(nextContentMin.height, minHeight - 28)
            if window.contentMinSize != nextContentMin {
                window.contentMinSize = nextContentMin
            }

            var frame = window.frame
            guard frame.width + 0.5 < target else { return }
            let grow = target - frame.width
            frame.size.width = target
            frame.origin.x -= grow / 2
            window.setFrame(frame, display: true, animate: animated)
        }

        private func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            detach()
            observedWindow = window

            let center = NotificationCenter.default
            let resize = center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.apply(animated: false)
            }
            let move = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.apply(animated: false)
            }
            observers = [resize, move]
        }

        private func detach() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            observedWindow = nil
        }
    }
}
