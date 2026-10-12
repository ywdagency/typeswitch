import SwiftUI

@main
struct TypeSwitchApp: App {
    @NSApplicationDelegateAdaptor(TypeSwitchAppDelegate.self) private var appDelegate
    @State private var appModel: AppModel
    @State private var coordinator: LayoutCoordinator

    init() {
        let appModel = AppModel()
        let coordinator = LayoutCoordinator(appModel: appModel)
        _appModel = State(initialValue: appModel)
        _coordinator = State(initialValue: coordinator)
        TypeSwitchAppDelegate.configure(appModel: appModel, coordinator: coordinator)
    }

    var body: some Scene {
        Settings {
            SettingsView(appModel: appModel, coordinator: coordinator)
                .task {
                    await coordinator.activate()
                }
        }
    }
}
