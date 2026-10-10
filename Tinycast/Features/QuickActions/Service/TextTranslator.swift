import Foundation
import NaturalLanguage
import Translation

/// `TranslationError` is macOS 26.4 against a 26.0 floor, so failures stay plain `Error` here.
enum TextTranslator {
    enum Failure: LocalizedError, Equatable {
        case undetectableSource
        case unsupported
        case notInstalled(language: String)
        case failed
        /// Sonoma port: everything below `translate` needs macOS 15's Translation framework.
        case needsNewerMacOS

        var errorDescription: String? {
            switch self {
            case .undetectableSource:
                return "The language of the selected text could not be identified."
            case .unsupported:
                return "Apple's translator does not support this language pair."
            case .notInstalled(let language):
                return "\(language) needs to be downloaded before it can be used."
            case .failed:
                return "The text could not be translated."
            case .needsNewerMacOS:
                return "Translating isn't available in this build."
            }
        }
    }

    /// `TranslationSession(installedSource:)` needs a language; availability reports only a status.
    static func sourceLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: dominant.rawValue)
    }

    /// Installed pairs only: fetching one needs SwiftUI's `translationTask`, which the panel owns.
    static func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard let source = sourceLanguage(of: text) else { throw Failure.undetectableSource }
        guard !source.isEquivalent(to: target) else { return text }
        // Sonoma port: Apple's translator cannot be built on this branch at all — the
        // `TranslationSession(installedSource:target:)` initialiser the flow needs does not exist in
        // the macOS 15.2 SDK (it is 26-era), and `LanguageAvailability` is 15+ besides. So the whole
        // path collapses into one honest answer instead of several partial ones.
        _ = source
        throw Failure.needsNewerMacOS
    }

    /// Minimal, not maximal: the maximal form would spell `es` "Spanish (Latin, Spain)" in a menu.
    static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    /// The framework's own list, so the picker cannot offer a pair that only fails at press time.
    static func supportedLanguages() async -> [Locale.Language] {
        // Sonoma port: `LanguageAvailability` is macOS 15+; 14 offers no pairs to pick from.
        guard #available(macOS 15.0, *) else { return [] }
        return await LanguageAvailability().supportedLanguages
            .sorted { displayName(of: $0) < displayName(of: $1) }
    }
}
