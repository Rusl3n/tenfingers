import SwiftData
import SwiftUI
import TypingCore

struct CourseMapView: View {
    let start: (LessonRun) -> Void

    @Environment(ContentLibrary.self) private var library
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Query private var progress: [LessonProgress]

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }
    private var progressById: [String: LessonProgress] {
        Dictionary(progress.filter { $0.language == language.rawValue }.map { ($0.lessonId, $0) },
                   uniquingKeysWith: { first, _ in first })
    }
    private var passed: Set<String> {
        Set(progressById.values.filter { $0.passedAt != nil }.map(\.lessonId))
    }

    var body: some View {
        if let course = library.courses[language] {
            List {
                ForEach(course.stages) { stage in
                    Section {
                        ForEach(stage.lessons) { lesson in row(lesson, course: course) }
                    } header: {
                        let goal = unit.format(Double(stage.targetCpm))
                        HStack {
                            Text(stage.localizedTitle)
                            Spacer()
                            Text("цель \(goal)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Курс · \(language.displayName)")
        }
    }

    private func row(_ lesson: Lesson, course: Course) -> some View {
        let unlocked = course.isUnlocked(lesson.id, passed: passed)
        let record = progressById[lesson.id]
        let icon = record?.passedAt != nil ? "checkmark.circle.fill" : (unlocked ? "play.circle" : "lock")
        return Button {
            start(LessonRun(language: language, lessonId: lesson.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(record?.passedAt != nil ? Color.green : Color.secondary)
                    .frame(width: 20)
                Text(lesson.localizedTitle)
                Spacer()
                if let record, record.bestCpm > 0 {
                    Text(unit.format(record.bestCpm)).foregroundStyle(.secondary).monospacedDigit()
                }
                StarsView(count: record?.bestStars ?? 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
