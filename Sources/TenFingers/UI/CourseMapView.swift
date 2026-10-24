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
            HStack(spacing: CourseColumns.spacing) {
                Button {
                    start(LessonRun(language: language, lessonId: lesson.id))
                } label: {
                    HStack(spacing: CourseColumns.spacing) {
                        Image(systemName: isPassed ? "checkmark.circle.fill" : (isUnlocked ? "play.circle" : "lock"))
                            .foregroundStyle(isPassed ? Color.green : Color.secondary)
                            .frame(width: 20)
                        Text(lesson.localizedTitle)
                        Spacer()
                        // Слева направо: ошибки, скорость, звёзды. Ширина колонок не зависит от значений,
                        // у строки без попыток ячейки пусты, но места не теряют.
                        CourseColumn(id: "errors", text: CourseColumns.errorsText(overview.errors),
                                     templates: CourseColumns.errorsTemplates)
                            .foregroundStyle(.secondary)
                            .help(Text("Сумма ошибок в лучших попытках шагов урока"))
                        CourseColumn(id: "speed", text: CourseColumns.speedText(bestCpm, unit: unit),
                                     templates: CourseColumns.speedTemplates)
                            .foregroundStyle(.secondary)
                        CourseStarsColumn(count: overview.stars)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked)
                StarsHelpButton(targetCpm: targetCpm, unit: unit, isPresented: $showsStarsHelp)
                    .opacity(isHovered || isExpanded || showsStarsHelp ? 1 : 0.35)
                    .courseColumnFrame("help")
                if overview.errors != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: CourseColumns.chevronWidth, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isExpanded ? Text("Скрыть шаги") : Text("Показать шаги"))
                    .courseColumnFrame("chevron")
                } else {
                    Color.clear.frame(width: CourseColumns.chevronWidth, height: 18).courseColumnFrame("chevron")
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

    /// Шаг: колонки «ошибки», «скорость» те же, что у строки урока (ширина по тем же шаблонам, правые края
    /// совпадают), а «Пройти заново» стоит на месте звёзд, «?» и стрелки.
    private func stepRow(_ step: StepStat) -> some View {
        HStack(spacing: CourseColumns.spacing) {
            Text(step.kind.localizedTitle)
            Spacer()
            CourseColumn(id: "step.\(step.kind.rawValue).errors", text: CourseColumns.stepErrorsText(step.errorsInBest),
                         templates: CourseColumns.errorsTemplates)
                .foregroundStyle(Self.errorsColor(step))
            CourseColumn(id: "step.\(step.kind.rawValue).speed", text: CourseColumns.speedText(step.bestCpm, unit: unit),
                         templates: CourseColumns.speedTemplates)
                .foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                CourseColumns.trailingTemplate
                Button {
                    start(LessonRun(language: language, lessonId: lesson.id, onlyStep: step.kind))
                } label: {
                    Label("Пройти заново", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!isUnlocked)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.callout)
        .monospacedDigit()
    }

    /// Без ошибок — зелёным, точность ниже порога чистого шага (мешает ★★★★★) — оранжевым, иначе приглушённо
    /// (на пороге — тоже приглушённо: сравнение с допуском, как у звёзд).
    static func errorsColor(_ step: StepStat) -> Color {
        if step.errorsInBest == 0 { return .green }
        if step.bestAccuracy + LessonScoring.accuracyTolerance < LessonScoring.cleanLessonStepAccuracy { return .orange }
        return .secondary
    }
}

/// Тексты колонок карты курса и их шаблоны ширины (чистые функции: проверяются без отрисовки).
enum CourseColumns {
    static let spacing: CGFloat = 12
    static let chevronWidth: CGFloat = 18
    /// Шрифт цифровых колонок общий у строки урока и строк шагов: ширина шаблона зависит от шрифта.
    static let font = Font.callout

    /// «ошибок: 3»; у урока без попыток (`nil`) — пусто.
    static func errorsText(_ errors: Int?) -> String {
        guard let errors else { return "" }
        return String(localized: "ошибок: \(errors)")
    }

    /// «217 зн/мин»; без попыток (скорость 0) — пусто.
    static func speedText(_ cpm: Double, unit: SpeedUnit) -> String {
        cpm > 0 ? unit.format(cpm) : ""
    }

    /// Ошибки в строке шага: «0 ошибок», «1 ошибка».
    static func stepErrorsText(_ errors: Int) -> String { Formatting.errors(errors) }

    /// Самое длинное значение колонки ошибок: «ошибок: 999».
    static var errorsTemplates: [String] { [errorsText(999)] }

    /// Самые длинные значения скорости в обеих единицах: «999 зн/мин» и «99 WPM»; ширина одна для обеих.
    static var speedTemplates: [String] { [SpeedUnit.cpm.format(999), SpeedUnit.wpm.format(99 * 5)] }

    /// Невидимая копия блока «звёзды, ?, стрелка» строки урока: задаёт место под «Пройти заново» в строке шага.
    @MainActor static var trailingTemplate: some View {
        HStack(spacing: spacing) {
            CourseStarsColumn(count: 0)
            StarsHelpButton(targetCpm: 0, unit: .cpm)
            Color.clear.frame(width: chevronWidth, height: 1)
        }
        .hidden()
        .accessibilityHidden(true)
    }
}

/// Рамки колонок для проверки раскладки (читаются тестом; в приложении не используются).
struct CourseColumnFramesKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func courseColumnFrame(_ id: String) -> some View {
        anchorPreference(key: CourseColumnFramesKey.self, value: .bounds) { [id: $0] }
    }
}

/// Колонка с текстом по правому краю. Ширину задаёт невидимый самый длинный шаблон (по шрифту и языку, а не по
/// числу), поэтому колонки в строках совпадают, а при масштабе интерфейса растут вместе с текстом.
struct CourseColumn: View {
    let id: String
    let text: String
    let templates: [String]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(templates, id: \.self) { Text($0).hidden() }
            Text(text)
        }
        .lineLimit(1)
        .font(CourseColumns.font)
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .courseColumnFrame(id)
    }
}

/// Колонка звёзд: всегда пять позиций, у урока без звёзд — пустые.
struct CourseStarsColumn: View {
    let count: Int

    var body: some View {
        StarsView(count: count)
            .fixedSize()
            .courseColumnFrame("stars")
    }
}
