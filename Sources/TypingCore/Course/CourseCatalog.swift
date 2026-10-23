import Foundation

public enum CourseCatalog {
    public static func load(_ language: Language) throws -> Course {
        let data = try Data(contentsOf: CoreResources.url("course-\(language.rawValue)", "json"))
        return try JSONDecoder().decode(Course.self, from: data)
    }
}
