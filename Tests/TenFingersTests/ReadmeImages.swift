import SwiftUI
import Testing
import TypingCore
import WidgetKit
import WidgetSnapshot
@testable import TenFingers
@testable import TenFingersWidget

/// Рендерит картинки для README в docs/images. Запуск: RENDER_DOCS=1 swift test --filter renderReadmeImages
@MainActor
private func render<V: View>(_ view: V, to name: String) throws {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/images")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: dir.appendingPathComponent(name))
}

/// Рендер через `NSHostingView` в окне за пределами экрана: в отличие от `ImageRenderer` рисует и элементы AppKit
/// (кнопки, переключатели, списки выбора), а кнопки с поповерами не превращает в жёлтые заглушки. Окно делается
/// главным, чтобы акцентные кнопки не были серыми, как у неактивного окна, и тут же убирается.
/// Ширина задаётся; высота — по содержимому или `height`; `crop` оставляет только верхние `crop` точек.
/// Масштаб — 2 (как у `render`).
@MainActor
private func renderHosted<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, crop: CGFloat? = nil,
                                   to name: String) throws {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/images")
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.appearance = NSAppearance(named: .aqua)
    let size = host.fittingSize
    let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    // Без контекста окна `cacheDisplay` рисует в масштабе 1: свой растр в двойном разрешении.
    let area = NSRect(x: 0, y: 0, width: size.width, height: min(crop ?? size.height, size.height))
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(area.width * 2), pixelsHigh: Int(area.height * 2), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = area.size
    host.cacheDisplay(in: area, to: rep)
    let png = try #require(rep.representation(using: .png, properties: [:]))
    try png.write(to: dir.appendingPathComponent(name))
}

/// Курс с русскими названиями этапов и уроков. Названия в курсе — русские ключи перевода, а в тестах строки ядра
/// берутся на английском (язык процесса, `Bundle.main` без переводов приложения), поэтому ключам добавлен невидимый
/// пробел нулевой ширины: перевода у такого ключа нет, и `localizedTitle` возвращает русский текст как есть.
private func russianCourse(_ course: Course) throws -> Course {
    func mark(_ value: Any) -> Any {
        if let array = value as? [Any] { return array.map(mark) }
        guard let object = value as? [String: Any] else { return value }
        return object.reduce(into: [String: Any]()) { result, pair in
            if pair.key == "title", let title = pair.value as? String { result[pair.key] = title + "\u{200B}" }
            else { result[pair.key] = mark(pair.value) }
        }
    }
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course))
    return try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: mark(json)))
}

/// Подписи легенды на английском из Localization/en.lproj: в тестах `Bundle.main` не содержит локализации приложения.
private func englishLegendTitles() throws -> [String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let strings = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    return try FingerLegend.titleKeys.map { try #require(strings[$0], "нет перевода: \($0)") }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderReadmeImages() async throws {
    let ru = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.RussianWin"))
    let en = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.ABC"))
    let ruSnap = KeyboardLayoutService.snapshot(for: ru, shape: .ansi)
    let enSnap = KeyboardLayoutService.snapshot(for: en, shape: .ansi)
    let enLegend = try englishLegendTitles()
    let marks = KeyboardView.marks(for: KeyHighlight(keyCode: 22, shiftKeyCode: 56, isError: false))

    let light = LightPalette.beige.palette
    try render(
        VStack(spacing: 16) {
            KeyboardView(snapshot: ruSnap, marks: marks)
            FingerLegend()
        }
        .padding(24)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        to: "keyboard-ru.png"
    )

    let dark = DarkPalette.night.palette
    try render(
        VStack(spacing: 16) {
            KeyboardView(snapshot: enSnap, marks: marks)
            FingerLegend(titles: enLegend)
        }
        .padding(24)
        .background(dark.background)
        .environment(\.palette, dark)
        .environment(\.colorScheme, .dark),
        to: "keyboard-en-dark.png"
    )

    try render(
        TypingTextView(target: Array("щука щит цвет цепь щель цапля ещё"), position: 14, errorAtCursor: true)
            .padding(24)
            .frame(width: 520, alignment: .leading)
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        to: "exercise-text.png"
    )

    // Главная с серией, «Искрой» и планом дня. Рисуется через `NSHostingView` (`renderHosted`): `ImageRenderer`
    // заменяет кнопки с поповерами жёлтыми заглушками. Прокрутки нет — берётся `HomeContent.column`.
    // Курс английский: название языка («English») читается одинаково в любом интерфейсе; остальные строки —
    // исходные русские.
    let enCourse = try #require(ContentLibrary().courses[.en])
    try renderHosted(
        VStack(spacing: 0) {
            HomeContent(data: homeFixture(), continueInfo: ContinueInfo(
                            lessonTitle: "Буквы E и N", stageTitle: "Основной ряд", percent: 23,
                            retakeCheck: false, lessonRun: LessonRun(language: .en, lessonId: "en.1.3")),
                        unit: .cpm, level: LevelLine.make(level: 14, title: .of(level: 14), gained: 320, needed: 500),
                        challenges: challengesFixture(), dayPlan: dayPlanFixture(course: enCourse),
                        startLesson: { _ in }, openTraining: {}, startWeakSpots: {}, openPractice: {},
                        tabOverride: .plan, dotsOverride: [.challenges])
                .column
        }
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        width: 820, to: "home.png"
    )

    // Тепловая карта ошибок по клавишам (без переключателя режима: элементы AppKit `ImageRenderer` не рисует;
    // без таблицы пальцев: их названия — строки ядра, в тестах на языке системы).
    let keys = heatmapFixture(ruSnap)
    try render(
        AnalyticsCard("Клавиатура") {
            VStack(alignment: .leading, spacing: 10) {
                HeatmapKeyboardView(snapshot: ruSnap, language: .ru, keys: keys,
                                    heat: HeatmapModel.heat(keys, mode: .errors))
                HeatLegend(mode: .errors)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 760)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        to: "analytics-heatmap.png"
    )
}

/// Экран «Ачивки» (русский интерфейс): полученные, с шуткой и датой; видны первые строки
/// сетки. Названия, шутки и условия берутся из ресурсов ядра на русском (в тестах строки ядра идут на языке процесса).
/// Запуск: RENDER_DOCS=1 swift test --filter renderAchievementsImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderAchievementsImage() throws {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let ids = ["streak.3", "streak.7", "streak.14", "speed.ru.100", "speed.ru.150", "spark.7", "accuracy.sniper",
               "course.first_lesson", "course.first_stage", "volume.chars.10k", "volume.hours.1", "special.night_owl",
               "letters.ru.hello", "fun.not_today"]
    let earned = ids.enumerated().map { index, id in
        StoredAchievement(id: id, unlockedAt: base.addingTimeInterval(Double(index) * 86_400), seen: true)
    }
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let ruStrings = try #require(try PropertyListSerialization.propertyList(
        from: Data(contentsOf: root.appendingPathComponent("Sources/TypingCore/Resources/ru.lproj/Localizable.strings")),
        format: nil) as? [String: String])
    let entries = AchievementsListing.entries(catalog: AchievementCatalog.all, earned: earned, adultHumor: true)
        .map { entry in
            let achievement = entry.achievement
            return AchievementEntry(
                achievement: achievement, unlockedAt: entry.unlockedAt, seen: entry.seen,
                lockedText: AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                              localization: "ru"),
                title: ruStrings[achievement.titleKey], earnedText: ruStrings[achievement.detailKey],
                reasonText: AchievementConditionText.describe(achievement.condition, display: achievement.lettersDisplay,
                                                              localization: "ru", earned: true))
        }
    let light = LightPalette.beige.palette
    // Фильтр «Полученные»: иначе первые строки сетки заняли бы неполученные силуэты категории «Серия».
    // Через `renderHosted`: переключатель фильтра — элемент AppKit.
    try renderHosted(
        AchievementsContent(entries: entries, category: .constant(nil), filter: .constant(.earned), freshIds: [],
                            select: { _ in })
            .frame(height: 880, alignment: .top)
            .clipped()
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        width: 900, height: 880, to: "achievements.png"
    )
}

/// Карта курса (русский интерфейс): первый этап с пройденными уроками и звёздами, «Освежить» у слабого урока,
/// следующий этап закрыт. Таблицу собирает та же `CourseLessonRow` и тот же заголовок этапа, что у `CourseMapView`
/// (сам экран читает SwiftData и прокручивается: `ImageRenderer` рисует только статичное содержимое).
/// Запуск: RENDER_DOCS=1 swift test --filter renderCourseMapImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderCourseMapImage() throws {
    let course = try russianCourse(#require(ContentLibrary().courses[.ru]))
    let stars = [5, 4, 2, 5, 3]                       // пройденные уроки первого этапа
    let passed = Set(course.stages[0].lessons.prefix(stars.count).map(\.id))
    let light = LightPalette.beige.palette
    func header(_ stage: Stage, locked: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.localizedTitle).foregroundStyle(.primary)
                Spacer()
                Text(CourseColumns.stageGoalText(stage, unit: .cpm)).foregroundStyle(.secondary)
                Text(CourseColumns.gateText(stage)).font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout.weight(.semibold))
            if let locked {
                Text(CourseColumns.opensWhenText(previousStage: locked, gate: course.stages[locked - 1].gate))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    let first = course.stages[0]
    let rows = Array(first.lessons.prefix(8).enumerated())
    try renderHosted(
        VStack(alignment: .leading, spacing: 0) {
            header(first, locked: nil)
            ForEach(rows, id: \.element.id) { index, lesson in
                let isPassed = index < stars.count
                CourseLessonRow(
                    lesson: lesson, language: .ru,
                    overview: LessonOverview.make(lessonId: lesson.id, targetCpm: course.targetCpm(for: lesson.id) ?? 0,
                                                  sessions: [], storedStars: isPassed ? stars[index] : 0,
                                                  isPassed: isPassed),
                    targetCpm: course.targetCpm(for: lesson.id) ?? 0, bestCpm: isPassed ? 96 + Double(index * 9) : 0,
                    isPassed: isPassed, isUnlocked: course.isUnlocked(lesson.id, passed: passed, checkStars: [:]),
                    unit: .cpm, refresh: index == 2 ? RefreshMark(isDue: true, isHard: true) : nil,
                    isExpanded: .constant(false), start: { _ in })
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            header(course.stages[1], locked: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        width: 760, to: "course.png"
    )
}

/// Виджет на рабочем столе: настоящий `TenFingersEntryView` расширения (`@testable import TenFingersWidget`)
/// с демо-снимком и вымышленными числами. Четыре средних виджета: серия, цель дня в пути, цель выполнена, ачивки.
/// Подписи — исходные русские (в тестах бандла расширения с переводами нет). Рамка и фон — как у карточки виджета.
/// Маленький виджет не рисуется: `widgetFamily` в окружении только для чтения, и вне системы виджетов
/// виды всегда получают средний размер.
/// Запуск: RENDER_DOCS=1 swift test --filter renderWidgetImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderWidgetImage() throws {
    let now = Date()
    func snapshot(doneMinutes: Int) -> WidgetSnapshot {
        WidgetSnapshot(
            writtenAt: now, logicalDay: WidgetTimeline.logicalDay(for: now), language: "ru", adultHumor: false,
            fire: .init(days: 14, today: .full, freezes: 1), spark: .init(days: 21, today: true),
            goal: .init(goalMinutes: 10, doneMinutes: doneMinutes),
            next: .init(title: "Урок 12. Верхний ряд", courseLanguage: "ru"),
            achievements: [
                .init(id: "demo.speed", title: "Скорость 150", symbol: "bolt.fill", date: now, adult: false),
                .init(id: "demo.week", title: "Неделя подряд", symbol: "flame.fill", date: now, adult: false),
                .init(id: "demo.clean", title: "Чистый урок", symbol: "checkmark.seal.fill", date: now, adult: false),
            ])
    }
    func widget(_ page: WidgetPage, doneMinutes: Int = 7) -> some View {
        let snapshot = snapshot(doneMinutes: doneMinutes)
        return TenFingersEntryView(entry: TenFingersEntry(date: now, page: page, snapshot: snapshot, showInvite: true,
                                                          tapToSwitch: false))
            .padding(16)
            .frame(width: 364, height: 170)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
    let items = snapshot(doneMinutes: 7).achievements
    let light = LightPalette.beige.palette
    try renderHosted(
        VStack(spacing: 20) {
            HStack(spacing: 20) { widget(.streak); widget(.goal) }
            HStack(spacing: 20) { widget(.achievements(items)); widget(.goal, doneMinutes: 10) }
        }
        .padding(28)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        width: 804, to: "widget.png"
    )
}

/// «Настройки → Общие»: настоящий `SettingsView` с переключателями и списками выбора (`renderHosted`;
/// `ImageRenderer` элементы AppKit не рисует). Значения — из отдельного набора настроек: светлая тема, палитра
/// «Бежевая». Проверка обновлений говорит «Установлена последняя версия». Версия внизу — как у сборки из тестов.
/// Запуск: RENDER_DOCS=1 swift test --filter renderSettingsImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderSettingsImage() async throws {
    let (defaults, name) = makeTestDefaults("readme-settings-")
    defer { removeTestDefaults(name) }
    defaults.set(LightPalette.beige.rawValue, forKey: SettingsKey.lightPalette)
    defaults.set(ThemeMode.light.rawValue, forKey: SettingsKey.themeMode)
    defaults.set(SettingsSection.general.rawValue, forKey: SettingsKey.settingsSection)
    let checker = try await updateChecker(offering: "2.5.0", defaults: defaults)
    let scheduler = ReminderScheduler(center: IdleReminderCenter(), defaults: defaults,
                                      inputs: { _ in throw CocoaError(.fileNoSuchFile) }, title: "Десять пальцев")
    let light = LightPalette.beige.palette
    try renderHosted(
        SettingsView()
            .environment(checker)
            .environment(scheduler)
            .environment(ReminderDraftStore(defaults: defaults))
            .defaultAppStorage(defaults)
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        width: 740, height: 900, crop: 760, to: "settings.png"
    )
}

/// Карточки «Поделиться»: серия по-русски (светлый «огонь», квадрат) и рекорд скорости по-английски
/// (тёмная палитра, широкая). Тексты — из Localization/<язык>.lproj (в тестах `Bundle.main` без переводов
/// приложения), иконка — scripts/AppIcon.icns (в тестах её нет в бандле). Рисует `ShareCardRenderer`, как
/// в приложении, но в масштабе 1 и в JPEG (качество 0,85): градиенты в PNG весят больше мегабайта.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderShareCardImages() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let icon = try #require(NSImage(contentsOf: root.appendingPathComponent("scripts/AppIcon.icns")))
    func bundle(_ language: String) throws -> Bundle {
        try #require(Bundle(url: root.appendingPathComponent("Localization/\(language).lproj")))
    }
    let (defaults, name) = makeTestDefaults("readme-share-")
    defer { removeTestDefaults(name) }
    defaults.set(DarkPalette.night.rawValue, forKey: SettingsKey.darkPalette)
    let date = Date(timeIntervalSince1970: 1_792_843_200)
    let dir = root.appendingPathComponent("docs/images")
    func jpeg(_ view: ShareCardView, to name: String) throws {
        let rep = try #require(NSBitmapImageRep(data: try ShareCardRenderer.png(view, scale: 1)))
        let data = try #require(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]))
        try data.write(to: dir.appendingPathComponent(name))
    }

    let streak = ShareOptions(signature: .nickname, theme: .light, background: .colored, format: .square)
    try jpeg(ShareCardView.make(card: ShareCard(.streak(days: 30, full: 28), now: date), options: streak,
                                profile: ShareProfile(nickname: "rusl3n", fullName: ""), defaults: defaults,
                                bundle: bundle("ru"), locale: Locale(identifier: "ru"), appIcon: icon),
             to: "share-streak-ru.jpg")

    let speed = ShareOptions(signature: .nickname, theme: .dark, background: .colored, format: .wide)
    try jpeg(ShareCardView.make(card: ShareCard(.speedRecord(.en, cpm: 268, date: date)), options: speed,
                                profile: ShareProfile(nickname: "rusl3n", fullName: ""), defaults: defaults,
                                bundle: bundle("en"), locale: Locale(identifier: "en"), appIcon: icon),
             to: "share-speed-en.jpg")
}

/// Три недели занятий: полные дни, половинный, пропуск под заморозкой и начатый сегодняшний день.
private func homeFixture() -> HomeData {
    let today = "2026-10-24"
    var days: [String: DayActivity] = [:]
    for offset in -19...0 {
        let key = StreakCalculator.dayKey(today, offset: offset)
        switch offset {
        case -3: continue                                                        // пропуск: заморозка
        case -5: days[key] = DayActivity(activeSeconds: 240, completedExercises: 2)  // половинный огонь
        case 0: days[key] = DayActivity(activeSeconds: 420, completedExercises: 3)   // сегодня ещё не цель
        default: days[key] = DayActivity(activeSeconds: 900 + Double(offset * 7), completedExercises: 6)
        }
    }
    let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: 600)
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let sessions = (0..<7).map { index in
        SessionSummary(day: StreakCalculator.dayKey(today, offset: -index), endedAt: start, language: .en,
                       mode: .course, chars: 900, activeSeconds: 300, accuracy: 0.965 + Double(index) * 0.002,
                       completed: true, cpm: 168 - Double(index) * 3)
    }
    return HomeData.make(language: .en, streak: streak, days: days, sessions: sessions, today: today,
                         goalMinutes: 10, focus: "k", weakKeys: ["q", "z", "x"], canStartWeakSpots: true,
                         firstSessionDate: start.addingTimeInterval(-19 * 86_400),
                         firstWeekday: 2,
                         weekdaySymbols: HomeData.weekdaySymbols(locale: Locale(identifier: "ru")))
}

/// Статистика букв раскладки: ошибок больше на краях (мизинцы) и в верхнем ряду.
private func heatmapFixture(_ snapshot: LayoutSnapshot) -> [KeyInfo] {
    let entries = snapshot.plain.compactMap { code, label -> KeyStatEntry? in
        guard label.count == 1, let scalar = label.unicodeScalars.first, (0x430...0x44F).contains(scalar.value) || label == "ё"
        else { return nil }
        let x = KeyboardGeometry.position(of: code, shape: .ansi)?.x ?? 6.5
        let edge = min(1, abs(x - 6.5) / 6.5)
        let presses = 400 + Int(code) * 13 % 300
        let errors = Int(Double(presses) * (0.01 + 0.07 * edge * edge + (Int(code) % 5 == 0 ? 0.03 : 0)))
        return KeyStatEntry(character: label, stat: KeyStatSummary(keyCode: code, presses: presses, errors: errors,
                                                                   ewmaMs: 180 + 120 * edge))
    }
    return HeatmapModel.merge(entries)
}

/// План дня: разминка выполнена, остальные пункты впереди.
@MainActor private func dayPlanFixture(course: Course) -> DayPlanCardModel {
    let lesson = course.lessons.dropFirst(5).first { $0.resolvedKind == .keys } ?? course.lessons[5]
    let actions: [PlanAction] = [.review(focus: ["а", "о", "е"], chars: 300), .lesson(lessonId: lesson.id, retake: false),
                                 .adaptive(portions: 2), .text(stageIndex: nil, portions: 1, chars: 450)]
    let items = zip(PlanSlot.allCases, zip(actions, [true, false, false, false])).map {
        PlanItem(slot: $0, action: $1.0, done: $1.1)
    }
    return DayPlanCardModel.make(plan: DayPlan(day: "2026-10-24", items: items, extraRefresh: nil), course: course,
                                 canContinue: true)
}

/// Испытания недели и месяца: часть в пути, одно выполнено, одно трудное.
private func challengesFixture() -> ChallengesCardModel? {
    let parameters = ChallengeParameters(goalMinutes: 10, cpm: 150)
    func result(_ id: ChallengeId, _ progress: Int, _ target: Int) -> ChallengeResult {
        ChallengeResult(id: id, progress: progress, target: target,
                        completedAt: progress >= target ? Date(timeIntervalSince1970: 1_790_000_000) : nil)
    }
    let week = ChallengePeriodResult(period: .week("2026-W43"), parameters: parameters,
                                     results: [result(.weekGoal5, 5, 5), result(.weekChars, 2_400, 5_000),
                                               result(.weekSpeed, 0, 1)], allDoneAt: nil)
    let month = ChallengePeriodResult(period: .month("2026-10"), parameters: parameters,
                                      results: [result(.monthGoal20, 13, 20)], allDoneAt: nil)
    return ChallengesCardModel.make(week: week, month: month, today: "2026-10-24", unit: .cpm)
}

/// Установщик без дела: плашке нужен только `UpdateChecker` в состоянии «доступна версия».
@MainActor private final class IdleInstaller: UpdateInstalling {
    func preflight(manifest: ReleaseManifest) throws {}
    func download(_ manifest: ReleaseManifest, zipURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> URL { zipURL }
    func backup(version: String) throws -> URL { URL(filePath: "/dev/null") }
    func replace(with newApp: URL) throws {}
    func discardDownload(_ newApp: URL) {}
    func relaunch() throws {}
}

/// Проверка обновлений с поддельной сетью и настройками: `offering` новее установленной 2.5.0 — «доступна версия»
/// (вымышленный выпуск), равна ей — «Установлена последняя версия».
@MainActor private func updateChecker(offering version: String, defaults: UserDefaults? = nil) async throws -> UpdateChecker {
    let own = defaults == nil ? makeTestDefaults("readme-update-") : nil
    defer { own.map { removeTestDefaults($0.name) } }
    let manifest = Data("""
    {"format": 1, "version": "\(version)", "build": \(version == "2.5.0" ? 300 : 400), "commit": "abc",
     "schemaGeneration": 6, "minimumSystemVersion": "15.0",
     "zip": {"name": "TenFingers-\(version).zip", "size": 1, "sha256": "aa"},
     "dmg": {"name": "TenFingers-\(version).dmg", "size": 2, "sha256": "bb"}, "notesURL": "https://example.com/notes"}
    """.utf8)
    let checker = UpdateChecker(
        defaults: defaults ?? own!.defaults, fetch: { _ in manifest }, installer: { IdleInstaller() }, now: { Date() },
        info: ["CFBundleShortVersionString": "2.5.0", "CFBundleVersion": "300"],
        systemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0), isBundledApp: true)
    await checker.check(manual: true)
    return checker
}

/// Центр уведомлений без дела: настройкам нужен только планировщик напоминаний.
@MainActor private final class IdleReminderCenter: ReminderCenter {
    func authorization() async -> ReminderAuthorization { .notDetermined }
    func requestAuthorization() async -> ReminderAuthorization { .notDetermined }
    func pending() async -> [ReminderNotification] { [] }
    func removePending(ids: [String]) {}
    func removeAll() {}
    func add(_ notification: ReminderNotification) async {}
}

// MARK: - Новые картинки README: анимация набора, разбор шага, «Ритм», замер

/// Русские переводы строк приложения из Localization/ru.lproj (в тестах `Bundle.main` без переводов приложения).
private func russianAppStrings() throws -> [String: String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/ru.lproj/Localizable.strings")
    return try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
}

/// Кадры анимации набора для hero.gif: текст упражнения и экранная клавиатура с десятью кончиками пальцев (как на
/// знакомстве с клавишами и в повторе замера): кончик идёт к нажимаемой клавише и возвращается домой, пробел жмёт
/// большой палец руки, противоположной предыдущей букве. Пунктирной дуги нет. Кадры — PNG в `HERO_FRAMES_DIR`
/// (по умолчанию временная папка); склейка в GIF — ffmpeg (12 кадров/с).
/// Запуск: RENDER_DOCS=1 swift test --filter renderHeroFrames
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderHeroFrames() throws {
    let env = ProcessInfo.processInfo.environment
    let dir = URL(fileURLWithPath: env["HERO_FRAMES_DIR"] ?? NSTemporaryDirectory() + "hero-frames")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ru = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.RussianWin"))
    let snapshot = KeyboardLayoutService.snapshot(for: ru, shape: .ansi)
    let target = Array("пальцы сами находят клавиши")
    let presses = MeasureReplayModel.presses(keys: target.map { ReplayKey(position: 0, typed: $0, offsetMs: 0) }, snapshot: snapshot)
    let layout = HandsOverlayModel.layout(shape: snapshot.shape)
    let keyFrames = HandsOverlayModel.keyFrames(shape: snapshot.shape)
    // Каждое нажатие — 4 кадра по 100 мс из 400 мс; знак засчитан с третьего кадра (палец уже на клавише).
    let durationMs = 400.0, framesPerKey = 4
    var shots: [(position: Int, active: [ActiveHandsPress])] = [(0, [])]
    for (index, press) in presses.enumerated() {
        guard let press else { continue }
        for k in 0..<framesPerKey {
            let elapsed = Double(k) * durationMs / Double(framesPerKey)
            shots.append((k >= 2 ? index + 1 : index, [ActiveHandsPress(press: press, elapsedMs: elapsed, durationMs: durationMs)]))
        }
    }
    shots += Array(repeating: (target.count, []), count: 14)
    let light = LightPalette.beige.palette
    for (index, shot) in shots.enumerated() {
        let tips = HandsOverlayModel.tips(layout: layout, frames: keyFrames, active: shot.active, moves: true)
        let pressed = HandsOverlayModel.pressedKeys(active: shot.active)
        let spaceHalf = HandsOverlayModel.pressedSpaceHalf(active: shot.active)
        let overlay = Canvas { context, _ in
            for key in pressed {
                guard let frame = keyFrames[key] else { continue }
                var rect = CGRect(x: frame.center.x - frame.width / 2, y: frame.center.y - frame.height / 2,
                                  width: frame.width, height: frame.height)
                if key == KeyboardGeometry.space, let spaceHalf {
                    rect.size.width /= 2
                    if spaceHalf == .right { rect.origin.x += rect.width }
                }
                context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.accentColor), lineWidth: 3)
            }
            for tip in tips {
                let d = layout.diameter(pressing: tip.isDown)
                let rect = CGRect(x: tip.point.x - d / 2, y: tip.point.y - d / 2, width: d, height: d)
                // На светлой теме кружок того же цвета, что клавиша: полная заливка, белое кольцо и тёмный ободок.
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.28)))
                context.fill(Path(ellipseIn: rect), with: .color(FingerPalette.color(tip.finger)))
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: 2)
            }
        }
        let view = VStack(spacing: 10) {
            TypingTextView(target: target, position: shot.position, errorAtCursor: false)
                .frame(width: 700, height: 44, alignment: .leading)
            KeyboardView(snapshot: snapshot, marks: [:], unit: CGFloat(KeyboardSizing.baseUnit))
                .overlay(alignment: .topLeading) { overlay }
            FingerLegend()
        }
        .padding(28)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent(String(format: "frame_%03d.png", index)))
    }
}

/// Разбор шага урока (русский интерфейс): промежуточный экран «Готово: шаг 3 из 7» — скорость и ошибки,
/// график темпа по отрезкам с медленными местами и строки «что получилось / что мешало». Повторяет вёрстку
/// `LessonRunnerView` (сам экран живёт внутри раннера урока). Строки разбора — русские переводы приложения.
/// Запуск: RENDER_DOCS=1 swift test --filter renderLessonReviewImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderLessonReviewImage() throws {
    let strings = try russianAppStrings()
    let text = "щука ищет щель в целом море, а цапля ждёт на мели и смотрит на щеглов у берега реки"
    let speeds: [Double] = [246, 258, 138, 251, 262, 146, 249, 268]
    let step = text.count / speeds.count
    let segments = speeds.enumerated().map { index, cpm in
        SpeedSegment(start: index * step, end: index == speeds.count - 1 ? text.count : (index + 1) * step, cpm: cpm)
    }
    let lines = [ReviewLine(key: "review.fasterThanTarget"),
                 ReviewLine(key: "review.slowest", args: ["щель в целом"]),
                 ReviewLine(key: "review.letters", args: ["щ", "ц"])]
    let screen = StepReviewScreen(lines: lines, segments: segments, slow: SpeedSegments.slow(segments), text: text)
    let light = LightPalette.beige.palette
    try renderHosted(
        VStack(spacing: 16) {
            Text("Готово: шаг 3 из 7").font(.largeTitle.bold())
            Text("\(SpeedUnit.cpm.format(214)) · ошибок: 2").font(.title2).monospacedDigit()
            StepDotsView(current: 3, total: 7)
            SpeedSegmentsChart(screen: screen, unit: .cpm).frame(width: 460)
            VStack(spacing: 4) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(ReviewText.text(lines[index], template: strings[lines[index].key]))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Дальше: Предложения").foregroundStyle(.secondary)
            Button("Дальше") {}.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        width: 760, to: "lesson-review.png"
    )
}

/// Кадр «Ритма»: ноты едут по восьми дорожкам пальцев к линии попадания, оценка «Точно», очки, комбо и здоровье.
/// Запуск: RENDER_DOCS=1 swift test --filter renderRhythmImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderRhythmImage() throws {
    let letters: [Character] = ["ф", "ы", "в", "а", "о", "л", "д", "ж"]
    let lanes = [3, 4, 2, 5, 8, 1, 6, 0, 7]             // 8 — пробел
    let now: TimeInterval = 20
    let notes = lanes.enumerated().map { index, lane in
        RhythmFieldFrame.Note(index: index, time: now + 0.05 + Double(index) * 0.19, scrollSeconds: 2,
                              character: lane == 8 ? " " : letters[lane],
                              lane: lane == 8 ? .space : .finger(lane), missed: false)
    }
    var frame = RhythmFieldFrame()
    frame.trackTime = now
    frame.notes = notes
    frame.laneFlash[3] = 0.7
    frame.label = .init(judgement: .perfect, lane: .finger(3), age: 0.2)
    frame.score = 12_840
    frame.combo = 37
    frame.multiplier = 3
    frame.health = 82
    frame.progress = 0.46
    let light = LightPalette.beige.palette
    try render(
        RhythmFieldCanvas(frame: frame)
            .frame(width: 820, height: 560)
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        to: "rhythm.png"
    )
}

/// Итог замера скорости: скорость, точность, сравнение с первым и прошлым замером и график замеров варианта.
/// Повторяет `MeasureResultView` без прокрутки (`NSHostingView` не меряет высоту `ScrollView`).
/// Запуск: RENDER_DOCS=1 swift test --filter renderMeasureImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderMeasureImage() throws {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let history = [214.0, 231, 246, 252, 271, 286].enumerated().map { index, cpm in
        MeasureHistoryEntry(date: base.addingTimeInterval(Double(index) * 5 * 86_400), cpm: cpm, accuracy: 0.98)
    }
    let comparison = MeasureComparison(toFirst: 72, toPrevious: 15)
    let light = LightPalette.beige.palette
    try renderHosted(
        VStack(spacing: 16) {
            RunSummaryView(title: "Замер скорости", leadingMetrics: [.init(title: "Знаков", value: "1240")],
                           cpm: 286, accuracy: 0.981, errors: 6,
                           lines: MeasureResultText.lines(comparison, unit: .cpm),
                           primaryTitle: "Готово", onPrimary: {},
                           secondaryTitle: "Смотреть запись", onSecondary: {})
            MeasureHistoryChart(entries: history, unit: .cpm).frame(maxWidth: 420)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        width: 760, to: "measure.png"
    )
}
