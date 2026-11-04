import SwiftUI
import TypingCore

/// Строка истории испытаний (§10.2, решение 18 плана): неделя — диапазон дат «26 окт. – 1 нояб.» и «2 из 3», месяц —
/// название месяца, название испытания и дата выполнения. Ключ периода (`2026-W44`) пользователю не показывается.
struct ChallengeHistoryRow: Identifiable, Equatable {
    static let weekIcon = "calendar"
    static let monthIcon = "calendar.badge.checkmark"
    /// Сколько периодов видно, пока не нажато «Показать все».
    static let limit = 8

    /// Ключ периода: `2026-W44` или `2026-11`.
    let id: String
    let title: String
    /// Неделя — «2 из 3»; месяц — «Двадцать целей · 28 окт. 2026».
    let detail: String
    let isMonth: Bool
    /// Названия выполненных испытаний периода (подсказка к строке недели).
    let completed: [String]

    var icon: String { isMonth ? Self.monthIcon : Self.weekIcon }

    static func make(_ period: ChallengePeriodResult, locale: Locale = Formatting.interfaceLocale(),
                     timeZone: TimeZone = .current, now: Date = Date()) -> ChallengeHistoryRow {
        let done = period.results.filter { $0.completedAt != nil }
        let names = done.map { YearText.title($0.id) }
        switch period.period {
        case .week(let key):
            return ChallengeHistoryRow(id: key, title: weekTitle(period.period, locale: locale, now: now, timeZone: timeZone),
                                       detail: String(localized: "\(done.count) из \(period.results.count)", locale: locale),
                                       isMonth: false, completed: names)
        case .month(let key):
            let date = done.first?.completedAt.map {
                $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone))
            }
            let detail = ([names.first] + [date]).compactMap { $0 }.joined(separator: " · ")
            return ChallengeHistoryRow(id: key, title: monthTitle(key, locale: locale), detail: detail, isMonth: true,
                                       completed: names)
        }
    }

    /// Строки по периодам в том же порядке (`YearState.history` — новые сверху).
    static func rows(history: [ChallengePeriodResult], locale: Locale = Formatting.interfaceLocale(),
                     timeZone: TimeZone = .current, now: Date = Date()) -> [ChallengeHistoryRow] {
        history.map { make($0, locale: locale, timeZone: timeZone, now: now) }
    }

    static func visible(_ rows: [ChallengeHistoryRow], showAll: Bool) -> [ChallengeHistoryRow] {
        showAll ? rows : Array(rows.prefix(limit))
    }

    static func hasMore(_ rows: [ChallengeHistoryRow]) -> Bool { rows.count > limit }

    /// «26 окт. – 1 нояб.» (en: «Oct 26 – Nov 1») по первому и последнему дню недели; год — если неделя не этого года
    /// или на стыке годов. Если даты не разобраны (не бывает для ключей движка), показывается сам ключ.
    static func weekTitle(_ period: ChallengePeriod, locale: Locale, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func parse(_ day: String) -> Date? {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
        guard let first = parse(period.firstDay), let last = parse(period.lastDay) else { return period.key }
        let year = calendar.component(.year, from: now)
        let withYear = calendar.component(.year, from: first) != year || calendar.component(.year, from: last) != year
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .month(.abbreviated).day()
        if withYear { style = style.year() }
        return (first..<last).formatted(style)
    }

    /// «октябрь 2026» по ключу месяца `2026-10`.
    private static func monthTitle(_ key: String, locale: Locale) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard parts.count == 2, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 15))
        else { return key }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: calendar.timeZone).month(.wide).year())
    }
}

/// «Испытания» в аналитике: выполненные испытания по периодам, новые сверху; последние 8, остальные — по кнопке.
struct ChallengeHistoryView: View {
    let rows: [ChallengeHistoryRow]
    @State private var showAll = false

    var body: some View {
        AnalyticsCard("Выполненные испытания") {
            InfoButton(text: HelpText.challenges)
        } content: {
            if rows.isEmpty {
                Text("Выполненных испытаний пока нет").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(ChallengeHistoryRow.visible(rows, showAll: showAll)) { row in
                        GridRow {
                            Image(systemName: row.icon).foregroundStyle(.green).frame(width: 18)
                            Text(verbatim: row.title).font(.callout.weight(.semibold)).monospacedDigit()
                            Text(verbatim: row.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        .help(row.completed.joined(separator: ", "))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(row.title). \(row.detail)"))
                        .accessibilityValue(Text(verbatim: row.completed.joined(separator: ", ")))
                    }
                }
                if ChallengeHistoryRow.hasMore(rows) {
                    Button(showAll ? "Свернуть" : "Показать все") { showAll.toggle() }
                        .buttonStyle(.link)
                }
            }
        }
    }
}
