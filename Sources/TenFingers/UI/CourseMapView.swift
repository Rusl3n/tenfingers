import SwiftData
import SwiftUI
import TypingCore

struct CourseMapView: View {
    let start: (LessonRun) -> Void

    @Environment(ContentLibrary.self) private var library
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
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
            let summaries = courseSessions.compactMap(ProgressSnapshot.summary)
            let sessions = Dictionary(grouping: summaries) { $0.lessonId ?? "" }
            let passed = passed
            // Гейт этапов издания 2: звёзды проверок по тем же сессиям (у издания 1 порога нет).
            let checkStars = CourseGate.checkStars(course: course, sessions: summaries)
            let today = LogicalDay.key(for: .now, dayStartHour: dayStartHour)
            // ScrollView, а не List: строки List — отдельные NSHostingView, и при масштабе интерфейса
            // (`uiScaled`) клики в них попадают мимо кнопок.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(course.stages.enumerated()), id: \.element.id) { stageIndex, stage in
                        Section {
                            ForEach(Array(stage.lessons.enumerated()), id: \.element.id) { lessonIndex, lesson in
                                let record = records[lesson.id]
                                let target = course.targetCpm(for: lesson.id) ?? 0
                                let overview = LessonOverview.make(lessonId: lesson.id, targetCpm: target,
                                                                   sessions: sessions[lesson.id] ?? [],
                                                                   storedStars: record?.bestStars ?? 0,
                                                                   isPassed: record?.passedAt != nil)
                                let isUnlocked = course.isUnlocked(lesson.id, passed: passed, checkStars: checkStars)
                                // Проверку открытого этапа можно сдать, не пройдя уроки: экстерн (пока порог не взят).
                                let isExtern = CourseColumns.showsExternHint(
                                    edition: course.edition, isUnlocked: isUnlocked,
                                    isStageCheck: lesson.resolvedKind == .stageCheck,
                                    previousPassed: lessonIndex > 0 ? passed.contains(stage.lessons[lessonIndex - 1].id) : true,
                                    bestCheckStars: checkStars[lesson.id] ?? 0, gate: stage.gate)
                                // «Освежить»: возврат слабо сданного урока (издание 2); день зачёта — логический.
                                let refresh = RefreshMark(RefreshSchedule.state(
                                    lessonId: lesson.id,
                                    passedDay: record?.passedAt.map { LogicalDay.key(for: $0, dayStartHour: dayStartHour) },
                                    currentStars: overview.stars, sessions: sessions[lesson.id] ?? [],
                                    targetCpm: target, today: today))
                                CourseLessonRow(lesson: lesson, language: language, overview: overview,
                                                targetCpm: target, bestCpm: record?.bestCpm ?? 0, isPassed: record?.passedAt != nil,
                                                isUnlocked: isUnlocked, unit: unit,
                                                stepPlan: stepPlan(course, lesson, isExpanded: expanded.contains(lesson.id)),
                                                isExtern: isExtern, refresh: refresh,
                                                isExpanded: expandedBinding(lesson.id), start: start)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(stage.localizedTitle).foregroundStyle(.primary)
                                    Spacer()
                                    Text(CourseColumns.stageGoalText(stage, unit: unit)).foregroundStyle(.secondary)
                                    if course.edition >= 2 {
                                        Text(CourseColumns.gateText(stage)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .font(.callout.weight(.semibold))
                                if !course.isStageOpen(stageIndex, checkStars: checkStars) {
                                    Text(CourseColumns.opensWhenText(previousStage: stageIndex, gate: course.stages[stageIndex - 1].gate))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// План шагов раскрытого урока издания 2: названия шагов на карте — как в итоге раннера (у разминки проверки —
    /// «Разминка»). У свёрнутого урока и у издания 1 плана нет — названия по виду шага.
    private func stepPlan(_ course: Course, _ lesson: Lesson, isExpanded: Bool) -> [ResolvedStep] {
        guard isExpanded, course.edition >= 2, let context = course.context(for: lesson.id) else { return [] }
        return StepTemplates.resolve(context)
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
    /// План шагов урока (`StepTemplates.resolve`): названия строк шагов.
    var stepPlan: [ResolvedStep] = []
    /// Проверка этапа, которую можно сдать сразу (предыдущий урок этапа не засчитан): подсказка «экстерном».
    var isExtern = false
    /// Возврат слабо сданного урока (`RefreshMark`): значок, «трудный» и кнопка «Освежить»; `nil` — возврата нет.
    var refresh: RefreshMark? = nil
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
                        if let icon = LessonKindIcon.name(lesson.resolvedKind) {
                            Image(systemName: icon)
                                .foregroundStyle(.secondary)
                                .help(LessonKindIcon.help(lesson.resolvedKind) ?? "")
                        }
                        Text(lesson.localizedTitle)
                        if let refresh {
                            if refresh.isDue {
                                Image(systemName: RefreshMark.symbol)
                                    .foregroundStyle(Color.accentColor)
                                    .help(HelpText.refresh)
                            }
                            if refresh.isHard {
                                Text("трудный").font(.caption).foregroundStyle(.secondary)
                                    .help(HelpText.hardLesson)
                            }
                        }
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
                .modifier(ExternHelp(isExtern: isExtern))
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
            // Кнопка — отдельной строкой под уроком: колонки строки урока остаются на своих местах.
            if refresh?.isDue == true {
                Button {
                    start(LessonRun(language: language, lessonId: lesson.id, refresh: true))
                } label: {
                    Label("Освежить", systemImage: RefreshMark.symbol)
                }
                .buttonStyle(.borderless)
                .disabled(!isUnlocked)
                .help(HelpText.refresh)
                .padding(.leading, 32)
            }
            if isExpanded, !overview.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // Ключ строки — (номер, вид): у двух шагов с одинаковыми итогами id не совпадает.
                    ForEach(overview.steps, id: \.rowKey) { step in stepRow(step) }
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
        let columnId = CourseColumns.stepColumnId(step)
        return HStack(spacing: CourseColumns.spacing) {
            Text(CourseColumns.stepTitle(step, plan: stepPlan))
            Spacer()
            CourseColumn(id: "\(columnId).errors", text: CourseColumns.stepErrorsText(step.errorsInBest),
                         templates: CourseColumns.errorsTemplates)
                .foregroundStyle(Self.errorsColor(step))
            CourseColumn(id: "\(columnId).speed", text: CourseColumns.speedText(step.bestCpm, unit: unit),
                         templates: CourseColumns.speedTemplates)
                .foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                CourseColumns.trailingTemplate
                // Повтор — по номеру шага в плане; у шага без номера (только архивные уроки) кнопки нет.
                if let index = step.stepIndex {
                    Button {
                        start(LessonRun(language: language, lessonId: lesson.id, onlyStepIndex: index))
                    } label: {
                        Label("Пройти заново", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isUnlocked)
                }
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

/// Что карта курса показывает о возврате урока (`RefreshState`): значок и кнопка «Освежить» — когда возврат наступил,
/// подпись «трудный» — у «трудного» урока, пока он на расписании (в том числе до срока). Остальным — ничего.
struct RefreshMark: Equatable {
    static let symbol = "arrow.clockwise.circle"

    let isDue: Bool
    let isHard: Bool

    init(isDue: Bool, isHard: Bool) {
        self.isDue = isDue
        self.isHard = isHard
    }

    init?(_ state: RefreshState) {
        switch state {
        case .due(_, let hard): self.init(isDue: true, isHard: hard)
        case .waiting(_, true): self.init(isDue: false, isHard: true)
        case .waiting(_, false), .none, .closed: return nil
        }
    }
}

/// Значок вида урока перед названием на карте: «Повтор», «Ускорение», ступень скорости, проверка этапа.
/// У обычных уроков (`keys`, `rows`, `text`) значка нет.
enum LessonKindIcon {
    static func name(_ kind: LessonKind) -> String? {
        switch kind {
        case .review: "arrow.triangle.2.circlepath"
        case .speedup: "hare"
        case .tier: "speedometer"
        case .stageCheck: "flag.checkered"
        case .keys, .rows, .text: nil
        }
    }

    static func help(_ kind: LessonKind) -> String? {
        switch kind {
        case .review: String(localized: "Повтор: по вашим ошибкам")
        case .speedup: String(localized: "Ускорение: на сильных буквах")
        case .tier: String(localized: "Ступень скорости")
        case .stageCheck: String(localized: "Проверка этапа")
        case .keys, .rows, .text: nil
        }
    }
}

/// Тексты колонок карты курса и их шаблоны ширины (чистые функции: проверяются без отрисовки).
enum CourseColumns {
    static let spacing: CGFloat = 12
    static let chevronWidth: CGFloat = 18
    /// Шрифт цифровых колонок общий у строки урока и строк шагов: ширина шаблона зависит от шрифта.
    static let font = Font.callout

    /// Подсказка «экстерном» — у проверки открытого этапа издания 2, к которой не пройден предыдущий урок, и только
    /// пока лучшие звёзды проверки ниже порога этапа: у сданной проверки подсказка вводила бы в заблуждение.
    static func showsExternHint(edition: Int, isUnlocked: Bool, isStageCheck: Bool, previousPassed: Bool,
                                bestCheckStars: Int, gate: Int) -> Bool {
        edition >= 2 && isUnlocked && isStageCheck && !previousPassed && bestCheckStars < gate
    }

    /// «ошибок: 3»; у урока без попыток (`nil`) — пусто.
    static func errorsText(_ errors: Int?) -> String {
        guard let errors else { return "" }
        return String(localized: "ошибок: \(errors)")
    }

    /// «217 зн/мин»; без попыток (скорость 0) — пусто.
    static func speedText(_ cpm: Double, unit: SpeedUnit) -> String {
        cpm > 0 ? unit.format(cpm) : ""
    }

    /// Строка шага: «3. Слова» (`stepIndex + 1`); без номера — только название. Название — по плану урока
    /// (`plan`, `StepTemplates.resolve`), как в итоге раннера: у разминки проверки этапа — «Разминка».
    static func stepTitle(_ step: StepStat, plan: [ResolvedStep] = []) -> String {
        StepTitle.numbered(step.stepIndex, StepTitle.name(stepIndex: step.stepIndex, kind: step.kind, plan: plan))
    }

    /// Шаги издания 2 одного вида различаются номером: id колонок — `step.<номер>.<вид>` (без номера — `step.<вид>`).
    static func stepColumnId(_ step: StepStat) -> String {
        step.stepIndex.map { "step.\($0).\(step.kind.rawValue)" } ?? "step.\(step.kind.rawValue)"
    }

    /// Цель этапа в заголовке: «цель 60 → 80 зн/мин», если «до» ≠ «от», иначе «цель 80 зн/мин».
    static func stageGoalText(_ stage: Stage, unit: SpeedUnit) -> String {
        let end = unit.format(Double(stage.targetEnd))
        guard stage.targetEnd != stage.targetCpm else { return String(localized: "цель \(end)") }
        let start = String(unit.wholeValue(Double(stage.targetCpm)))
        return String(localized: "цель \(start) → \(end)")
    }

    /// Порог проверки этапа: «порог ★★».
    static func gateText(_ stage: Stage) -> String {
        let stars = String(repeating: "★", count: stage.gate)
        return String(localized: "порог \(stars)")
    }

    /// Под заголовком закрытого этапа: «Откроется, когда проверка этапа 1 наберёт ★★». `previousStage` — номер
    /// предыдущего этапа (с 1), `gate` — его порог.
    static func opensWhenText(previousStage: Int, gate: Int) -> String {
        let stars = String(repeating: "★", count: gate)
        return String(localized: "Откроется, когда проверка этапа \(previousStage) наберёт \(stars)")
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

/// Подсказка «экстерном» только у строки проверки открытого этапа; у остальных строк подсказки нет.
private struct ExternHelp: ViewModifier {
    let isExtern: Bool

    func body(content: Content) -> some View {
        if isExtern {
            content.help(Text("Проверку этапа можно сдать сразу — экстерном"))
        } else {
            content
        }
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

private struct StepRowKey: Hashable {
    let index: Int?
    let kind: ExerciseKind
}

private extension StepStat {
    /// Ключ строки шага на карте курса: номер и вид (как группы `LessonStepStats.summarize`).
    var rowKey: StepRowKey { StepRowKey(index: stepIndex, kind: kind) }
}
