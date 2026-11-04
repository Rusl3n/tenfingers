import AppIntents
import SwiftUI
import WidgetKit
import WidgetSnapshot

/// Одна запись ленты: страница и всё, что нужно её нарисовать на момент `date`.
struct TenFingersEntry: TimelineEntry {
    let date: Date
    let page: WidgetPage
    /// `nil` — файла нет (страница тогда `.placeholder`).
    let snapshot: WidgetSnapshot?
    let showInvite: Bool
    /// «Менять по нажатию»: нажатие листает страницу, а не открывает приложение.
    let tapToSwitch: Bool
    /// Смещение ленты, которое запишет нажатие: страница после показанной.
    var nextOffset = 0
}

/// Пример для галереи и заглушки, когда настоящего снимка ещё нет: правдоподобные цифры, без чтения файла.
enum WidgetSample {
    static func snapshot(language: String, now: Date) -> WidgetSnapshot {
        let ru = language == "ru"
        let day = WidgetTimeline.logicalDay(for: now)
        let achievements: [WidgetSnapshot.Item] = [
            .init(id: "sample.speed", title: ru ? "Скорость 150" : "Speed 150", symbol: "bolt.fill", date: now, adult: false),
            .init(id: "sample.week", title: ru ? "Неделя подряд" : "A week in a row", symbol: "flame.fill", date: now, adult: false),
            .init(id: "sample.clean", title: ru ? "Чистый урок" : "Clean lesson", symbol: "checkmark.seal.fill", date: now, adult: false),
        ]
        return WidgetSnapshot(
            writtenAt: now, logicalDay: day, language: language, adultHumor: false,
            fire: .init(days: 12, today: .full, freezes: 1), spark: .init(days: 12, today: true),
            goal: .init(goalMinutes: 15, doneMinutes: 10),
            next: .init(title: ru ? "Урок 7. Верхний ряд" : "Lesson 7. Top row", courseLanguage: language),
            achievements: achievements)
    }
}

struct TenFingersProvider: AppIntentTimelineProvider {
    /// Без чтения файла: пример на языке системы.
    func placeholder(in context: Context) -> TenFingersEntry {
        let now = Date()
        let sample = WidgetSample.snapshot(language: WidgetStrings(language: nil).language, now: now)
        return TenFingersEntry(date: now, page: .streak, snapshot: sample, showInvite: true, tapToSwitch: false)
    }

    func snapshot(for configuration: TenFingersConfiguration, in context: Context) async -> TenFingersEntry {
        let now = Date()
        var snapshot = SnapshotReader.read()
        // В галерее без файла показываем пример, а не пустую заглушку.
        if context.isPreview, snapshot == nil {
            snapshot = WidgetSample.snapshot(language: WidgetStrings(language: nil).language, now: now)
        }
        let pages = WidgetTimeline.pages(selection: configuration.selection, snapshot: snapshot,
                                         hideAdult: configuration.hideAdult)
        return TenFingersEntry(date: now, page: pages.first ?? .placeholder, snapshot: snapshot,
                               showInvite: configuration.showInvite, tapToSwitch: configuration.tapToSwitch)
    }

    /// Записи с шагом «Менять каждые, мин» на два часа вперёд: страницы по кругу, начиная со счётчика нажатий.
    /// Одна страница тоже повторяется, чтобы «сегодня» и «давно не открывали» пересчитывались.
    func timeline(for configuration: TenFingersConfiguration, in context: Context) async -> Timeline<TenFingersEntry> {
        let now = Date()
        let snapshot = SnapshotReader.read()
        let pages = WidgetTimeline.pages(selection: configuration.selection, snapshot: snapshot,
                                         hideAdult: configuration.hideAdult)
        let offset = PageCounter.value
        let entries = WidgetTimeline.entries(pages: pages, start: now, intervalMinutes: configuration.intervalMinutes,
                                             offset: offset).enumerated().map { index, item in
            let shown = WidgetTimeline.pageIndex(offset: offset, entry: index, pageCount: pages.count)
            return TenFingersEntry(date: item.0, page: item.1, snapshot: snapshot, showInvite: configuration.showInvite,
                                   tapToSwitch: configuration.tapToSwitch,
                                   nextOffset: WidgetTimeline.nextOffset(afterShown: shown, pageCount: pages.count))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct TenFingersEntryView: View {
    let entry: TenFingersEntry
    @Environment(\.widgetFamily) private var family

    private var strings: WidgetStrings { WidgetStrings(language: entry.snapshot?.language) }

    var body: some View {
        Group {
            if entry.tapToSwitch {
                switching
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    content
                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(entry.page.link)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// «Менять по нажатию»: вся страница — кнопка следующей страницы. Строка приглашения в среднем виджете
    /// остаётся ссылкой на урок; в маленьком она часть кнопки.
    private var switching: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(intent: NextPageIntent(link: entry.page.link, nextOffset: entry.nextOffset)) {
                VStack(alignment: .leading, spacing: 6) {
                    content
                    staleLabel
                    if family == .systemSmall { inviteLine }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if family != .systemSmall { inviteLine }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            let today = WidgetTimeline.today(for: snapshot, now: entry.date, dayStartHour: snapshot.dayStartHour)
            switch entry.page {
            case .streak: StreakView(snapshot: snapshot, today: today, strings: strings)
            case .goal: GoalView(snapshot: snapshot, today: today, strings: strings)
            case .achievements(let items): AchievementsView(items: items, strings: strings)
            case .placeholder: PlaceholderView(strings: strings)
            }
        } else {
            PlaceholderView(strings: strings)
        }
    }

    /// «Давно не открывали» и строка приглашения на урок.
    @ViewBuilder private var footer: some View {
        staleLabel
        inviteLine
    }

    @ViewBuilder private var staleLabel: some View {
        if let snapshot = entry.snapshot, entry.page != .placeholder, snapshot.isStale(now: entry.date) {
            Text(verbatim: strings.text("давно не открывали"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder private var inviteLine: some View {
        if let snapshot = entry.snapshot, entry.page != .placeholder, entry.showInvite, let next = snapshot.next {
            invite(next)
        }
    }

    @ViewBuilder private func invite(_ next: WidgetSnapshot.Next) -> some View {
        let line = Text(verbatim: strings.text("Продолжить: %@", next.title))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        // Link работает только в среднем виджете; в маленьком нажатие уходит на `widgetURL` (или на кнопку смены).
        if family == .systemSmall {
            line
        } else {
            Link(destination: WidgetLink.course) { line }
        }
    }
}

/// Идентификатор виджета для перезагрузки ленты.
enum TenFingersWidgetKind {
    static let home = "TenFingersWidget"
}

struct TenFingersHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: TenFingersWidgetKind.home, intent: TenFingersConfiguration.self,
                               provider: TenFingersProvider()) { entry in
            TenFingersEntryView(entry: entry)
        }
        .configurationDisplayName("Десять пальцев")
        .description("Серия, цель дня и ачивки на рабочем столе.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TenFingersWidgetBundle: WidgetBundle {
    var body: some Widget {
        TenFingersHomeWidget()
    }
}
