import AppKit
import Darwin
import Foundation

final class SingleInstanceGuard {
    enum State: Equatable {
        case acquired
        case alreadyRunning
        case unavailable
    }

    let state: State
    private var fileDescriptor: Int32 = -1

    init(identifier: String, lockDirectory: URL? = nil) {
        let directory = lockDirectory ?? Self.defaultLockDirectory

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            state = .unavailable
            return
        }

        let safeIdentifier = identifier.replacingOccurrences(of: "/", with: "_")
        let lockURL = directory.appendingPathComponent("\(safeIdentifier).lock", isDirectory: false)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard descriptor >= 0 else {
            state = .unavailable
            return
        }

        var lock = Darwin.flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0

        if Darwin.fcntl(descriptor, F_SETLK, &lock) == 0 {
            fileDescriptor = descriptor
            state = .acquired
            return
        }

        let lockError = errno
        Darwin.close(descriptor)
        state = lockError == EACCES || lockError == EAGAIN ? .alreadyRunning : .unavailable
    }

    deinit {
        guard fileDescriptor >= 0 else {
            return
        }
        Darwin.close(fileDescriptor)
    }

    private static var defaultLockDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeSwitch", isDirectory: true)
    }
}

@MainActor
final class TypeSwitchAppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var isPrimaryInstance = false
    private static var configuredAppModel: AppModel?
    private static var configuredCoordinator: LayoutCoordinator?

    private var instanceGuard: SingleInstanceGuard?
    private var statusItemController: StatusItemController?

    static func configure(appModel: AppModel, coordinator: LayoutCoordinator) {
        configuredAppModel = appModel
        configuredCoordinator = coordinator
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.dmvishnyak.typeswitch"
        let guardInstance = SingleInstanceGuard(identifier: bundleIdentifier)
        instanceGuard = guardInstance

        switch guardInstance.state {
        case .acquired:
            Self.isPrimaryInstance = true
            return
        case .alreadyRunning:
            activateExistingInstance(bundleIdentifier: bundleIdentifier)
            Darwin.exit(EXIT_SUCCESS)
        case .unavailable:
            Darwin.exit(EXIT_FAILURE)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.isPrimaryInstance,
              let appModel = Self.configuredAppModel,
              let coordinator = Self.configuredCoordinator
        else {
            return
        }

        statusItemController = StatusItemController(appModel: appModel, coordinator: coordinator)
        Task { @MainActor in
            await coordinator.activate()
        }
    }

    private func activateExistingInstance(bundleIdentifier: String) {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessID && $0.isTerminated == false }

        _ = existingInstance?.activate(options: [.activateAllWindows])
    }
}
