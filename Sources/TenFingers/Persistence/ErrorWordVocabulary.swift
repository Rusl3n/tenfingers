import Foundation
import TypingCore

/// Частотный словарь языка как множество слов; загружается один раз на язык и кэшируется.
enum ErrorWordVocabulary {
    private static let ru: Set<String> = load(.ru)
    private static let en: Set<String> = load(.en)

    static func words(_ language: Language) -> Set<String> {
        switch language {
        case .ru: return ru
        case .en: return en
        }
    }

    private static func load(_ language: Language) -> Set<String> {
        Set((try? WordList.load(language).words) ?? [])
    }
}
