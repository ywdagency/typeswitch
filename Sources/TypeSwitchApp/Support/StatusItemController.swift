import AppKit
import Observation

enum StatusItemClickAction: Equatable {
    case showMenu
    case toggleAutoFix
    case ignore

    static func resolve(eventType: NSEvent.EventType?) -> StatusItemClickAction {
        switch eventType {
        case .leftMouseUp:
            .showMenu
        case .rightMouseUp:
            .toggleAutoFix
        default:
            .ignore
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let appModel: AppModel
    private let coordinator: LayoutCoordinator
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(appModel: AppModel, coordinator: LayoutCoordinator) {
        self.appModel = appModel
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        guard let button = statusItem.button else {
            return
        }

        let image = Bundle.module.url(forResource: "StatusBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "TypeSwitch")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateAppearance()
        observeModel()
    }

    @objc
    private func handleClick() {
        switch StatusItemClickAction.resolve(eventType: NSApp.currentEvent?.type) {
        case .showMenu:
            showMenu()
        case .toggleAutoFix:
            coordinator.toggleAutoFix()
            updateAppearance()
        case .ignore:
            break
        }
    }

    private func showMenu() {
        coordinator.refreshPermissions()
        coordinator.refreshLearningCandidate()
        rebuildMenu()

        guard let button = statusItem.button,
              let event = NSApp.currentEvent
        else {
            return
        }

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if appModel.permissionState.isReadyForManualCorrection == false {
            if appModel.permissionState.inputMonitoring != .granted {
                addMenuItem(title: "Enable Input Monitoring…", action: #selector(requestInputMonitoring))
            }
            if appModel.permissionState.accessibility != .granted {
                addMenuItem(title: "Enable Accessibility…", action: #selector(requestAccessibility))
            }
            menu.addItem(.separator())
        }

        addMenuItem(
            title: appModel.autoFixEnabled ? "Switcher: ON" : "Switcher: OFF",
            action: #selector(toggleAutoFix),
            enabled: appModel.permissionState.isReadyForManualCorrection
        )

        if appModel.pendingLearningCandidate != nil {
            addMenuItem(title: "Add Last Word to Dictionary…", action: #selector(learnLastWord))
        }

        if appModel.learnedCorrections.isEmpty == false {
            addMenuItem(title: "Learned Words…", action: #selector(openLearnedWords))
        }

        addMenuItem(title: "Settings…", action: #selector(openSettings))
        menu.addItem(.separator())
        addMenuItem(title: "Quit TypeSwitch", action: #selector(quitApp))
    }

    private func addMenuItem(title: String, action: Selector, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func updateAppearance() {
        statusItem.button?.alphaValue = appModel.autoFixEnabled ? 1 : 0.45
        statusItem.button?.toolTip = appModel.autoFixEnabled
            ? "TypeSwitch — Auto-Fix On. Right-click to turn it off."
            : "TypeSwitch — Auto-Fix Off. Right-click to turn it on."
    }

    private func observeModel() {
        withObservationTracking {
            _ = appModel.autoFixEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateAppearance()
                self?.observeModel()
            }
        }
    }

    @objc private func requestInputMonitoring() {
        coordinator.requestPermission(.inputMonitoring)
    }

    @objc private func requestAccessibility() {
        coordinator.requestPermission(.accessibility)
    }

    @objc private func toggleAutoFix() {
        coordinator.toggleAutoFix()
    }

    @objc private func openSettings() {
        SettingsWindowPresenter.shared.show(appModel: appModel, coordinator: coordinator)
    }

    @objc private func learnLastWord() {
        coordinator.refreshLearningCandidate()
        guard let candidate = appModel.pendingLearningCandidate else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add this correction to the dictionary?"
        alert.informativeText = "\(candidate.entry.wrongToken) → \(candidate.entry.correctToken)\n\nIt will be stored only on this Mac and used for future corrections."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        coordinator.learnPendingCorrection()
    }

    @objc private func openLearnedWords() {
        LearnedWordsWindowPresenter.shared.show(appModel: appModel, coordinator: coordinator)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
