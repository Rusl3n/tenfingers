import SwiftData
import SwiftUI
import TypingCore

/// Что нужно окну «Статистика урока»: урок, его цель и план шагов (названия — как на карте курса).
struct LessonStatsRequest: Identifiable, Equatable {
    let lessonId: String
    let language: Language
    let title: String
    let targetCpm: Int
    let plan: [ResolvedStep]

    var id: String { lessonId }

    /// По курсу и уроку; `nil` — урока в курсе нет.
    static func make(course: Course, lessonId: String, language: Language) -> LessonStatsRequest? {
        guard let lesson = course.lessons.first(where: { $0.id == lessonId }) else { return nil }
        let plan = course.edition >= 2 ? course.context(for: lessonId).map(StepTemplates.resolve) ?? [] : []
        return LessonStatsRequest(lessonId: lessonId, language: language, title: lesson.localizedTitle,
                                  targetCpm: course.targetCpm(for: lessonId) ?? 0, plan: plan)
    }
}

/// Читает из базы записи курса одного урока и считает `LessonHistory`.
@MainActor
struct LessonStatsLoader {
    let context: ModelContext

    func stats(for request: LessonStatsRequest) throws -> LessonHistoryStats {
        let code = request.language.rawValue
        let lessonId: String? = request.lessonId
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.language == code && $0.lessonId == lessonId })
        let sessions = try context.fetch(descriptor).compactMap(ProgressSnapshot.summary)
        return LessonHistory.make(lessonId: request.lessonId, sessions: sessions, targetCpm: request.targetCpm)
    }
}

/// Тексты и отбор данных окна — чистые функции.
enum LessonStatsText {
    /// На графике — не больше стольких последних проходов.
    static let chartLimit = 12

    static func chartPasses(_ passes: [LessonCheckPass]) -> [LessonCheckPass] { Array(passes.suffix(chartLimit)) }

    static func shortDate(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }

    /// «Проходов: 4 · 12 окт — 6 ноя»; без проходов — пусто.
    static func summaryLine(_ stats: LessonHistoryStats) -> String? {
        guard let first = stats.firstDate, let last = stats.lastDate else { return nil }
        let count = stats.passes.count
        let head = String(localized: "Проходов: \(count)")
        let (from, to) = (shortDate(first), shortDate(last))
        return from == to ? "\(head) · \(from)" : "\(head) · \(from) — \(to)"
    }

    /// «+57 %», «−10 %», «0 %».
    static func changeText(_ percent: Int) -> String {
        percent > 0 ? "+\(percent) %" : percent < 0 ? "−\(-percent) %" : "0 %"
    }
}

struct LessonStatsView: View {
    let request: LessonStatsRequest
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @State private var stats: LessonHistoryStats?

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Статистика урока · \(request.title)").font(.title2.bold())
                        if let stats, let line = LessonStatsText.summaryLine(stats) {
                            Text(line).foregroundStyle(.secondary)
                        }
                    }
                    if let stats {
                        if stats.passes.isEmpty {
                            Text("Проверку урока ещё не проходили").foregroundStyle(.secondary)
                        } else {
                            chart(stats.passes)
                            passes(stats.passes)
                        }
                        if !stats.steps.isEmpty { steps(stats.steps) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 420)
        .onExitCommand { dismiss() }
        .task { stats = try? LessonStatsLoader(context: modelContext).stats(for: request) }
    }

    private func chart(_ all: [LessonCheckPass]) -> some View {
        let shown = LessonStatsText.chartPasses(all)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Скорость проверки").font(.headline)
                if request.targetCpm > 0 {
                    let goal = unit.format(Double(request.targetCpm))
                    Text("цель \(goal)").font(.callout).foregroundStyle(.secondary)
                }
            }
            SpeedBars(values: shown.map { Optional($0.cpm) }, slow: [], unit: unit,
                      help: { "\(LessonStatsText.shortDate(shown[$0].date)): \(unit.format(shown[$0].cpm))" },
                      ends: shown.first.flatMap { first in
                          shown.last.map { (LessonStatsText.shortDate(first.date), LessonStatsText.shortDate($0.date)) }
                      },
                      height: 44)
        }
    }

    private func passes(_ all: [LessonCheckPass]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Проходы").font(.headline)
            ForEach(Array(all.reversed().enumerated()), id: \.offset) { _, pass in
                HStack(spacing: 16) {
                    Text(LessonStatsText.shortDate(pass.date)).frame(width: 70, alignment: .leading)
                    Text(unit.format(pass.cpm)).frame(width: 100, alignment: .leading)
                    Text(Formatting.errors(pass.errors)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    StarsView(count: pass.stars)
                }
                .font(.callout.monospacedDigit())
            }
        }
    }

    private func steps(_ all: [LessonStepProgress]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Шаги: первый → последний проход").font(.headline)
            ForEach(Array(all.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 16) {
                    Text(StepTitle.numbered(step.stepIndex,
                                            StepTitle.name(stepIndex: step.stepIndex, kind: step.kind, plan: request.plan)))
                        .frame(width: 200, alignment: .leading)
                    if let percent = step.changePercent {
                        Text("\(unit.wholeValue(step.first)) → \(unit.wholeValue(step.last))").frame(width: 100, alignment: .leading)
                        Text(LessonStatsText.changeText(percent))
                            .foregroundStyle(percent > 0 ? Color.green : percent < 0 ? Color.orange : Color.secondary)
                    } else {
                        Text(unit.format(step.last)).foregroundStyle(.secondary)
                    }
                }
                .font(.callout.monospacedDigit())
            }
        }
    }
}

/// Кнопка «Статистика урока»: на карте курса и на итоге урока.
struct LessonStatsButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label("Статистика урока", systemImage: LessonStatsButton.symbol) }
            .buttonStyle(.borderless)
    }
    nonisolated static let symbol = "chart.line.uptrend.xyaxis"
}
