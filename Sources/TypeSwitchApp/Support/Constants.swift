import Foundation

enum AppConstants {
    static let bundleIdentifier = "com.dmvishnyak.typeswitch"
    static let usEnglishSourceID = "com.apple.keylayout.US"
    static let russianSourceID = "com.apple.keylayout.Russian"
    static let ukrainianSourceID = "com.apple.keylayout.Ukrainian"
    static let englishSourceIDs = [
        "com.apple.keylayout.US",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.Canadian"
    ]
    static let russianSourceIDs = [
        "com.apple.keylayout.RussianWin",
        "com.apple.keylayout.Russian"
    ]
    static let ukrainianSourceIDs = [
        "com.apple.keylayout.Ukrainian",
        "com.apple.keylayout.Ukrainian-PC"
    ]
    static let inputMonitorQueueLabel = "TypeSwitch.InputMonitorQueue"
    static let autoFixDelayNanoseconds: UInt64 = 60_000_000
    static let autoCorrectionUndoDelayNanoseconds: UInt64 = 30_000_000
    static let autoCorrectionUndoLifetime: TimeInterval = 3
    static let learningCandidateLifetime: TimeInterval = 30
    static let minimumConfidence = 0.72
    static let syntheticEventMarker: Int64 = 0x545950455357
}
