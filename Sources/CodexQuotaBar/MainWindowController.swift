import AppKit
import SwiftUI

@MainActor
final class QuotaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        QuotaModel.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show(model: .shared)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Keep the interactive main window separate from the background desktop panel.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show(model: QuotaModel) {
        if window == nil {
            let view = NSHostingController(rootView: MainView(model: model))
            let main = NSWindow(contentViewController: view)
            main.title = "Codex Quota"
            main.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            main.setContentSize(NSSize(width: 780, height: 680))
            main.minSize = NSSize(width: 760, height: 660)
            main.isReleasedWhenClosed = false
            main.level = .normal
            main.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            main.center()
            main.setFrameAutosaveName("CodexQuotaMainWindow")
            window = main
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
