import Foundation

public enum CourseCatalog {
    /// Текущий курс языка (`course-<lang>.json`).
    public static func load(_ language: Language) throws -> Course {
        try decode(CoreResources.url("course-\(language.rawValue)", "json"))
    }

    /// Курс издания 1 (`course-<lang>-v1.json`, архив); `nil`, если файла нет.
    public static func legacy(_ language: Language) throws -> Course? {
        guard let url = CoreResources.bundle.url(forResource: "course-\(language.rawValue)-v1", withExtension: "json")
        else { return nil }
        return try decode(url)
    }

    /// Издание урока по id: `<lang>2.…` — 2, иначе 1.
    public static func edition(ofLessonId id: String) -> Int {
        Language.allCases.contains { id.hasPrefix("\($0.rawValue)2.") } ? 2 : 1
    }

    private static func decode(_ url: URL) throws -> Course {
        try JSONDecoder().decode(Course.self, from: Data(contentsOf: url))
    }
}
