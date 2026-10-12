import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general
        case ignoredApps
        case about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .ignoredApps: "Ignored Apps"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .ignoredApps: "nosign.app"
            case .about: "info.circle"
            }
        }
    }

    let appModel: AppModel
    let coordinator: LayoutCoordinator
    @State private var selectedPage: Page? = .general

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.icon)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 190)
        } detail: {
            switch selectedPage ?? .general {
            case .general:
                GeneralSettingsView(appModel: appModel, coordinator: coordinator)
            case .ignoredApps:
                IgnoredAppsSettingsView(appModel: appModel, coordinator: coordinator)
            case .about:
                AboutSettingsView(appModel: appModel)
            }
        }
        .frame(width: 680, height: 440)
    }
}

private struct GeneralSettingsView: View {
    let appModel: AppModel
    let coordinator: LayoutCoordinator

    var body: some View {
        Form {
            if appModel.permissionState.isReadyForManualCorrection == false {
                Section("Permissions Required") {
                    Text(appModel.permissionState.missingSummary)
                        .foregroundStyle(.orange)

                    HStack {
                        Button("Grant Permissions") { coordinator.requestPermissions() }
                        Button("Open System Settings") { PermissionSettingsOpener.openPrivacyAndSecurity() }
                        Button("Refresh") { coordinator.refreshPermissions() }
                    }
                }
            }

            Section("Auto-Fix") {
                HStack {
                    Text("Current state")
                    Spacer()
                    Text(appModel.autoFixEnabled ? "On" : "Off")
                        .foregroundStyle(appModel.autoFixEnabled ? Color.green : Color.secondary)
                }

                LabeledContent("Toggle shortcut") {
                    ShortcutRecorder(
                        shortcut: Binding(
                            get: { appModel.toggleAutoFixHotkey },
                            set: { coordinator.setToggleAutoFixHotkey($0) }
                        )
                    )
                    .frame(width: 240, height: 28)
                }
            }

            Section("Languages") {
                if appModel.availableLayouts.count < 2 {
                    Text("Add at least two supported input sources in macOS Settings.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.availableLayouts, id: \.self) { layout in
                        Toggle(
                            layout.displayName,
                            isOn: Binding(
                                get: { appModel.participatingLayouts.contains(layout) },
                                set: { coordinator.setLayout(layout, participates: $0) }
                            )
                        )
                        .disabled(
                            appModel.participatingLayouts.contains(layout)
                                && appModel.participatingLayouts.count <= 2
                        )
                    }
                    Text("Detected automatically from macOS. At least two languages must remain enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct IgnoredAppsSettingsView: View {
    let appModel: AppModel
    let coordinator: LayoutCoordinator
    @State private var selectedBundleID: String?
    @State private var isChoosingApps = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TypeSwitch will not change text in these applications.")
                .foregroundStyle(.secondary)

            Group {
                if appModel.ignoredApps.isEmpty {
                    ContentUnavailableView(
                        "No Ignored Apps",
                        systemImage: "square.and.arrow.down",
                        description: Text("Drag applications here or use the + button.")
                    )
                } else {
                    List(appModel.ignoredApps, selection: $selectedBundleID) { app in
                        IgnoredAppRow(app: app)
                            .tag(app.bundleID)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                addApplications(urls)
            } isTargeted: { isDropTargeted = $0 }

            HStack(spacing: 8) {
                Button { isChoosingApps = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add applications")

                Button {
                    guard let selectedBundleID else { return }
                    coordinator.removeIgnoredApp(bundleID: selectedBundleID)
                    self.selectedBundleID = nil
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedBundleID == nil)
                .help("Remove selected application")

                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .navigationTitle("Ignored Apps")
        .fileImporter(
            isPresented: $isChoosingApps,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            _ = addApplications(urls)
        }
        .onAppear { coordinator.refreshIgnoredApps() }
    }

    @discardableResult
    private func addApplications(_ urls: [URL]) -> Bool {
        urls.reduce(false) { addedAny, url in
            coordinator.addIgnoredApp(at: url) || addedAny
        }
    }
}

private struct IgnoredAppRow: View {
    let app: AppPolicy

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)

            Text(app.displayName)
        }
        .padding(.vertical, 3)
    }

    private var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AboutSettingsView: View {
    let appModel: AppModel

    var body: some View {
        Form {
            Section("TypeSwitch") {
                Text("Private, local keyboard-layout correction for macOS.")
                    .foregroundStyle(.secondary)
                LabeledContent("Dictionary coverage") {
                    Text(appModel.dictionaryCoverageDescription)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Dictionary Sources") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FrequencyWords / OpenSubtitles 2018")
                    Link("Source · CC BY-SA 4.0", destination: URL(string: "https://github.com/hermitdave/FrequencyWords")!)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hunspell English, Russian, and Ukrainian dictionaries")
                    Link("Source and license notices", destination: URL(string: "https://github.com/wooorm/dictionaries")!)
                        .font(.caption)
                }

                Text("TypeSwitch filters, normalizes, and combines these sources locally. No dictionary data is downloaded at runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}

#Preview {
    let appModel = AppModel()
    let coordinator = LayoutCoordinator(appModel: appModel)
    return SettingsView(appModel: appModel, coordinator: coordinator)
}
