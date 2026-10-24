import SwiftData
import SwiftUI
import TypingCore

struct CourseMapView: View {
    let start: (LessonRun) -> Void

    @Environment(ContentLibrary.self) private var library
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Query private var progress: [LessonProgress]
    /// Завершённые упражнения курса: из них считаются звёзды и детали по шагам.
    @Query(filter: #Predicate<SessionRecord> { $0.mode == "course" && $0.completed })
    private var courseSessions: [SessionRecord]
    @State private var expanded: Set<String> = []

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
            let records = progressById
            let sessions = Dictionary(grouping: courseSessions.compactMap(ProgressSnapshot.summary)) { $0.lessonId ?? "" }
            let passed = passed
            // ScrollView, а не List: строки List — отдельные NSHostingView, и при масштабе интерфейса
            // (`uiScaled`) клики в них попадают мимо кнопок.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(course.stages) { stage in
                        Section {
                            ForEach(stage.lessons) { lesson in
                                let record = records[lesson.id]
                                let overview = LessonOverview.make(lessonId: lesson.id, targetCpm: stage.targetCpm,
                                                                   sessions: sessions[lesson.id] ?? [],
                                                                   storedStars: record?.bestStars ?? 0,
                                                                   isPassed: record?.passedAt != nil)
                                CourseLessonRow(lesson: lesson, language: language, overview: overview,
                                                targetCpm: stage.targetCpm, bestCpm: record?.bestCpm ?? 0, isPassed: record?.passedAt != nil,
                                                isUnlocked: course.isUnlocked(lesson.id, passed: passed), unit: unit,
                                                isExpanded: expandedBinding(lesson.id), start: start)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                        } header: {
                            let goal = unit.format(Double(stage.targetCpm))
                            HStack {
                                Text(stage.localizedTitle).foregroundStyle(.primary)
                                Spacer()
                                Text("цель \(goal)").foregroundStyle(.secondary)
                            }
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                            .background(palette.background)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Курс · \(language.displayName)")
        }
    }

    private func expandedBinding(_ lessonId: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(lessonId) },
                set: { if $0 { expanded.insert(lessonId) } else { expanded.remove(lessonId) } })
    }
}

/// Строка урока на карте курса. У пройденного или начатого урока — средняя точность по шагам и раскрытие:
/// строки шагов с лучшей точностью, ошибками, скоростью и кнопкой «Пройти заново».
/// Рядом со звёздами — «?» с объяснением звёзд (цели этапа строки): приглушена, ярче при наведении,
/// у раскрытого урока и пока открыт попап, чтобы не спорить со звёздами в каждой строке.
struct CourseLessonRow: View {
    let lesson: Lesson
    let language: Language
    let overview: LessonOverview
    let targetCpm: Int
    let bestCpm: Double
    let isPassed: Bool
    let isUnlocked: Bool
    let unit: SpeedUnit
    @Binding var isExpanded: Bool
    let start: (LessonRun) -> Void

    @State private var isHovered = false
    @State private var showsStarsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    start(LessonRun(language: language, lessonId: lesson.id))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isPassed ? "checkmark.circle.fill" : (isUnlocked ? "play.circle" : "lock"))
                            .foregroundStyle(isPassed ? Color.green : Color.secondary)
                            .frame(width: 20)
                        Text(lesson.localizedTitle)
                        Spacer()
                        if bestCpm > 0 {
                            Text(unit.format(bestCpm)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        StarsView(count: overview.stars)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked)
                StarsHelpButton(targetCpm: targetCpm, unit: unit, isPresented: $showsStarsHelp)
                    .opacity(isHovered || isExpanded || showsStarsHelp ? 1 : 0.35)
                if let average = overview.averageAccuracy {
                    Text(verbatim: "Ø \(Formatting.percent(average))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                        .help(Text("Средняя точность по шагам урока"))
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isExpanded ? Text("Скрыть шаги") : Text("Показать шаги"))
                } else {
                    Color.clear.frame(width: 18 + 64 + 12, height: 1)
                }
            }
            if isExpanded, !overview.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(overview.steps, id: \.kind) { step in stepRow(step) }
                }
                .padding(.leading, 32)
                .padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func stepRow(_ step: StepStat) -> some View {
        HStack(spacing: 14) {
            Text(step.kind.localizedTitle)
                .frame(width: 210, alignment: .leading)
            Text(Formatting.percent(step.bestAccuracy))
                .foregroundStyle(Self.accuracyColor(step.bestAccuracy))
                .frame(width: 64, alignment: .trailing)
            Text("ошибок: \(step.errorsInBest)")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(unit.format(step.bestCpm))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                start(LessonRun(language: language, lessonId: lesson.id, onlyStep: step.kind))
            } label: {
                Label("Пройти заново", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!isUnlocked)
        }
        .font(.callout)
        .monospacedDigit()
    }

    /// 100% — зелёным, ниже 98% — оранжевым.
    static func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 1 { return .green }
        if accuracy < LessonScoring.twoStarAccuracy { return .orange }
        return .primary
    }
}
