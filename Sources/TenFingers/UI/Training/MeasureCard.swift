import Charts
import SwiftData
import SwiftUI
import TypingCore

/// Выбор варианта замера без языка (язык — текущий язык курса). Хранится в настройках как «60:plain».
struct MeasureChoice: Equatable, Sendable {
    var duration: MeasureDuration
    var kind: MeasureTextKind

    static let `default` = MeasureChoice(duration: .seconds(60), kind: .plain)

    var rawValue: String { "\(duration.rawValue):\(kind.rawValue)" }

    init(duration: MeasureDuration, kind: MeasureTextKind) {
        self.duration = duration
        self.kind = kind
    }

    /// Незнакомая строка — вариант по умолчанию.
    init(rawValue: String) {
        let parts = rawValue.split(separator: ":").map(String.init)
        if parts.count == 2, let d = MeasureDuration(rawValue: parts[0]), let k = MeasureTextKind(rawValue: parts[1]) {
            self.init(duration: d, kind: k)
        } else {
            self = .default
        }
    }

    func variant(language: Language) -> MeasureVariant {
        MeasureVariant(duration: duration, kind: kind, language: language)
    }
}

/// Открытые клавиши и пройденные заглавные: вход `MeasureText` (буквы, знаки, цифры открытых уроков обоих изданий курса).
struct MeasureKeys: Equatable {
    var open: Set<Character>
    var capitalsLearned: Bool

    static func combine(language: Language, courses: [Course], passedLessonIds: Set<String>,
                        adaptiveLetters: [Character]) -> MeasureKeys {
        var open = Set(adaptiveLetters)
        var capitals = false
        for course in courses {
            guard let last = course.lessons.last(where: { passedLessonIds.contains($0.id) }),
                  let lesson = course.context(for: last.id) else { continue }
            if lesson.capitals { capitals = true }
            for character in lesson.allowed where character != " " {
                if character.isLetter {
                    let lowered = Character(String(character).lowercased())
                    if language.letters.contains(lowered) { open.insert(lowered) }
                } else {
                    open.insert(character)
                }
            }
        }
        return MeasureKeys(open: open, capitalsLearned: capitals)
    }
}

extension StatsReader {
    func measureKeys(language: Language, course: Course?, legacy: Course?) throws -> MeasureKeys {
        let code = language.rawValue
        let progress = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let passed = Set(progress.filter { $0.passedAt != nil }.map(\.lessonId))
        return MeasureKeys.combine(
            language: language, courses: [course, legacy].compactMap { $0 }, passedLessonIds: passed,
            adaptiveLetters: AdaptiveTrainer(language: language).unlockedLetters(count: try unlockedCount(language: language)))
    }

    /// Замеры варианта от старого к новому: первый и последние 5.
    func measurements(variant: MeasureVariant) throws -> [MeasureHistoryEntry] {
        let language = variant.language.rawValue, duration = variant.duration.rawValue, kind = variant.kind.rawValue
        let rows = try context.fetch(FetchDescriptor<SpeedMeasurement>(predicate: #Predicate {
            $0.language == language && $0.duration == duration && $0.textKind == kind
        }, sortBy: [SortDescriptor(\.date)]))
        return MeasureHistory.shown(rows.map(MeasureHistoryEntry.init))
    }
}

/// Строка истории замеров.
struct MeasureHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let cpm: Double
    let accuracy: Double
    let chars: Int
    let errors: Int
    let hasReplay: Bool

    init(_ row: SpeedMeasurement) {
        id = row.id
        date = row.date
        cpm = row.cpm
        accuracy = row.accuracy
        chars = row.chars
        errors = row.errors
        hasReplay = row.replay != nil
    }

    init(id: UUID = UUID(), date: Date, cpm: Double, accuracy: Double = 1, chars: Int = 0, errors: Int = 0,
         hasReplay: Bool = false) {
        self.id = id
        self.date = date
        self.cpm = cpm
        self.accuracy = accuracy
        self.chars = chars
        self.errors = errors
        self.hasReplay = hasReplay
    }
}

enum MeasureHistory {
    /// Первый замер и последние 5, от старого к новому.
    static func shown(_ entries: [MeasureHistoryEntry]) -> [MeasureHistoryEntry] {
        MeasureRetention.keep(entries.sorted { $0.date < $1.date }, variant: { _ in .init(duration: .text300, kind: .plain, language: .ru) },
                              date: \.date)
    }

    /// Сравнение последнего замера списка с прежними.
    static func comparison(_ entries: [MeasureHistoryEntry]) -> MeasureComparison {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let current = sorted.last else { return MeasureComparison(toFirst: nil, toPrevious: nil) }
        return MeasureComparison.make(current: current.cpm, earlier: sorted.dropLast().map(\.cpm))
    }
}

/// Что показывает карточка «Замер скорости»: выбор, доступность видов и история выбранного варианта.
struct MeasureCardModel: Equatable {
    /// Выбор с учётом доступности: недоступный вид заменяется на «Простой».
    let choice: MeasureChoice
    let availability: [MeasureTextKind: MeasureAvailability]
    /// История выбранного варианта от старого к новому.
    let history: [MeasureHistoryEntry]

    var canStart: Bool { availability[choice.kind] == .available }
    var last: MeasureHistoryEntry? { history.last }

    static func make(stored: MeasureChoice, language: Language, keys: MeasureKeys,
                     entries: [MeasureHistoryEntry]) -> MeasureCardModel {
        var availability: [MeasureTextKind: MeasureAvailability] = [:]
        for kind in MeasureTextKind.allCases {
            availability[kind] = MeasureText.availability(kind: kind, language: language, open: keys.open,
                                                          capitalsLearned: keys.capitalsLearned)
        }
        var choice = stored
        if availability[choice.kind] != .available, availability[.plain] == .available { choice.kind = .plain }
        return MeasureCardModel(choice: choice, availability: availability, history: MeasureHistory.shown(entries))
    }
}

extension MeasureAvailability {
    /// Подсказка неактивной кнопки вида: что нужно пройти.
    var hint: String? {
        switch self {
        case .available: nil
        case .needsLetters: String(localized: "Сначала откройте буквы в курсе")
        case .needsCapitals: String(localized: "Нужно пройти урок с заглавными буквами")
        case .needsPunctuation: String(localized: "Нужно пройти урок со знаками препинания")
        case .needsDigits: String(localized: "Нужно пройти урок с цифрами")
        }
    }
}

extension MeasureDuration {
    var title: String {
        switch self {
        case .seconds(let s): String(localized: "\(s / 60) мин")
        case .text300: String(localized: "Текст 300 знаков")
        }
    }
}

extension MeasureTextKind {
    var title: String {
        switch self {
        case .plain: String(localized: "Простой")
        case .capsPunctuation: String(localized: "Заглавные и знаки")
        case .digits: String(localized: "С цифрами")
        }
    }
}

/// Карточка экрана «Тренировка»: последний результат, «Замерить», история варианта с графиком.
struct MeasureCard: View {
    let model: MeasureCardModel
    let unit: SpeedUnit
    let onChoose: (MeasureChoice) -> Void
    let start: () -> Void
    /// Повтор замера (экран повтора — задача 17): без обработчика кнопки «Повтор» нет.
    var onReplay: ((MeasureHistoryEntry) -> Void)? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Замер скорости").font(.headline)
                Spacer()
                Button("Замерить", action: start).buttonStyle(.borderedProminent).disabled(!model.canStart)
            }
            VStack(alignment: .leading, spacing: 6) {
                chips(MeasureDuration.allCases, selected: model.choice.duration, title: \.title) {
                    onChoose(MeasureChoice(duration: $0, kind: model.choice.kind))
                }
                chips(MeasureTextKind.allCases, selected: model.choice.kind, title: \.title,
                      hint: { model.availability[$0]?.hint }) {
                    onChoose(MeasureChoice(duration: model.choice.duration, kind: $0))
                }
            }
            if let last = model.last {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Последний замер").foregroundStyle(.secondary)
                    Text(unit.format(last.cpm)).font(.headline).monospacedDigit()
                    Text(Formatting.percent(last.accuracy)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
            } else {
                Text("Замеров этого варианта пока нет").font(.callout).foregroundStyle(.secondary)
            }
            if model.history.count > 1 { MeasureHistoryChart(entries: model.history, unit: unit, height: 56) }
            if !model.history.isEmpty { MeasureHistoryList(entries: model.history, unit: unit, onReplay: onReplay) }
        }
        .compactCard(palette)
    }

    private func chips<T: Hashable>(_ items: [T], selected: T, title: KeyPath<T, String>,
                                    hint: @escaping (T) -> String? = { _ in nil },
                                    choose: @escaping (T) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let reason = hint(item)
                Button(action: { choose(item) }) {
                    Text(item[keyPath: title])
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(item == selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(reason != nil)
                .help(reason ?? "")
                .accessibilityAddTraits(item == selected ? .isSelected : [])
            }
        }
    }
}

/// Маленький график скорости по замерам варианта (первый и последние 5).
struct MeasureHistoryChart: View {
    let entries: [MeasureHistoryEntry]
    let unit: SpeedUnit
    var height: CGFloat = 80

    var body: some View {
        Chart(Array(entries.enumerated()), id: \.element.id) { index, entry in
            LineMark(x: .value("№", index), y: .value("Скорость", speed(entry)))
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("№", index), y: .value("Скорость", speed(entry)))
                .foregroundStyle(Color.accentColor)
                .symbolSize(24)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: height)
    }

    private func speed(_ entry: MeasureHistoryEntry) -> Double { unit == .wpm ? entry.cpm / 5 : entry.cpm }
}

/// История варианта: первый замер и последние 5, новые сверху.
struct MeasureHistoryList: View {
    let entries: [MeasureHistoryEntry]
    let unit: SpeedUnit
    var onReplay: ((MeasureHistoryEntry) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(entries.enumerated().reversed()), id: \.element.id) { index, entry in
                HStack(spacing: 12) {
                    if index == 0 {
                        Label("Первый замер", systemImage: "flag").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    Spacer()
                    Text(unit.format(entry.cpm)).monospacedDigit()
                    Text(Formatting.percent(entry.accuracy)).monospacedDigit().foregroundStyle(.secondary)
                    if let onReplay, entry.hasReplay {
                        Button("Смотреть запись") { onReplay(entry) }.controlSize(.small)
                    }
                }
                .font(.callout)
            }
        }
    }
}
