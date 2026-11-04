import SwiftUI
import TypingCore

/// Итог захода для экрана: считается по самой игре, поэтому не зависит от успеха записи.
struct RhythmSummary: Equatable {
    let mode: RhythmNoteMode
    let level: RhythmLevelID
    let cleared: Bool
    let score: Int
    let accuracy: Double
    let maxCombo: Int
    let grade: RhythmGrade
    /// perfect, good, early, late, wrongKey, skipped.
    let counts: [String: Int]
    let isNewRecord: Bool
    let report: RhythmReport

    /// Бесконечный режим: у него нет оценки-буквы, в шапке — «Продержались» и «Темп» из разбора.
    var isEndless: Bool { level == .endless }
    var survivedSeconds: Double? { report.survivedSeconds }
    var peakNotesPerMinute: Int? { report.peakNotesPerMinute }

    /// Рекорд обычного уровня — только у пройденного трека и только если очков больше прежних (первый пройденный —
    /// тоже рекорд). У бесконечного — любой заход, в котором продержались дольше прежнего лучшего (по набору нот и
    /// языку; `previousEndless`); заход, не продержавшийся и секунды, рекордом не считается.
    static func make(game: RhythmGame, chart: RhythmChart, run: RhythmRun, previous: RhythmRecords,
                     previousEndless: RhythmEndlessRecords = .empty) -> RhythmSummary {
        let report = RhythmReport.make(game: game, chart: chart)
        let cleared = game.state == .cleared
        let isNewRecord: Bool
        if run.level == .endless {
            let seconds = report.survivedSeconds ?? 0
            isNewRecord = seconds > 0 && RhythmEndlessRecords.isNewBest(seconds: seconds, previous: previousEndless)
        } else {
            isNewRecord = cleared && RhythmRecords.isNewBest(score: game.score, previous: previous)
        }
        return RhythmSummary(mode: run.mode, level: run.level, cleared: cleared, score: game.score,
                             accuracy: report.accuracy, maxCombo: game.maxCombo, grade: report.grade,
                             counts: report.counts, isNewRecord: isNewRecord, report: report)
    }

    /// Слабые буквы разбора (до трёх, не меньше трёх нот; пробела нет) для «Потренировать слабые».
    var weakLetters: [Character] { report.weak.compactMap { $0.character.first } }
}

/// Подписи разбора захода.
enum RhythmReportText {
    /// Сдвиг меньше стольких мс (после округления) — «в такт».
    static let onBeatMs = 10

    /// «рано/поздно на N мс» по знаку среднего сдвига (отрицательный — рано); у самого такта — «в такт».
    static func timing(_ meanOffsetMs: Double) -> String {
        let ms = Int(abs(meanOffsetMs).rounded())
        if ms < onBeatMs { return String(localized: "в такт") }
        return meanOffsetMs < 0 ? String(localized: "рано на \(ms) мс") : String(localized: "поздно на \(ms) мс")
    }

    /// «нажато X вместо Y ×N».
    static func confusion(_ line: RhythmReport.Confusion) -> String {
        let pressed = line.pressed.uppercased(), expected = line.expected.uppercased(), count = line.count
        return String(localized: "нажато \(pressed) вместо \(expected) ×\(count)")
    }
}

/// Названия режимов, уровней и стилей для экранов игры.
extension RhythmNoteMode {
    var title: String {
        switch self {
        case .open: String(localized: "Открытые буквы")
        case .closed: String(localized: "Закрытые буквы")
        case .problem: String(localized: "Проблемные")
        case .words: String(localized: "Слова")
        }
    }
}

extension RhythmLevelID {
    var title: String {
        switch self {
        case .easy: String(localized: "Лёгкий")
        case .medium: String(localized: "Средний")
        case .hard: String(localized: "Сложный")
        case .expert: String(localized: "Эксперт")
        case .personal: String(localized: "Под меня")
        case .endless: String(localized: "Бесконечный")
        }
    }
}

extension RhythmBeatStyle {
    var title: String {
        switch self {
        case .pulse: String(localized: "Пульс")
        case .groove: String(localized: "Грув")
        case .drive: String(localized: "Драйв")
        }
    }
}

extension RhythmGrade {
    var color: Color {
        switch self {
        case .s: Color(red: 0.95, green: 0.72, blue: 0.15)
        case .a: Color(red: 0.25, green: 0.72, blue: 0.35)
        case .b: Color(red: 0.22, green: 0.54, blue: 0.87)
        case .c: Color(red: 0.95, green: 0.62, blue: 0.15)
        case .d: Color(red: 0.88, green: 0.27, blue: 0.27)
        }
    }
}

/// Вкладки разбора на итогах захода.
enum RhythmResultTab: String, CaseIterable, Identifiable, PageTab {
    case errors, letters, confusions, fingers

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .errors: "xmark.circle"
        case .letters: "textformat"
        case .confusions: "arrow.left.arrow.right"
        case .fingers: "hand.raised"
        }
    }

    var title: String {
        switch self {
        case .errors: String(localized: "Ошибки")
        case .letters: String(localized: "Буквы")
        case .confusions: String(localized: "Путаницы")
        case .fingers: String(localized: "Пальцы")
        }
    }
}

/// Итоги захода: оценка буквой, очки, точность, комбо, кнопки и новый рекорд — сверху; разбор (ошибки, сильные
/// и слабые буквы, путаницы, пальцы) — во вкладках, как на «Главной», чтобы всё помещалось без прокрутки.
/// Разбор есть и у проигранного захода.
struct RhythmResultView: View {
    let summary: RhythmSummary
    /// Ачивки и полный огонь этого сохранения (карточки, как на итогах упражнений).
    var newAchievements: [EarnedCard] = []
    var fullFlame: FullFlame?
    let onAgain: () -> Void
    let onBack: () -> Void
    /// «Потренировать слабые»: слабые буквы захода уходят в фокус тренировки слабых мест.
    var onTrainWeak: ([Character]) -> Void = { _ in }

    @State private var tab: RhythmResultTab = .errors

    /// Ошибки захода: не та буква, рано, поздно, пропуск.
    private static let errorRows: [(key: String, title: String)] = [
        ("wrongKey", String(localized: "Не та буква")), ("early", String(localized: "Рано")),
        ("late", String(localized: "Поздно")), ("skipped", String(localized: "Пропуск")),
    ]

    /// Вкладка есть, только когда ей есть что показать; «Ошибки» — всегда.
    private var tabs: [RhythmResultTab] {
        RhythmResultTab.allCases.filter {
            switch $0 {
            case .errors: true
            case .letters: !summary.report.strong.isEmpty || !summary.report.weak.isEmpty
            case .confusions: !summary.report.confusions.isEmpty
            case .fingers: !fingerRows.isEmpty
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if summary.isNewRecord {
                    Label("Новый рекорд!", systemImage: "trophy.fill").font(.headline).foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    Button("Назад", action: onBack)
                    if !summary.weakLetters.isEmpty {
                        Button("Потренировать слабые") { onTrainWeak(summary.weakLetters) }
                    }
                    Button("Ещё раз", action: onAgain)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                HomeTabsSection(tabs: tabs, selection: $tab) {
                    switch tab {
                    case .errors: errorsTab
                    case .letters: lettersTab
                    case .confusions: confusionsTab
                    case .fingers: fingersTab
                    }
                }
                .frame(maxWidth: 640)
                NewAchievementCards(achievements: newAchievements, fullFlame: fullFlame)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    /// Заголовок итога: у обычного уровня — «Трек пройден»/«Не пройден», у бесконечного — «Трек пройден»/«Игра окончена».
    private var title: Text {
        if summary.cleared { return Text("Трек пройден") }
        return summary.isEndless ? Text("Игра окончена") : Text("Не пройден")
    }

    /// Шапка: оценка слева (у бесконечного режима её нет), справа итог, режим и все числа захода в одну строку.
    private var header: some View {
        HStack(spacing: 24) {
            if !summary.isEndless {
                Text(summary.grade.rawValue)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(summary.grade.color)
                    .frame(width: 92, height: 92)
                    .background(summary.grade.color.opacity(0.15), in: Circle())
                    .accessibilityLabel(Text("Оценка \(summary.grade.rawValue)"))
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                    .font(.title.bold())
                    // Конец бесконечного захода по здоровью — обычный финал, а не провал: без красного.
                    .foregroundStyle(summary.cleared || summary.isEndless ? Color.primary
                                     : RhythmJudgement.miss(.skipped).color)
                Text("\(summary.mode.title) · \(summary.level.title)").foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    if summary.isEndless {
                        if let seconds = summary.survivedSeconds {
                            metric(String(localized: "Продержались"), Formatting.minutesSeconds(seconds))
                        }
                        if let tempo = summary.peakNotesPerMinute {
                            metric(String(localized: "Темп"), String(localized: "\(tempo) нот/мин"))
                        }
                    }
                    metric(String(localized: "Очки"), "\(summary.score)")
                    metric(String(localized: "Точность"), Formatting.percent(summary.accuracy))
                    metric(String(localized: "Макс. комбо"), "\(summary.maxCombo)")
                    metric(String(localized: "Точно"), "\(summary.counts["perfect"] ?? 0)")
                    metric(String(localized: "Хорошо"), "\(summary.counts["good"] ?? 0)")
                }
            }
        }
    }

    private var errorsTab: some View {
        HStack(spacing: 32) {
            ForEach(Self.errorRows, id: \.key) { row in
                metric(row.title, "\(summary.counts[row.key] ?? 0)")
            }
        }
    }

    /// Сильные и слабые буквы рядом, по колонке на каждые.
    private var lettersTab: some View {
        HStack(alignment: .top, spacing: 32) {
            letterColumn("Сильные", lines: summary.report.strong)
            letterColumn("Слабые", lines: summary.report.weak)
        }
    }

    @ViewBuilder private func letterColumn(_ title: LocalizedStringKey, lines: [RhythmReport.LetterLine]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(lines, id: \.character) { line in
                    HStack(spacing: 12) {
                        Text(line.character.uppercased()).font(.title3.bold().monospaced()).frame(width: 28)
                        Text(Formatting.percent(line.accuracy)).monospacedDigit()
                        Spacer(minLength: 12)
                        Text(RhythmReportText.timing(line.meanOffsetMs)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var confusionsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(summary.report.confusions.enumerated()), id: \.offset) { _, line in
                Text(RhythmReportText.confusion(line)).monospacedDigit()
            }
        }
    }

    /// Строка пальца: сколько нот, доли сегментов полосы и доля попаданий.
    private struct FingerRow {
        let finger: Finger
        let notes: Int
        let segments: [(fraction: Double, color: Color)]
        let hitRate: Double
    }

    /// Сегменты полосы пальца слева направо — цветами оценок на поле: точно, хорошо, рано/поздно, мимо.
    private static let fingerSegments: [(keys: [String], judgement: RhythmJudgement)] = [
        (["perfect"], .perfect), (["good"], .good), (["early", "late"], .early), (["wrongKey", "skipped"], .miss(.skipped)),
    ]

    /// Пальцы в порядке слева направо; без нот на дорожке палец не показывается.
    private var fingerRows: [FingerRow] {
        RhythmLane.fingerOrder.compactMap { finger in
            guard let counts = summary.report.fingerCounts?[finger.rawValue] else { return nil }
            let notes = counts.values.reduce(0, +)
            guard notes > 0 else { return nil }
            let segments = Self.fingerSegments.map { segment in
                (fraction: Double(segment.keys.reduce(0) { $0 + (counts[$1] ?? 0) }) / Double(notes),
                 color: segment.judgement.color)
            }
            let misses = (counts["wrongKey"] ?? 0) + (counts["skipped"] ?? 0)
            return FingerRow(finger: finger, notes: notes, segments: segments,
                             hitRate: Double(notes - misses) / Double(notes))
        }
    }

    /// Полоса пальца разбита по оценкам (легенда сверху), справа — доля попаданий и промахов.
    private var fingersTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(Array(Self.fingerSegments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.judgement.color).frame(width: 8, height: 8)
                        Text(verbatim: segment.keys.count > 1 ? String(localized: "Рано и поздно") : segment.judgement.title)
                    }
                }
                Spacer(minLength: 12)
                Text("Попадания").frame(width: 92, alignment: .trailing)
                Text("Мимо").frame(width: 56, alignment: .trailing)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            ForEach(fingerRows, id: \.finger) { row in
                HStack(spacing: 10) {
                    Text(row.finger.displayName).lineLimit(1).frame(width: 150, alignment: .leading)
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(Array(row.segments.enumerated()), id: \.offset) { _, segment in
                                Rectangle().fill(segment.color).frame(width: geometry.size.width * segment.fraction)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    Text(Formatting.percent(row.hitRate)).monospacedDigit().lineLimit(1).fixedSize()
                        .frame(minWidth: 92, alignment: .trailing)
                    Text(Formatting.percent(1 - row.hitRate)).monospacedDigit().lineLimit(1)
                        .foregroundStyle(row.hitRate < 1 ? RhythmJudgement.miss(.skipped).color : .secondary)
                        .fixedSize().frame(minWidth: 56, alignment: .trailing)
                }
                .help(Text("Нот: \(row.notes)"))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.callout).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3.bold()).monospacedDigit()
        }
    }
}
