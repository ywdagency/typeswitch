import AppKit
import SwiftUI

@MainActor
final class LearnedWordsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = LearnedWordsWindowPresenter()

    private var window: NSWindow?

    func show(appModel: AppModel, coordinator: LayoutCoordinator) {
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hostingController = NSHostingController(
            rootView: LearnedWordsView(appModel: appModel, coordinator: coordinator)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TypeSwitch Learned Words"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
