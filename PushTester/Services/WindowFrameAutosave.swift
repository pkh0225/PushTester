import SwiftUI
import AppKit

enum WindowFrameStore {
    static let mainWindowName = "PushTesterMainWindow"

    static func defaultsKey(for name: String) -> String {
        "PushTester.windowFrame.\(name)"
    }

    static func load(name: String = mainWindowName) -> NSRect? {
        guard let saved = UserDefaults.standard.string(forKey: defaultsKey(for: name)), !saved.isEmpty else {
            return nil
        }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return constrainToVisibleScreens(frame)
    }

    static func save(_ frame: NSRect, name: String = mainWindowName) {
        guard frame.width >= 560, frame.height >= 480 else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: defaultsKey(for: name))
    }

    static func constrainToVisibleScreens(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }

        let intersectsAny = screens.contains { $0.visibleFrame.intersects(frame) }
        if intersectsAny {
            var result = frame
            if let screen = screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? screens.first {
                let visible = screen.visibleFrame
                if result.maxX < visible.minX + 80 {
                    result.origin.x = visible.minX + 40
                }
                if result.minX > visible.maxX - 80 {
                    result.origin.x = visible.maxX - result.width - 40
                }
                if result.maxY < visible.minY + 40 {
                    result.origin.y = visible.minY + 20
                }
                if result.minY > visible.maxY - 40 {
                    result.origin.y = visible.maxY - 60
                }
            }
            return result
        }

        let target = NSScreen.main?.visibleFrame ?? screens[0].visibleFrame
        var centered = frame
        centered.origin.x = target.midX - frame.width / 2
        centered.origin.y = target.midY - frame.height / 2
        return centered
    }

    /// 창이 보이기 직전/직후에 호출해, 잘못된 위치에 깜빡이지 않게 합니다.
    static func applyLaunchFrame(to window: NSWindow, name: String = mainWindowName) {
        window.isRestorable = false
        window.setFrameAutosaveName("")

        guard let frame = load(name: name) else { return }

        // 복원이 끝날 때까지 투명하게 유지 → 오른쪽에서 열렸다가 이동하는 깜빡임 방지
        window.alphaValue = 0
        window.setFrame(frame, display: false)

        DispatchQueue.main.async {
            window.setFrame(frame, display: false)
            // SwiftUI가 default 배치를 한 번 더 덮어쓰는 타이밍을 지난 뒤 표시
            DispatchQueue.main.async {
                window.setFrame(frame, display: true)
                window.alphaValue = 1
            }
        }
    }
}

/// 창 이동/리사이즈/종료 시 프레임을 저장합니다. (복원은 AppDelegate에서 처리)
struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeCoordinator() -> Coordinator {
        Coordinator(name: name)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        private let name: String
        private var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(name: String) {
            self.name = name
        }

        deinit {
            detachObservers()
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                self.configure(window)
            }
        }

        private func configure(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            detachObservers()
            observedWindow = window
            window.isRestorable = false
            window.setFrameAutosaveName("")

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.save(window)
                },
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] note in
                    guard let window = note.object as? NSWindow, !window.inLiveResize else { return }
                    self?.save(window)
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    self?.save(window)
                },
                center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.save(window)
                }
            ]
        }

        private func save(_ window: NSWindow) {
            WindowFrameStore.save(window.frame, name: name)
        }

        private func detachObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            observedWindow = nil
        }
    }
}
