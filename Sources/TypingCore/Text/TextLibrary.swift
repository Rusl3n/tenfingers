import Foundation

/// Отрывок для практики из встроенной библиотеки.
public struct LibraryText: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let author: String
    public let text: String
    /// Адрес, откуда взят текст (Project Gutenberg или Викитека).
    public let source: String
}

/// Встроенные отрывки из произведений в общественном достоянии.
public enum TextLibrary {
    public static func load(_ language: Language) throws -> [LibraryText] {
        let data = try Data(contentsOf: CoreResources.url("texts-\(language.rawValue)", "json"))
        return try JSONDecoder().decode([LibraryText].self, from: data)
    }
}
