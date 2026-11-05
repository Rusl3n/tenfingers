import SwiftUI
import TypingCore

/// Раскрываемый «Разбор» на итоге урока (§2.3): графики, «Получилось», «Подтянуть», «Куда дальше».
struct LessonReviewSection: View {
    let model: LessonReviewModel
    let unit: SpeedUnit
    /// Подпись и действие кнопки «Куда дальше»; `nil` — кнопки нет.
    var adviceTitle: String? = nil
    var onAdvice: (() -> Void)? = nil

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 18) {
                // Широкое окно — графики рядом и три колонки текста; узкое — всё столбиком.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) { charts }
                    VStack(alignment: .leading, spacing: 14) { charts }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) { notes }
                    VStack(alignment: .leading, spacing: 14) { notes }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label("Разбор", systemImage: "chart.bar.fill").font(.headline)
        }
        .frame(maxWidth: 660)
    }

    @ViewBuilder private var charts: some View {
        if model.stepSpeeds.count >= 2 {
            section("Скорость по шагам") {
                SpeedBars(values: model.stepSpeeds.map { Optional($0.cpm) }, slow: [], unit: unit,
                          help: { "\(model.stepSpeeds[$0].index + 1): \(unit.format(model.stepSpeeds[$0].cpm))" },
                          ends: (String(localized: "шаг \(model.stepSpeeds.first!.index + 1)"),
                                 String(localized: "шаг \(model.stepSpeeds.last!.index + 1)")))
            }
            .frame(width: 300, alignment: .leading)
        }
        if let segments = model.finalSegments, segments.count >= 2 {
            section("Темп по ходу текста последнего шага") {
                SpeedBars(values: segments.map(\.cpm), slow: Set(SpeedSegments.slow(segments)), unit: unit,
                          help: { segments[$0].cpm.map { unit.format($0) } },
                          ends: (String(localized: "начало"), String(localized: "конец")))
            }
            .frame(width: 300, alignment: .leading)
        }
    }

    @ViewBuilder private var notes: some View {
        if !good.isEmpty {
            section("Получилось") { ForEach(good, id: \.self) { Text($0).font(.callout) } }
                .frame(minWidth: 180, alignment: .leading)
        }
        if !weak.isEmpty {
            section("Подтянуть") { ForEach(weak, id: \.self) { Text($0).font(.callout) } }
                .frame(minWidth: 180, alignment: .leading)
        }
        if let adviceTitle, let onAdvice {
            section("Куда дальше") {
                Button(adviceTitle, action: onAdvice).buttonStyle(.bordered)
            }
        }
    }

    /// «Получилось»: лучший шаг по скорости и шаги без ошибок.
    var good: [String] { Self.goodLines(model) }
    /// «Подтянуть»: буквы с ошибками и слабый палец.
    var weak: [String] { Self.weakLines(model) }

    static func goodLines(_ model: LessonReviewModel) -> [String] {
        var lines: [String] = []
        if let best = model.review.bestStep { let step = best + 1; lines.append(String(localized: "Быстрее всего: шаг \(step)")) }
        if !model.review.cleanSteps.isEmpty {
            let steps = model.review.cleanSteps.map { String($0 + 1) }.joined(separator: ", ")
            lines.append(String(localized: "Без ошибок: шаги \(steps)"))
        }
        return lines
    }

    static func weakLines(_ model: LessonReviewModel) -> [String] {
        var lines: [String] = []
        if !model.review.letters.isEmpty {
            let letters = model.review.letters.map(String.init).joined(separator: ", ")
            lines.append(String(localized: "Буквы с ошибками: \(letters)"))
        }
        if let finger = model.review.finger {
            let name = finger.displayName
            lines.append(String(localized: "Слабый палец: \(name)"))
        }
        return lines
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
