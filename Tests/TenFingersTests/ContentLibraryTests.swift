import Testing
import TypingCore
@testable import TenFingers

/// Ресурсы курсов грузятся без ошибок; архив издания 1 (`course-ru-v1.json`) доступен приложению.
@MainActor @Test func contentLibraryLoadsCoursesAndLegacyArchive() {
    let library = ContentLibrary()
    #expect(library.loadError == nil)
    #expect(library.legacyCourses[.ru] != nil)
}
