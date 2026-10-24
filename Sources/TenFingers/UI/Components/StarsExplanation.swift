import SwiftUI
import TypingCore

/// Тексты объяснения звёзд и подсказки «до следующей звезды». Пороги берутся из `LessonScoring`,
/// поэтому объяснение не может разойтись с подсчётом.
enum StarHintText {
    /// Скорость для ★★: цель этапа.
    static func twoStarGoal(targetCpm: Int, unit: SpeedUnit) -> String {
        unit.format(Double(targetCpm), rounding: .up)
    }

    /// Скорость для ★★★: цель × 1,3, округлённая вверх (названная скорость точно даёт звезду).
    static func threeStarGoal(targetCpm: Int, unit: SpeedUnit) -> String {
        unit.format(Double(targetCpm) * LessonScoring.threeStarFactor, rounding: .up)
    }

    /// Условие ★★ для попапа; без цели этапа (`targetCpm` ≤ 0, урока нет в курсе) — без числа скорости.
    static func twoStarRule(targetCpm: Int, unit: SpeedUnit, locale: Locale = .current) -> String {
        let accuracy = Formatting.compactPercent(LessonScoring.twoStarAccuracy, locale: locale)
        guard targetCpm > 0 else { return String(localized: "скорость не ниже цели этапа и точность от \(accuracy)") }
        let goal = twoStarGoal(targetCpm: targetCpm, unit: unit)
        return String(localized: "скорость не ниже цели этапа (\(goal)) и точность от \(accuracy)")
    }

    /// Условие ★★★ для попапа; без цели этапа — без числа скорости.
    static func threeStarRule(targetCpm: Int, unit: SpeedUnit, locale: Locale = .current) -> String {
        let accuracy = Formatting.compactPercent(LessonScoring.threeStarAccuracy, locale: locale)
        let factor = LessonScoring.threeStarFactor.formatted(.number.locale(locale))
        guard targetCpm > 0 else { return String(localized: "скорость от цели × \(factor) и точность от \(accuracy)") }
        let goal = threeStarGoal(targetCpm: targetCpm, unit: unit)
        return String(localized: "скорость от цели × \(factor) (\(goal)) и точность от \(accuracy)")
    }

    /// «скорость от 60 зн/мин (у вас 52 зн/мин) и точность от 99,5% (у вас 98,9%)»; пусто, если условий нет.
    /// Порог округляется вверх, результат — вниз: недостающее не выглядит достигнутым.
    static func requirements(needCpm: Double?, needAccuracy: Double?, cpm: Double, accuracy: Double,
                             unit: SpeedUnit, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let needCpm, needCpm > 0 {
            let need = unit.format(needCpm, rounding: .up), have = unit.format(cpm, rounding: .down)
            parts.append(String(localized: "скорость от \(need) (у вас \(have))"))
        }
        if let needAccuracy {
            let need = Formatting.compactPercent(needAccuracy, locale: locale)
            let have = Formatting.percent(accuracy, rounding: .down, locale: locale)
            parts.append(String(localized: "точность от \(need) (у вас \(have))"))
        }
        switch parts.count {
        case 2: return String(localized: "\(parts[0]) и \(parts[1])")
        case 1: return parts[0]
        default: return ""
        }
    }
}

/// Попап «Как считаются звёзды»: что влияет на звёзды и пороги для цели этапа `targetCpm`.
struct StarsExplanation: View {
    let targetCpm: Int
    let unit: SpeedUnit

    var body: some View {
        let pass = Formatting.compactPercent(LessonScoring.passAccuracy)
        VStack(alignment: .leading, spacing: 10) {
            Text("Как считаются звёзды").font(.headline)
            Text("Звёзды за урок ставятся по проверочному тексту — последнему шагу урока. Остальные шаги — тренировка: на звёзды они не влияют, но показывают, где ошибки.")
            Text("Урок засчитан при точности от \(pass).")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    StarsView(count: 1, size: 11)
                    Text("урок засчитан")
                }
                GridRow {
                    StarsView(count: 2, size: 11)
                    Text(verbatim: StarHintText.twoStarRule(targetCpm: targetCpm, unit: unit))
                }
                GridRow {
                    StarsView(count: 3, size: 11)
                    Text(verbatim: StarHintText.threeStarRule(targetCpm: targetCpm, unit: unit))
                }
            }
            Text("На коротких текстах первых этапов три звезды фактически означают «без единой ошибки».")
                .foregroundStyle(.secondary)
            Text("Любой шаг можно пройти заново отдельно: раскройте урок на карте курса и нажмите «Пройти заново».")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 380, alignment: .leading)
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

/// «До ★★★: точность от 99,5% (у вас 98,9%)». Ничего не показывает, если урок не засчитан или звёзд уже три.
struct NextStarHintView: View {
    let cpm: Double
    let accuracy: Double
    let targetCpm: Int
    let unit: SpeedUnit

    var body: some View {
        if let hint = LessonScoring.nextStarHint(cpm: cpm, accuracy: accuracy, targetCpm: targetCpm) {
            let next = LessonScoring.stars(cpm: cpm, accuracy: accuracy, targetCpm: targetCpm) + 1
            let text = StarHintText.requirements(needCpm: hint.needCpm, needAccuracy: hint.needAccuracy,
                                                 cpm: cpm, accuracy: accuracy, unit: unit)
            HStack(spacing: 0) {
                Text("До")
                HStack(spacing: 1) {
                    ForEach(0..<next, id: \.self) { _ in
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                .padding(.leading, 5)
                Text(verbatim: ": \(text)")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("До \(next) звёзд: \(text)"))
        }
    }
}
