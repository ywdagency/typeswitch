import Foundation
import Testing
@testable import TypeSwitchApp

@Test
func singleInstanceGuardAcquiresAndReleasesLock() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var firstGuard: SingleInstanceGuard? = SingleInstanceGuard(
        identifier: "com.example.TypeSwitchTests",
        lockDirectory: directory
    )
    #expect(firstGuard?.state == .acquired)

    firstGuard = nil

    let replacementGuard = SingleInstanceGuard(
        identifier: "com.example.TypeSwitchTests",
        lockDirectory: directory
    )
    #expect(replacementGuard.state == .acquired)
}
