import Foundation

enum AppLanguage: Equatable {
    case chinese
    case english

    static func preferred(_ languages: [String]) -> AppLanguage {
        guard let first = languages.first else { return .english }
        return first.lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

enum L10n {
    static var language: AppLanguage { .preferred(Locale.preferredLanguages) }

    static func text(_ chinese: String, _ english: String, language: AppLanguage = L10n.language) -> String {
        language == .chinese ? chinese : english
    }
}
