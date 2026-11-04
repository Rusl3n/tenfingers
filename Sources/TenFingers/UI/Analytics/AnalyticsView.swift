import SwiftData
import SwiftUI
import TypingCore

/// «Аналитика»: данные читаются из базы при появлении экрана и при смене курса или настроек дня,
/// графики — ещё и при смене периода, история (все языки, не зависит от настроек) — только при появлении.
/// Если чтение не удалось — сообщение с кнопкой «Повторить» вместо пустого экрана.
/// Сама раскладка — в `AnalyticsContent`.
struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ContentLibrary.self) private var library
    @Environment(KeyboardLayoutService.self) private var layout
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.firstWeekday) private var firstWeekday = SettingsDefault.firstWeekday
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @State private var period: AnalyticsPeriod = .month
    @State private var data: AnalyticsData?
    @State private var chart: ChartSeries = .empty
    @State private var history: [HistoryRow] = []
    /// Опыт и история испытаний; ошибка чтения прячет только их карточки, не всю аналитику.
    @State private var year: YearState?
    /// Какие части экрана не прочитались из базы.
    @State private var failed: Set<Part> = []
    /// Открытая карточка «Мой прогресс».
    @State private var share: ShareCard?

    private enum Part { case summary, chart, history }

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }
    private var today: String { LogicalDay.key(for: .now, dayStartHour: dayStartHour) }

    var body: some View {
        Group {
            if !failed.isEmpty {
                LoadErrorView(retry: reloadAll)
            } else if let data {
                AnalyticsContent(data: data, chart: chart, history: history, year: year,
                                 unit: SpeedUnit(rawValue: speedUnit) ?? .cpm, snapshot: layout.snapshot,
                                 period: $period, shareProgress: openProgressCard,
                                 shareCertificate: openCertificateCard)
            } else {
                Color.clear
            }
        }
        .shareSheet($share)
        .onAppear(perform: reloadAll)
        .onChange(of: activeLanguage) { reload() }
        .onChange(of: dayStartHour) { reload() }
        .onChange(of: firstWeekday) { reload() }
        .onChange(of: dailyGoal) { reload() }
        .onChange(of: period) { reloadChart() }
    }

    /// «Поделиться» у календаря: карточка «Мой прогресс» из свежих данных базы; ошибка чтения — тост.
    private func openProgressCard() {
        share = ShareCard.openProgress(context: modelContext, goalSeconds: Double(dailyGoal) * 60,
                                       dayStartHour: dayStartHour, toasts: toasts)
    }

    /// «Сертификат» у строки курса: карточка со средней скоростью проверок этапов.
    private func openCertificateCard(_ row: CourseProgressRow) {
        guard let average = row.certificateAverage else { return }
        share = ShareCard(.certificate(language: row.language, averageCpm: average))
    }

    private func reloadAll() {
        reloadHistory()
        reload()
    }

    /// Один снимок года на загрузку (кэш в `YearLoader` не пересчитывает опыт, пока история не менялась).
    private func reloadYear() {
        year = try? YearLoader(context: modelContext).state()
    }

    private func reload() {
        do {
            data = try AnalyticsLoader(context: modelContext).summary(
                language: language, courses: library.courses, legacyCourses: library.legacyCourses,
                today: today, goalSeconds: Double(dailyGoal) * 60)
            failed.remove(.summary)
        } catch {
            failed.insert(.summary)
        }
        reloadYear()
        reloadChart()
    }

    private func reloadHistory() {
        do {
            history = try AnalyticsLoader(context: modelContext)
                .history(courses: library.courses, legacyCourses: library.legacyCourses, texts: library.texts)
            failed.remove(.history)
        } catch {
            failed.insert(.history)
        }
    }

    private func reloadChart() {
        do {
            chart = try AnalyticsLoader(context: modelContext).chart(language: language, period: period, today: today)
            failed.remove(.chart)
        } catch {
            failed.insert(.chart)
        }
    }
}

/// Раскладка экрана сверху вниз: время, графики, опыт, клавиатура, пальцы, календарь, рекорды, испытания, история, курсы.
struct AnalyticsContent: View {
    let data: AnalyticsData
    let chart: ChartSeries
    let history: [HistoryRow]
    var year: YearState?
    let unit: SpeedUnit
    let snapshot: LayoutSnapshot
    @Binding var period: AnalyticsPeriod
    var shareProgress: (() -> Void)?
    var shareCertificate: ((CourseProgressRow) -> Void)?

    /// Поделиться прогрессом можно, как только есть хоть одно занятие (как на главной).
    nonisolated static func canShareProgress(_ data: AnalyticsData) -> Bool { data.firstSessionDate != nil }

    var body: some View {
        ScrollView { column }
            .scrollContentBackground(.hidden)
    }

    /// Содержимое без прокрутки (его же рисует проверка через `ImageRenderer`).
    var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Аналитика: \(data.language.displayName)").font(.largeTitle.bold())
            TimeTotalsView(data: data)
            ProgressChartsView(chart: chart, unit: unit, period: $period)
            if let year { ExperienceChartView(model: ExperienceChartModel.make(ledger: year.ledger, today: year.today)) }
            KeyboardHeatmapView(snapshot: snapshot, language: data.language, keys: data.keys)
            FingerStatsView(rows: data.fingers)
            ActivityCalendarView(calendar: data.calendar, share: Self.canShareProgress(data) ? shareProgress : nil)
            DayMetricsView(streak: data.streak)
            RecordsView(records: data.records, unit: unit)
            if let year { ChallengeHistoryView(rows: ChallengeHistoryRow.rows(history: year.history)) }
            SessionHistoryView(rows: history, unit: unit)
            CourseProgressView(rows: data.courseProgress, shareCertificate: shareCertificate)
        }
        .padding(24)
        .frame(maxWidth: 900, alignment: .leading)
    }
}

/// Карточка секции с заголовком на фоне палитры.
struct AnalyticsCard<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    init(_ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Чистое время за сегодня, 7 и 30 дней и всего; даты первого занятия и начала курса.
struct TimeTotalsView: View {
    let data: AnalyticsData

    var body: some View {
        AnalyticsCard("Время занятий") {
            HStack(alignment: .top, spacing: 16) {
                metric("Сегодня", data.totals.today)
                metric("7 дней", data.totals.week)
                metric("30 дней", data.totals.month)
                metric("Всего", data.totals.all)
            }
            let first = date(data.firstSessionDate)
            let started = date(data.courseStartDate)
            VStack(alignment: .leading, spacing: 4) {
                Text("Первое занятие: \(first)")
                Text("Курс начат: \(started)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Formatting.duration(seconds)).font(.title3.weight(.semibold)).monospacedDigit()
                .minimumScaleFactor(0.8).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func date(_ date: Date?) -> String {
        date?.formatted(date: .long, time: .omitted) ?? "—"
    }
}
