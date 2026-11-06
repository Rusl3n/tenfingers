import SwiftData
import SwiftUI
import TypingCore

/// Выбор слабых мест: только открытые пользователем буквы (пробел и знаки препинания в словах не потренировать,
/// а неоткрытые буквы ещё рано).
enum WeakSpotsFocus {
    /// `focus` (буквы захода игры «Ритм») — ключи фокуса, которые открыты; нет такой или пусто — обычный расчёт.
    static func keys(_ stats: [Character: KeyMastery], letters: Set<Character>, thresholdMs: Double,
                     focus: [Character]? = nil) -> [Character] {
        if let focus {
            let open = focus.filter(letters.contains)
            if !open.isEmpty { return open }
        }
        return WeakSpots.worstKeys(stats.filter { letters.contains($0.key) }, thresholdMs: thresholdMs)
    }

    static func bigrams(_ stats: [String: KeyMastery], letters: Set<Character>, thresholdMs: Double) -> [String] {
        WeakSpots.worstBigrams(stats.filter { $0.key.allSatisfy(letters.contains) }, thresholdMs: thresholdMs)
    }
}

/// Всё, что показывает экран «Тренировка», собранное из статистики.
struct TrainingSnapshot: Equatable {
    struct Letter: Identifiable, Equatable {
        let character: Character
        let progress: Double
        let isFocus: Bool
        var id: Character { character }
    }

    let letters: [Letter]
    let nextLetter: Character?
    let weakKeys: [Character]
    let weakBigrams: [String]
    /// Открыто слишком мало букв, чтобы собрать текст для слабых мест.
    let needsMoreLetters: Bool

    var hasWeakSpots: Bool { !weakKeys.isEmpty || !weakBigrams.isEmpty }
    var canStartWeakSpots: Bool { hasWeakSpots && !needsMoreLetters }

    static func make(language: Language, unlockedCount: Int, keyMastery: [Character: KeyMastery],
                     bigramMastery: [String: KeyMastery], targetCpm: Double,
                     openLetters: Set<Character>) -> TrainingSnapshot {
        let trainer = AdaptiveTrainer(language: language, targetCpm: targetCpm)
        let unlocked = trainer.unlockedLetters(count: unlockedCount)
        let focus = trainer.focusLetter(unlocked: unlocked, stats: keyMastery)
        let order = language.adaptiveOrder
        return TrainingSnapshot(
            letters: unlocked.map {
                Letter(character: $0, progress: trainer.masteryProgress(keyMastery[$0]), isFocus: $0 == focus)
            },
            nextLetter: unlocked.count < order.count ? order[unlocked.count] : nil,
            weakKeys: WeakSpotsFocus.keys(keyMastery, letters: openLetters, thresholdMs: trainer.thresholdMs),
            weakBigrams: WeakSpotsFocus.bigrams(bigramMastery, letters: openLetters, thresholdMs: trainer.thresholdMs),
            needsMoreLetters: openLetters.count < OpenLetters.minimumForWeakSpots)
    }
}

struct TrainingView: View {
    let start: (RunKind) -> Void
    /// Повтор замера по `SpeedMeasurement.id` (лист открывает `RootView`).
    var replay: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(ContentLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(KeyboardLayoutService.self) private var layout
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.trainingLetters) private var trainingLetters = SettingsDefault.trainingLetters
    @AppStorage(SettingsKey.measureChoice) private var measureChoice = SettingsDefault.measureChoice
    @State private var snapshot: TrainingSnapshot?
    @State private var errorWords = ErrorWordsCardModel(listCount: 0, eligibleCount: 0, fixed: 0)
    @State private var fingers = FingerCardModel(cells: [])
    @State private var measure: MeasureCardModel?
    /// Букв пальцев нет ни в истории клавиш, ни в раскладке: кнопок занятий нет, нужна раскладка языка.
    @State private var fingerLettersMissing = false

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }
    private var lettersSetting: TrainingLetters { TrainingLetters(rawValue: trainingLetters) ?? .open }
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Тренировка: \(language.displayName)").font(.title.bold())
                if let snapshot {
                    adaptiveCard(snapshot)
                    weakSpotsCard(snapshot)
                    ErrorWordsCard(model: errorWords,
                                   start: { start(.errorWords(TrainingRun(language: language))) })
                    if let measure {
                        MeasureCard(model: measure, unit: unit,
                                    onChoose: { measureChoice = $0.rawValue },
                                    start: { start(.measure(MeasureRun(variant: measure.choice.variant(language: language)))) },
                                    onReplay: { replay($0.id) })
                    }
                    FingerCard(model: fingers, unit: unit,
                               layoutPrompt: fingerLettersMissing && layout.snapshot.language != language
                                   ? LayoutPrompt.switchTo(language) : nil,
                               start: { start(.finger(FingerRun(language: language, finger: $0, drill: $1))) })
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: reload)
        .onChange(of: activeLanguage) { reload() }
        .onChange(of: targetCpm) { reload() }
        .onChange(of: trainingLetters) { reload() }
        .onChange(of: measureChoice) { reload() }
        .onChange(of: layout.snapshot) { reload() }
    }

    private func reload() {
        let reader = StatsReader(context: modelContext)
        let unlockedCount = (try? reader.unlockedCount(language: language)) ?? AdaptiveTrainer.initialLetters
        let openLetters = (try? reader.openLetters(language: language, course: library.courses[language],
                                                   legacy: library.legacyCourses[language]))
            ?? Set(AdaptiveTrainer(language: language).unlockedLetters(count: unlockedCount))
        snapshot = TrainingSnapshot.make(
            language: language,
            unlockedCount: unlockedCount,
            keyMastery: (try? reader.keyMastery(language: language)) ?? [:],
            bigramMastery: (try? reader.bigramMastery(language: language)) ?? [:],
            targetCpm: Double(targetCpm),
            openLetters: lettersSetting.letters(open: openLetters, language: language))
        errorWords = ErrorWordsCardModel.make(
            entries: (try? reader.errorWords(language: language)) ?? [], fixed: (try? reader.fixedWords()) ?? 0,
            allowed: lettersSetting.letters(open: openLetters, language: language))
        loadMeasure(reader)
        let thresholdMs = AdaptiveTrainer(language: language, targetCpm: Double(targetCpm)).thresholdMs
        let fingerOf = (try? reader.fingerLetters(language: language, layout: layout.fingerOf(language: language)))
            ?? layout.fingerOf(language: language)
        fingerLettersMissing = fingerOf.isEmpty
        fingers = FingerCardModel.make(
            reports: (try? reader.fingerReports(language: language, fingerOf: fingerOf, thresholdMs: thresholdMs)) ?? [],
            // Кнопка занятия — только у пальца с открытой буквой: иначе занятия нет.
            fingerOf: fingerOf.filter { openLetters.contains($0.key) })
    }

    private func loadMeasure(_ reader: StatsReader) {
        let keys = (try? reader.measureKeys(language: language, course: library.courses[language],
                                            legacy: library.legacyCourses[language]))
            ?? MeasureKeys(open: [], capitalsLearned: false)
        let stored = MeasureChoice(rawValue: measureChoice)
        let model = MeasureCardModel.make(stored: stored, language: language, keys: keys, entries: [])
        let entries = (try? reader.measurements(variant: model.choice.variant(language: language))) ?? []
        measure = MeasureCardModel.make(stored: stored, language: language, keys: keys, entries: entries)
    }

    private func adaptiveCard(_ snapshot: TrainingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Адаптивная тренировка").font(.headline)
                InfoButton(text: HelpText.trainingLetters)
                Spacer()
                Button("Начать") { start(.adaptive(TrainingRun(language: language))) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(snapshot.letters) { letterBadge($0) }
            }
            HStack(spacing: 16) {
                if let next = snapshot.nextLetter {
                    let name = String(next)
                    Text("Следующая буква: \(name)")
                } else {
                    Text("Все буквы открыты")
                }
                let goal = unit.format(Double(targetCpm))
                Text("Цель: \(goal)").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .compactCard(palette)
    }

    private func letterBadge(_ letter: TrainingSnapshot.Letter) -> some View {
        let accent = letter.isFocus ? Color.accentColor : Color.green
        return ZStack {
            Circle().fill(letter.isFocus ? Color.accentColor.opacity(0.18) : Color.clear)
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: letter.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(letter.character))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(letter.isFocus ? Color.accentColor : Color.primary)
        }
        .frame(width: 32, height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(letter.character))
        .accessibilityValue(Formatting.percent(letter.progress))
    }

    private func weakSpotsCard(_ snapshot: TrainingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Слабые места").font(.headline)
                InfoButton(text: HelpText.weakSpots)
                Spacer()
                Button("5 минут на слабые места") { start(.weakSpots(TrainingRun(language: language))) }
                    .disabled(!snapshot.canStartWeakSpots)
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                weakColumn("Клавиши", items: snapshot.weakKeys.map { String($0) })
                weakColumn("Сочетания", items: snapshot.weakBigrams)
            }
            if snapshot.needsMoreLetters {
                Text("Сначала откройте больше букв в курсе или тренировке")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .compactCard(palette)
    }

    private func weakColumn(_ title: LocalizedStringKey, items: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Нужно больше данных").foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .font(.callout)
    }
}

extension View {
    /// Карточка экрана «Тренировка» в сжатом виде: меньше полей, чтобы страница помещалась по высоте.
    func compactCard(_ palette: Palette) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
    }
}
