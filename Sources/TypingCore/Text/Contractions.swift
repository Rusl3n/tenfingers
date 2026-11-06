import Foundation

/// Английские сокращения с апострофом: в частотном словаре их нет, а в «слова с ошибками» они попадают целиком —
/// но только когда апостроф уже знаком по курсу (решение пользователя, 2026-11-06).
public enum Contractions {
    /// Частые сокращения в нижнем регистре, с прямым апострофом.
    public static let english: Set<String> = [
        "don't", "doesn't", "didn't", "can't", "couldn't", "won't", "wouldn't", "shouldn't", "mustn't", "needn't",
        "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
        "i'm", "i've", "i'll", "i'd", "you're", "you've", "you'll", "you'd",
        "he's", "he'll", "he'd", "she's", "she'll", "she'd", "it's", "it'll",
        "we're", "we've", "we'll", "we'd", "they're", "they've", "they'll", "they'd",
        "that's", "that'll", "there's", "here's", "what's", "who's", "where's", "how's", "let's",
    ]

    /// Апостроф знаком: среди `lessonIds` (пройденные уроки и урок, который идёт) есть урок, где апостроф
    /// уже введён, — сам урок с апострофом среди новых клавиш или любой после него.
    public static func apostropheKnown(courses: [Course], lessonIds: Set<String>) -> Bool {
        courses.contains { course in
            let lessons = course.lessons
            guard let first = lessons.firstIndex(where: { $0.newCharacters.contains("'") }) else { return false }
            return lessons[first...].contains { lessonIds.contains($0.id) }
        }
    }
}
