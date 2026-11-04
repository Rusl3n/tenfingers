import SwiftUI
import TypingCore

/// Строка карточки «Испытания»: название, условие с числами, прогресс; выполненное — галочка, трудное — ★.
struct ChallengeRow: Equatable {
    let id: ChallengeId
    let title: String
    let detail: String
    /// «3 / 5», «98%»; пусто у выполненного (там галочка) и у испытания «0 или 1» (`w.speed`).
    let valueText: String
    /// Доля полоски, 0…1.
    let fraction: Double
    let isDone: Bool
    let hasStar: Bool
}

/// Неделя или месяц: заголовок «Неделя: осталось 5 дн.» и строки испытаний.
struct ChallengeSection: Equatable {
    let header: String
    let rows: [ChallengeRow]
}

/// Данные карточки «Испытания» (§10.2, решения 9 и 17 плана): три строки недели и одна месяца.
struct ChallengesCardModel: Equatable {
    static let doneIcon = DayPlanRows.doneIcon

    let week: ChallengeSection?
    let month: ChallengeSection?

    /// `nil`, если испытаний нет (занятий ещё не было): карточки на главной тогда нет.
    static func make(week: ChallengePeriodResult?, month: ChallengePeriodResult?, today: String, unit: SpeedUnit,
                     bundle: Bundle = .main, locale: Locale = Formatting.interfaceLocale()) -> ChallengesCardModel? {
        func section(_ period: ChallengePeriodResult?, isWeek: Bool) -> ChallengeSection? {
            guard let period, !period.results.isEmpty else { return nil }
            let left = Formatting.daysLeft(daysLeft(in: period.period, today: today), bundle: bundle, locale: locale)
            let header = isWeek ? String(localized: "Неделя: \(left)", bundle: bundle, locale: locale)
                                : String(localized: "Месяц: \(left)", bundle: bundle, locale: locale)
            let rows = period.results.map { row($0, parameters: period.parameters, unit: unit, bundle: bundle, locale: locale) }
            return ChallengeSection(header: header, rows: rows)
        }
        let week = section(week, isWeek: true), month = section(month, isWeek: false)
        guard week != nil || month != nil else { return nil }
        return ChallengesCardModel(week: week, month: month)
    }

    /// Дней до конца периода, считая сегодняшний (после конца периода — 0).
    static func daysLeft(in period: ChallengePeriod, today: String) -> Int {
        StreakCalculator.dayKeys(from: today, to: period.lastDay).count
    }

    private static func row(_ result: ChallengeResult, parameters: ChallengeParameters, unit: SpeedUnit,
                            bundle: Bundle, locale: Locale) -> ChallengeRow {
        let done = result.completedAt != nil
        let fraction = done ? 1 : min(max(Double(result.progress) / Double(max(result.target, 1)), 0), 1)
        let value: String
        if done || result.id == .weekSpeed {
            value = ""
        } else if result.id == .monthGrowth {
            value = "\(result.progress)%"
        } else {
            let progress = result.progress.formatted(.number.locale(locale))
            let target = result.target.formatted(.number.locale(locale))
            value = "\(progress) / \(target)"
        }
        return ChallengeRow(id: result.id, title: YearText.title(result.id),
                            detail: YearText.condition(result, parameters: parameters, unit: unit, bundle: bundle,
                                                       locale: locale),
                            valueText: value, fraction: fraction, isDone: done, hasStar: result.id.isHard)
    }
}

/// «Испытания» на главной: после плана на сегодня. Стиль — как у `DayPlanCard`.
struct ChallengesCard: View {
    let model: ChallengesCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Испытания").font(.title3.bold())
                InfoButton(text: HelpText.challenges)
            }
            if let week = model.week { sectionView(week) }
            if let month = model.month { sectionView(month) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func sectionView(_ section: ChallengeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: section.header).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(section.rows, id: \.id) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.isDone ? ChallengesCardModel.doneIcon : "circle")
                        .foregroundStyle(row.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary.opacity(0.6)))
                        .frame(width: 22)
                    HStack(spacing: 6) {
                        Text(verbatim: row.title).font(.headline)
                        if row.hasStar {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                .help(Text("Трудное испытание"))
                        }
                        Text(verbatim: row.detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: row.valueText)
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 90, height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(row.isDone ? Color.green : Color.orange)
                                    .frame(width: proxy.size.width * row.fraction)
                            }
                        }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(row.title). \(row.detail)"))
                .accessibilityValue(Text(verbatim: row.isDone ? ChallengesCardModel.doneText : row.valueText))
            }
        }
    }
}

extension ChallengesCardModel {
    /// Озвучка выполненного испытания.
    static var doneText: String { String(localized: "Выполнено") }
}
