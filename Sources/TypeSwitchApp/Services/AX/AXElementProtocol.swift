import ApplicationServices
import Foundation

enum AXElementError: Error, Equatable {
    case missingValue
    case missingSelection
    case invalidRange
    case notWritable
    case unsupported
    case staleValue
    case verificationFailed

    var userFacingDescription: String {
        switch self {
        case .missingValue:
            "AX value is unavailable."
        case .missingSelection:
            "AX selection or caret range is unavailable."
        case .invalidRange:
            "AX text range is invalid."
        case .notWritable:
            "AX value is not writable."
        case .unsupported:
            "AX text model is unsupported."
        case .staleValue:
            "AX text changed before the replacement could be applied."
        case .verificationFailed:
            "AX did not confirm the text replacement."
        }
    }
}

protocol AXElementProtocol: AnyObject {
    var role: String? { get }
    var subrole: String? { get }
    var isValueSettable: Bool { get }
    var isSelectedTextSettable: Bool { get }
    var isSelectedTextRangeSettable: Bool { get }

    func stringValue() throws -> String?
    func selectedText() throws -> String?
    func selectedTextRange() throws -> CFRange?
    func setStringValue(_ value: String) throws
    func setSelectedText(_ value: String) throws
    func setSelectedTextRange(_ range: CFRange) throws
}

extension AXElementProtocol {
    var isSelectedTextSettable: Bool { false }
    var isSelectedTextRangeSettable: Bool { false }

    func setSelectedText(_ value: String) throws {
        throw AXElementError.unsupported
    }
}
