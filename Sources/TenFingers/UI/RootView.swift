import SwiftUI
import TypingCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, course, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Главная")
        case .course: String(localized: "Курс")
        case .settings: String(localized: "Настройки")
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .course: "graduationcap"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @State private var selection: SidebarItem? = .home
    @State private var activeRun: LessonRun?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var visibilityBeforeLesson: NavigationSplitViewVisibility?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .safeAreaInset(edge: .bottom) {
                Picker("Курс", selection: $activeLanguage) {
                    ForEach(Language.allCases) { Text($0.shortName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
        }
        .onChange(of: selection) { activeRun = nil }
        .onChange(of: activeRun?.id) { _, runId in
            if runId != nil {
                if visibilityBeforeLesson == nil { visibilityBeforeLesson = columnVisibility }
                withAnimation { columnVisibility = .detailOnly }
            } else if let previous = visibilityBeforeLesson {
                withAnimation { columnVisibility = previous }
                visibilityBeforeLesson = nil
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let error = library.loadError {
            ContentUnavailableView("Не удалось загрузить данные", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let run = activeRun {
            LessonRunnerView(run: run, onExit: { activeRun = nil }, onStart: { activeRun = $0 })
                .id(run.id)
        } else {
            switch selection ?? .home {
            case .home: HomeView(start: { activeRun = $0 })
            case .course: CourseMapView(start: { activeRun = $0 })
            case .settings: SettingsView()
            }
        }
    }
}
