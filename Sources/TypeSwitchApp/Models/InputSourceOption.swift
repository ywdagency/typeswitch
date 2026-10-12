import Foundation

struct InputSourceOption: Codable, Equatable, Identifiable {
    var id: String { sourceID }
    let sourceID: String
    let displayName: String

    var userFacingName: String {
        guard displayName != sourceID else {
            return sourceID.split(separator: ".").last.map(String.init) ?? sourceID
        }
        return displayName
    }

    var keyboardLayout: KeyboardLayout? {
        if AppConstants.englishSourceIDs.contains(sourceID) { return .usEnglish }
        if AppConstants.russianSourceIDs.contains(sourceID) { return .russian }
        if AppConstants.ukrainianSourceIDs.contains(sourceID) { return .ukrainian }

        let normalized = "\(sourceID) \(displayName)".lowercased()
        if normalized.contains("ukrain") { return .ukrainian }
        if normalized.contains("russian") { return .russian }
        return nil
    }
}
