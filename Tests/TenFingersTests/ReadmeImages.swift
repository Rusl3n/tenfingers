import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

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
func renderReadmeImages() throws {
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

    // Главная с серией: прокрутку `ImageRenderer` не рисует, поэтому — `HomeContent.column`.
    // Курс английский: строки ядра (название языка) в тестах берутся на языке системы, а «English» читается
    // одинаково в любом интерфейсе. Остальные строки — исходные русские.
    try render(
        HomeContent(data: homeFixture(), continueInfo: ContinueInfo(
                        lessonTitle: "Буквы E и N", stageTitle: "Основной ряд", percent: 23,
                        lessonRun: LessonRun(language: .en, lessonId: "en.1.3")),
                    unit: .cpm, startLesson: { _ in }, openTraining: {}, startWeakSpots: {}, openPractice: {})
            .column
            .frame(width: 820)
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        to: "home.png"
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

/// Экран «Ачивки» (русский интерфейс): часть полученных, остальные — силуэтами с условием; видны первые строки
/// сетки. Названия и условия берутся из ресурсов ядра на русском (в тестах строки ядра идут на языке процесса).
/// Запуск: RENDER_DOCS=1 swift test --filter renderAchievementsImage
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderAchievementsImage() throws {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let ids = ["streak.3", "streak.7", "streak.14", "speed.ru.100", "speed.ru.150", "speed.en.100", "accuracy.sniper",
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
            AchievementEntry(
                achievement: entry.achievement, unlockedAt: entry.unlockedAt, seen: entry.seen,
                lockedText: AchievementConditionText.describe(entry.achievement.condition,
                                                              display: entry.achievement.lettersDisplay,
                                                              localization: "ru"),
                title: ruStrings[entry.achievement.titleKey])
        }
    let light = LightPalette.beige.palette
    try render(
        AchievementsContent(entries: entries, category: .constant(nil), filter: .constant(.all), freshIds: [],
                            select: { _ in })
            .frame(width: 900, height: 800, alignment: .top)
            .clipped()
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        to: "achievements.png"
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
