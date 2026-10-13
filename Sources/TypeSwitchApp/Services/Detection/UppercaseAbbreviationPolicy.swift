import Foundation

enum UppercaseAbbreviationPolicy {
    // A curated source-language allowlist; length or capitalization alone is not evidence.
    private static let known: [KeyboardLayout: Set<String>] = [
        .usEnglish: Set("API SDK CEO CTO CFO COO SQL HTTP HTTPS HTML CSS JSON XML URL URI CPU GPU RAM SSD USB PDF VPN DNS SSH TLS SSL UI UX AI ML LLM FAQ PR HR QA CI CD ID ISBN USA UK EU UN NATO NASA FBI CIA".split(separator: " ").map(String.init)),
        .russian: Set("СССР США РФ СНГ ООН НАТО МВД ФСБ ГИБДД НДС ИП ООО ОАО ПАО ЗАО МГУ СПБГУ РАН ЖКХ СМИ ВВП ИНН ОГРН ИИ СУБД".split(separator: " ").map(String.init)),
        .ukrainian: Set("ЗСУ США ООН НАТО ЄС МВС СБУ ПДВ ФОП ТОВ НБУ ЗМІ ШІ ВВП".split(separator: " ").map(String.init))
    ]

    static func protects(_ token: String, layout: KeyboardLayout) -> Bool {
        known[layout]?.contains(token) == true
    }
}
