import SwiftUI
import TypingCore

/// Итог повтора одного шага урока: точность, ошибки, скорость и «Лучший результат!», если стало лучше.
struct StepResultView: View {
    /// Заголовок: шаг с номером в плане урока («4. Слова», `StepTitle.numbered`).
    let title: String
    let summary: ExerciseSummary
    let errors: Int
    let improved: Bool
    /// Звёзды, если повторяли проверочный шаг.
    let stars: Int?
    /// Звёзды урока, если этот повтор шага их увеличил (вернулась пятая).
    var lessonStarsGained: Int?
    /// Шаги урока: от них зависит пятая звезда и подсказка к ней.
    let steps: [StepStat]
    /// Цель этапа урока: для объяснения звёзд и подсказки до следующей звезды.
    let targetCpm: Int
    /// Ачивки, полученные в сохранении этого шага.
    var newAchievements: [EarnedCard] = []
    /// Полный огонь в сохранении этого шага.
    var fullFlame: FullFlame?
    /// Проверка засчитала последний урок этапа или курса (`ShareEvent.stepCompletion`).
    var completion: ShareEvent?
    /// Вместе с карточкой курса — «Сертификат» (`ShareEvent.certificateOffer`): вторая строка «Поделиться».
    var certificate: ShareEvent? = nil
    /// Итог повтора проверки «Ускорения» против ориентира до попытки: строка под метриками.
    var speedup: SpeedupReference.Outcome?
    /// Разбор шага (§2.2): мини-график и строки; `nil` — разбора нет.
    var review: StepReviewScreen? = nil
    /// Проверка этапа засчитана, но порог не взят (`GateHint.text`): строка под звёздами, как на итоге урока.
    var gateText: String? = nil
    /// «Потренировать слабые буквы» — «Повтор» этапа (`GateHint.reviewLesson`); `nil` — кнопки нет.
    var onPracticeWeak: (() -> Void)? = nil
    let onRetry: () -> Void
    let onExit: () -> Void

    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.largeTitle.bold())
            if improved {
                Label("Лучший результат!", systemImage: "trophy.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }
            if let stars {
                StarsView(count: stars, size: 34)
                    .overlay(alignment: .trailing) {
                        StarsHelpButton(targetCpm: targetCpm, unit: unit, size: 17).offset(x: 30)
                    }
            }
            if let gateText {
                Text(gateText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }
            if let lessonStarsGained {
                HStack(spacing: 10) {
                    Text("Звёзды урока").font(.title3)
                    StarsView(count: lessonStarsGained, size: 26)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Звёзды урока: \(lessonStarsGained)"))
            }
            HStack(spacing: 32) {
                metric("Ошибки", "\(errors)")
                metric("Скорость", unit.format(summary.cpm))
            }
            if let speedup { SpeedupOutcomeLine(outcome: speedup, unit: unit) }
            if let review {
                SpeedSegmentsChart(screen: review, unit: unit)
                StepReviewLines(screen: review, hidesLetters: !summary.topErrors.isEmpty)
            }
            if stars != nil {
                NextStarHintView(cpm: summary.cpm, accuracy: summary.accuracy, errors: summary.errors,
                                 chars: summary.chars, targetCpm: targetCpm, steps: steps, unit: unit)
            }
            NewAchievementCards(achievements: newAchievements, fullFlame: fullFlame)
            if let completion { CompletionShareLine(event: completion) }
            if let certificate { CompletionShareLine(event: certificate) }
            if !summary.topErrors.isEmpty {
                HStack(spacing: 12) {
                    ForEach(summary.topErrors, id: \.self) { error in
                        Text("\(error.character) × \(error.count)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            if gateText != nil, let onPracticeWeak {
                Button("Потренировать слабые буквы", action: onPracticeWeak)
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 12) {
                Button("К курсу", action: onExit)
                Button("Ещё раз", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}

/// Название шага с номером в плане урока: «3. Слова». Номер — с единицы (`stepIndex + 1`): в уроках издания 2
/// виды шагов повторяются; без номера (записи до 6a) — только название.
enum StepTitle {
    static func numbered(_ stepIndex: Int?, _ title: String) -> String {
        guard let stepIndex else { return title }
        return String(localized: "\(stepIndex + 1). \(title)")
    }

    /// Название шага по плану урока (`StepTemplates.resolve`) — то же, что в раннере (`ExerciseSpec.localizedTitle`):
    /// у разминки проверки этапа — «Разминка», а не название вида. Шага с таким номером и видом в плане нет
    /// (история другой структуры, записи без номера) — название вида.
    static func name(stepIndex: Int?, kind: ExerciseKind, plan: [ResolvedStep]) -> String {
        guard let stepIndex, plan.indices.contains(stepIndex), plan[stepIndex].kind == kind else {
            return kind.localizedTitle
        }
        return ExerciseSpec(id: stepIndex, kind: kind, title: plan[stepIndex].title, text: "").localizedTitle
    }
}
