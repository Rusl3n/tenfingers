import SwiftData
import SwiftUI

@main
struct TenFingersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var layout = KeyboardLayoutService()
    @State private var library = ContentLibrary()
    @State private var sound = SoundPlayer()
    @State private var systemAppearance = SystemAppearance()
    @State private var reminders: ReminderScheduler
    /// `nil`, если базу открыть нельзя: тогда вместо приложения окно с ошибкой, а база не трогается.
    private let container: ModelContainer?
    private let storeError: String?

    init() {
        // Язык интерфейса фиксируется до всего остального: дальше настройка может меняться, а язык сессии — нет.
        _ = InterfaceLanguage.atLaunch
        let defaults = UserDefaults.standard
        if defaults.string(forKey: SettingsKey.themeMode) == nil,
           let old = defaults.string(forKey: SettingsKey.legacyTheme),
           ThemeMode(rawValue: old) != nil {
            defaults.set(old, forKey: SettingsKey.themeMode)
        }
        do {
            container = try ModelStore.makeContainer()
            storeError = nil
        } catch ModelStoreError.newerStore, ModelStoreError.newerGeneration {
            container = nil
            storeError = String(localized: "Прогресс сохранён более новой версией приложения. Установите последнюю версию.")
        } catch ModelStoreError.unreadableGeneration {
            container = nil
            storeError = String(localized: "Не удалось прочитать версию базы прогресса. Установите последнюю версию приложения.")
        } catch {
            container = nil
            storeError = String(localized: "Не удалось открыть сохранённый прогресс: \(error.localizedDescription)")
        }
        // Дни до поколения схемы 5 получают текущую цель (один раз: дни с целью не трогаются).
        if let container { DayGoals.backfillLogging(context: container.mainContext) }
        let scheduler = ReminderScheduler.live(context: container?.mainContext)
        _reminders = State(initialValue: scheduler)
        // Запуск: пересчёт напоминаний. Разрешение здесь не запрашивается, только читается.
        scheduler.rescheduleSoon()
    }

    var body: some Scene {
        // Одно окно: монитор клавиш упражнения общий для всего приложения.
        Window(String(localized: "Десять пальцев"), id: "main") {
            ThemedRoot(system: systemAppearance) {
                if let container {
                    RootView()
                        .environment(layout)
                        .environment(library)
                        .environment(sound)
                        .environment(reminders)
                        .modelContainer(container)
                } else {
                    StoreErrorView(message: storeError ?? "")
                }
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О программе «Десять пальцев»") { AboutPanel.show() }
            }
        }
    }
}

/// Базу открыть нельзя: объясняем, что делать, и ничего не записываем.
private struct StoreErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось открыть прогресс", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Text("Резервные копии прогресса лежат в папке ~/Library/Application Support/TenFingers.backups")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Показать в Finder") { Self.revealBackups() }
                Button("Закрыть приложение") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Папка резервных копий, а если её ещё нет, — папка с данными приложения (Finder откроется в ней).
    private static func revealBackups() {
        let support = URL.applicationSupportDirectory
        let backups = support.appending(path: "TenFingers.backups", directoryHint: .isDirectory)
        let target = FileManager.default.fileExists(atPath: backups.path)
            ? backups : support.appending(path: "TenFingers", directoryHint: .isDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

/// Применяет тему: режим, расписание и палитру. Системная схема читается из настроек системы
/// (`SystemAppearance`), внешний вид окна задаётся через `NSApp.appearance`.
private struct ThemedRoot<Content: View>: View {
    let system: SystemAppearance
    @AppStorage(SettingsKey.themeMode) private var themeMode = ThemeMode.system.rawValue
    @AppStorage(SettingsKey.lightPalette) private var lightPalette = LightPalette.white.rawValue
    @AppStorage(SettingsKey.darkPalette) private var darkPalette = DarkPalette.graphite.rawValue
    @AppStorage(SettingsKey.darkFromHour) private var darkFrom = SettingsDefault.darkFromHour
    @AppStorage(SettingsKey.darkToHour) private var darkTo = SettingsDefault.darkToHour
    @AppStorage(SettingsKey.uiScale) private var uiScale = UIScale.defaultValue
    @ViewBuilder let content: Content

    /// Минимальный размер окна растёт с масштабом интерфейса (в пределах видимой области экрана).
    private var minimumSize: CGSize {
        UIScale.minimumWindowSize(scale: uiScale, visible: NSScreen.main?.visibleFrame.size)
    }

    var body: some View {
        // Читаем до замыкания TimelineView, чтобы Observation гарантированно отслеживал свойство.
        let systemIsDark = system.isDark
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let mode = ThemeMode(rawValue: themeMode) ?? .system
            let hour = Calendar.current.component(.hour, from: timeline.date)
            let isDark = ThemeResolver.isDark(mode: mode, systemIsDark: systemIsDark,
                                              hour: hour, darkFrom: darkFrom, darkTo: darkTo)
            let palette = isDark
                ? (DarkPalette(rawValue: darkPalette) ?? .graphite).palette
                : (LightPalette(rawValue: lightPalette) ?? .white).palette
            content
                .environment(\.palette, palette)
                .onChange(of: ThemeResolver.appearanceName(mode: mode, isDark: isDark), initial: true) { _, name in
                    NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
                }
        }
        .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
    }
}
