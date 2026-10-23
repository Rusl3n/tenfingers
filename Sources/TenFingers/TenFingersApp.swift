import SwiftData
import SwiftUI

@main
struct TenFingersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var layout = KeyboardLayoutService()
    @State private var library = ContentLibrary()
    @State private var sound = SoundPlayer()
    @State private var systemAppearance = SystemAppearance()
    private let container: ModelContainer

    init() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: SettingsKey.themeMode) == nil,
           let old = defaults.string(forKey: SettingsKey.legacyTheme),
           ThemeMode(rawValue: old) != nil {
            defaults.set(old, forKey: SettingsKey.themeMode)
        }
        do {
            container = try ModelStore.makeContainer()
        } catch {
            fatalError("Failed to open the data store: \(error)")
        }
    }

    var body: some Scene {
        // Одно окно: монитор клавиш упражнения общий для всего приложения.
        Window(String(localized: "Десять пальцев"), id: "main") {
            ThemedRoot(system: systemAppearance) {
                RootView()
                    .environment(layout)
                    .environment(library)
                    .environment(sound)
            }
                .frame(minWidth: 960, minHeight: 640)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
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
    @ViewBuilder let content: Content

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
    }
}
