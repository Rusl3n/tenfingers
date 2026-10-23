import SwiftData
import SwiftUI
import TypingCore

struct HomeView: View {
    let start: (LessonRun) -> Void

    @Environment(ContentLibrary.self) private var library
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @Query private var days: [DayRecord]
    @Query private var progress: [LessonProgress]
    @Query(HomeView.firstSessionDescriptor) private var firstSessions: [SessionRecord]

    static var firstSessionDescriptor: FetchDescriptor<SessionRecord> {
        var descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }
    private var course: Course? { library.courses[language] }
    private var passed: Set<String> {
        Set(progress.filter { $0.language == language.rawValue && $0.passedAt != nil }.map(\.lessonId))
    }
    private var todaySeconds: Double {
        let key = LogicalDay.key(for: .now, dayStartHour: dayStartHour)
        return days.first { $0.logicalDay == key }?.activeSeconds ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Курс: \(language.displayName)").font(.largeTitle.bold())
                todayCard
                if let course { continueCard(course) }
                statsGrid
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    private var todayCard: some View {
        let minutes = todaySeconds / 60
        let done = Int(minutes)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Сегодня \(done) из \(dailyGoal) мин").font(.headline)
            ProgressView(value: min(minutes, Double(dailyGoal)), total: Double(dailyGoal))
                .tint(.orange)
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func continueCard(_ course: Course) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let lesson = course.nextLesson(passed: passed) {
                    let stage = course.stage(of: lesson.id)?.localizedTitle ?? ""
                    Text("Продолжить курс · \(stage)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(lesson.localizedTitle).font(.title3.bold())
                } else {
                    Text("Курс пройден").font(.title3.bold())
                }
                let percent = "\(Int(course.completion(passed: passed) * 100))%"
                Text("Пройдено \(percent) курса")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let lesson = course.nextLesson(passed: passed) {
                Button("Начать") { start(LessonRun(language: language, lessonId: lesson.id)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                Text("Всего практики").foregroundStyle(.secondary)
                Text(Formatting.duration(days.reduce(0) { $0 + $1.activeSeconds }))
            }
            GridRow {
                Text("Занимаетесь с").foregroundStyle(.secondary)
                Text(firstSessions.first.map { $0.startedAt.formatted(date: .long, time: .omitted) } ?? String(localized: "сегодня"))
            }
            GridRow {
                Text("Пройдено уроков").foregroundStyle(.secondary)
                Text("\(passed.count) из \(course?.lessons.count ?? 0)")
            }
        }
    }
}
