import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []
    private var preparedWindowIDs = Set<ObjectIdentifier>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 화면에 올라오기 전/직후에 프레임을 맞춰 깜빡임을 줄입니다.
        let names: [Notification.Name] = [
            Notification.Name("NSWindowWillOrderOnScreenNotification"),
            NSWindow.didBecomeKeyNotification
        ]

        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.prepareMainWindow(note.object as? NSWindow)
            }
            windowObservers.append(observer)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            prepareMainWindow(window)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            WindowFrameStore.save(window.frame)
        }
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private func prepareMainWindow(_ window: NSWindow?) {
        guard let window, window.styleMask.contains(.titled) else { return }

        let id = ObjectIdentifier(window)
        guard !preparedWindowIDs.contains(id) else { return }
        preparedWindowIDs.insert(id)

        WindowFrameStore.applyLaunchFrame(to: window)
    }

    /// 빨간 X로 마지막 창을 닫으면 앱도 함께 종료합니다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Dock 아이콘 클릭 시 창이 없으면 다시 앞으로 가져옵니다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        if let window = sender.windows.first(where: { $0.canBecomeKey }) ?? sender.windows.first {
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

@main
struct PushTesterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var fieldPresetStore = FieldPresetStore()
    @StateObject private var certificatePresetStore = CertificatePresetStore()

    private var launchSize: CGSize {
        if let frame = WindowFrameStore.load() {
            return CGSize(width: frame.width, height: frame.height)
        }
        return CGSize(width: 1100, height: 940)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyStore)
                .environmentObject(fieldPresetStore)
                .environmentObject(certificatePresetStore)
                .frame(minWidth: 900, minHeight: 480)
                .background(WindowFrameAutosave(name: WindowFrameStore.mainWindowName))
        }
        .defaultSize(width: launchSize.width, height: launchSize.height)
    }
}
