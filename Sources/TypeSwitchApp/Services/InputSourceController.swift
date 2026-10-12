import Carbon
import Foundation

protocol InputSourceDriving {
    func currentSourceIdentifier() -> String?
    func availableSources() -> [InputSourceOption]
    func selectSource(identifier: String) -> Bool
}

struct SystemInputSourceDriver: InputSourceDriving {
    func currentSourceIdentifier() -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let unmanagedValue = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
        else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(unmanagedValue).takeUnretainedValue() as String
    }

    func availableSources() -> [InputSourceOption] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        return sourceList.compactMap { source in
            guard let categoryValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory),
                  Unmanaged<CFString>.fromOpaque(categoryValue).takeUnretainedValue() as String == kTISCategoryKeyboardInputSource as String,
                  let idValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            else {
                return nil
            }

            let sourceID = Unmanaged<CFString>.fromOpaque(idValue).takeUnretainedValue() as String
            let displayName: String
            if let nameValue = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                displayName = Unmanaged<CFString>.fromOpaque(nameValue).takeUnretainedValue() as String
            } else {
                displayName = sourceID
            }

            return InputSourceOption(sourceID: sourceID, displayName: displayName)
        }
    }

    func selectSource(identifier: String) -> Bool {
        let properties = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        guard let sourceList = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first
        else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }

}

struct InputSourceController {
    private let driver: InputSourceDriving

    init(driver: InputSourceDriving = SystemInputSourceDriver()) {
        self.driver = driver
    }

    func currentLayout() -> KeyboardLayout? {
        guard let currentIdentifier = driver.currentSourceIdentifier() else {
            return nil
        }

        if AppConstants.englishSourceIDs.contains(currentIdentifier) {
            return .usEnglish
        }

        if AppConstants.russianSourceIDs.contains(currentIdentifier) {
            return .russian
        }

        if AppConstants.ukrainianSourceIDs.contains(currentIdentifier)
            || currentIdentifier.lowercased().contains("ukrain") {
            return .ukrainian
        }

        return nil
    }

    func currentSourceIdentifier() -> String? {
        driver.currentSourceIdentifier()
    }

    func availableSourceOptions() -> [InputSourceOption] {
        var seenSourceIDs = Set<String>()
        return driver.availableSources()
            .filter { option in
                guard seenSourceIDs.contains(option.sourceID) == false else {
                    return false
                }
                seenSourceIDs.insert(option.sourceID)
                return true
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    @discardableResult
    func switchToLayout(_ layout: KeyboardLayout, preferredSourceID: String? = nil) -> Bool {
        let targetIdentifiers: [String]
        switch layout {
        case .usEnglish:
            targetIdentifiers = AppConstants.englishSourceIDs
        case .russian:
            targetIdentifiers = AppConstants.russianSourceIDs
        case .ukrainian:
            targetIdentifiers = AppConstants.ukrainianSourceIDs
        }

        let currentIdentifier = driver.currentSourceIdentifier()
        if let currentIdentifier {
            if let preferredSourceID {
                if currentIdentifier == preferredSourceID {
                    return true
                }
            } else if targetIdentifiers.contains(currentIdentifier) {
                return true
            }
        }

        let availableIdentifiers = driver.availableSources().map(\.sourceID)
        if let preferredSourceID, availableIdentifiers.contains(preferredSourceID) {
            guard driver.selectSource(identifier: preferredSourceID) else {
                return false
            }
            return driver.currentSourceIdentifier() == preferredSourceID
        }

        if let currentIdentifier, targetIdentifiers.contains(currentIdentifier) {
            return true
        }

        let targetIdentifier = targetIdentifiers.first { availableIdentifiers.contains($0) } ?? targetIdentifiers[0]
        guard driver.selectSource(identifier: targetIdentifier) else {
            return false
        }
        guard let selectedIdentifier = driver.currentSourceIdentifier() else {
            return false
        }
        return targetIdentifiers.contains(selectedIdentifier)
    }
}
