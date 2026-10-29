import SwiftUI
import TypingCore

/// Тексты объяснения звёзд и подсказки «до следующей звезды». Пороги берутся из `LessonScoring`,
/// поэтому объяснение не может разойтись с подсчётом.
enum StarHintText {
    /// Скорость порога: цель × множитель, округлённая вверх (названная скорость точно даёт звезду).
    static func speedGoal(targetCpm: Int, factor: Double, unit: SpeedUnit) -> String {
        unit.format(Double(targetCpm) * factor, rounding: .up)
    }

    /// Порог ошибок на 100 знаков: «не больше 3 ошибок на 100 знаков», при доле меньше 1% —
    /// «не больше 1 ошибки на 200 знаков», при 100% — «без ошибок».
    static func errorsRule(accuracy: Double) -> String {
        let rate = 1 - accuracy
        guard rate > LessonScoring.accuracyTolerance else { return String(localized: "без ошибок") }
        let perHundred = rate * 100 + LessonScoring.accuracyTolerance
        // 0,995 → меньше одной ошибки на 100 знаков: «1 на 200».
        let (count, chars) = perHundred >= 1 ? (Int(perHundred.rounded(.down)), 100) : (1, Int((1 / rate).rounded()))
        let atMost = Formatting.atMostErrors(count)
        return String(localized: "\(atMost) на \(chars) знаков")
    }

    /// «урок засчитан: не больше 4 ошибок на 100 знаков».
    static func passRule() -> String {
        let errors = errorsRule(accuracy: LessonScoring.passAccuracy)
        return String(localized: "урок засчитан: \(errors)")
    }

    /// Строка порога для попапа; без цели (`targetCpm` ≤ 0, урока нет в курсе) — без числа скорости.
    /// Множитель пишется по языку интерфейса (`locale` по умолчанию — из набора ресурсов `bundle`), а не по региону системы.
    static func rule(_ threshold: StarThreshold, targetCpm: Int, unit: SpeedUnit, locale: Locale? = nil,
                     bundle: Bundle = .main) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let errors = errorsRule(accuracy: threshold.accuracy)
        let goal = speedGoal(targetCpm: targetCpm, factor: threshold.speedFactor, unit: unit)
        if threshold.speedFactor == 1 {
            guard targetCpm > 0 else { return String(localized: "скорость не ниже цели, \(errors)") }
            return String(localized: "скорость не ниже цели (\(goal)), \(errors)")
        }
        let factor = threshold.speedFactor.formatted(.number.locale(locale))
        guard targetCpm > 0 else { return String(localized: "скорость от \(factor) × цели, \(errors)") }
        return String(localized: "скорость от \(factor) × цели (\(goal)), \(errors)")
    }

    /// ★★★★★ для попапа: условие проверки и чистота остальных шагов — в ошибках на 100 знаков.
    /// «скорость от 1,5 × цели (90 зн/мин), без ошибок на проверке, а на остальных шагах — не больше 2 ошибок на 100 знаков».
    static func topRule(_ threshold: StarThreshold, targetCpm: Int, unit: SpeedUnit, locale: Locale? = nil,
                        bundle: Bundle = .main) -> String {
        let check = rule(threshold, targetCpm: targetCpm, unit: unit, locale: locale, bundle: bundle)
        let steps = errorsRule(accuracy: LessonScoring.cleanLessonStepAccuracy)
        return String(localized: "\(check) на проверке, а на остальных шагах — \(steps)")
    }

    /// «пройдите шаг 4 «Слова» не больше чем с 2 ошибками на 100 знаков»: что сделать с шагом, мешающим ★★★★★.
    /// Номер — с единицы (`stepIndex + 1`): в уроках издания 2 виды шагов повторяются; без номера — только название.
    static func cleanStep(_ step: StepStat) -> String {
        let chars = 100
        let allowed = LessonScoring.allowedErrors(chars: chars, accuracy: LessonScoring.cleanLessonStepAccuracy)
        let limit = Formatting.withAtMostErrors(allowed)
        let title = step.kind.localizedTitle
        guard let index = step.stepIndex else {
            return String(localized: "пройдите шаг «\(title)» \(limit) на \(chars) знаков")
        }
        return String(localized: "пройдите шаг \(index + 1) «\(title)» \(limit) на \(chars) знаков")
    }

    /// «скорость от 78 зн/мин (у вас 70 зн/мин) и не больше 1 ошибки (у вас 3)»; пусто, если условий нет.
    /// Порог скорости округляется вверх, результат — вниз: недостающее не выглядит достигнутым.
    /// `blockingStep` — шаг, мешающий ★★★★★: последним условием.
    static func requirements(needCpm: Double?, maxErrors: Int?, cpm: Double, errors: Int, unit: SpeedUnit,
                             blockingStep: StepStat? = nil) -> String {
        var parts: [String] = []
        if let needCpm, needCpm > 0 {
            let need = unit.format(needCpm, rounding: .up), have = unit.format(cpm, rounding: .down)
            parts.append(String(localized: "скорость от \(need) (у вас \(have))"))
        }
        if let maxErrors {
            if maxErrors > 0 {
                let atMost = Formatting.atMostErrors(maxErrors)
                parts.append(String(localized: "\(atMost) (у вас \(errors))"))
            } else {
                parts.append(String(localized: "без ошибок (у вас \(errors))"))
            }
        }
        if let blockingStep { parts.append(cleanStep(blockingStep)) }
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default:
            let head = parts.dropLast().joined(separator: ", "), last = parts[parts.count - 1]
            return String(localized: "\(head) и \(last)")
        }
    }
}

/// Попап «Как считаются звёзды»: что влияет на звёзды и пороги для цели этапа `targetCpm`.
struct StarsExplanation: View {
    let targetCpm: Int
    let unit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Как считаются звёзды").font(.headline)
            Text("Звёзды за урок ставятся по проверочному тексту — последнему шагу урока. Остальные шаги — тренировка: они влияют только на пятую звезду и показывают, где ошибки.")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    StarsView(count: 1, size: 11)
                    Text(verbatim: StarHintText.passRule())
                }
                ForEach(LessonScoring.thresholds, id: \.stars) { threshold in
                    GridRow {
                        StarsView(count: threshold.stars, size: 11)
                        Text(verbatim: threshold.stars == LessonScoring.maxStars
                             ? StarHintText.topRule(threshold, targetCpm: targetCpm, unit: unit)
                             : StarHintText.rule(threshold, targetCpm: targetCpm, unit: unit))
                    }
                }
            }
            Text("На коротких текстах первых этапов четыре звезды фактически означают «без единой ошибки», а пятая отличается скоростью и чистотой остальных шагов.")
                .foregroundStyle(.secondary)
            Text("Любой шаг можно пройти заново отдельно: раскройте урок на карте курса и нажмите «Пройти заново».")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }
}

/// Кнопка «?» рядом со звёздами: по клику — попап `StarsExplanation`. `isPresented` передаётся, когда
/// владельцу нужно знать, открыт ли попап (строка курса показывает кнопку, пока он открыт).
struct StarsHelpButton: View {
    let targetCpm: Int
    let unit: SpeedUnit
    var isPresented: Binding<Bool>?
    var size: CGFloat = 13

    @State private var localPresented = false

    private var presented: Binding<Bool> { isPresented ?? $localPresented }

    var body: some View {
        Button { presented.wrappedValue.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: size))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(Text("Как считаются звёзды"))
        .accessibilityLabel(Text("Как считаются звёзды"))
        .popover(isPresented: presented, arrowEdge: .bottom) {
            StarsExplanation(targetCpm: targetCpm, unit: unit)
        }
    }
}

/// «До ★★★★: без ошибок (у вас 1)»; к ★★★★★ — и шаг урока, мешающий чистоте. Ничего не показывает, если урок
/// не засчитан или звёзд уже пять. `steps` — шаги урока (`LessonStepStats.summarize`).
struct NextStarHintView: View {
    let cpm: Double
    let accuracy: Double
    let errors: Int
    let chars: Int
    let targetCpm: Int
    let steps: [StepStat]
    let unit: SpeedUnit

    var body: some View {
        if let hint = LessonScoring.nextStarHint(cpm: cpm, accuracy: accuracy, errors: errors, chars: chars,
                                                 targetCpm: targetCpm, steps: steps) {
            let text = StarHintText.requirements(needCpm: hint.needCpm, maxErrors: hint.maxErrors,
                                                 cpm: cpm, errors: errors, unit: unit,
                                                 blockingStep: hint.blockingStep)
            HStack(spacing: 0) {
                Text("До")
                HStack(spacing: 1) {
                    ForEach(0..<hint.stars, id: \.self) { _ in
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                .padding(.leading, 5)
                Text(verbatim: ": \(text)")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("До \(hint.stars) звёзд: \(text)"))
        }
    }
}
