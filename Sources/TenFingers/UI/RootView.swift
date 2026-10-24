import AppKit
import SwiftData
import SwiftUI
import TypingCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, course, training, practice, analytics, achievements, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Главная")
        case .course: String(localized: "Курс")
        case .training: String(localized: "Тренировка")
        case .practice: String(localized: "Практика")
        case .analytics: String(localized: "Аналитика")
        case .achievements: String(localized: "Ачивки")
        case .settings: String(localized: "Настройки")
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .course: "graduationcap"
        case .training: "target"
        case .practice: "text.book.closed"
        case .analytics: "chart.xyaxis.line"
        case .achievements: "trophy"
        case .settings: "gearshape"
        }
    }
}

/// Запуск тренировки (адаптивной или слабых мест): новый `id` на каждый запуск.
struct TrainingRun: Identifiable, Equatable {
    let id = UUID()
    let language: Language
}

/// То, что сейчас занимает окно вместо раздела: урок курса, тренировка или практика.
enum RunKind: Identifiable, Equatable {
    case lesson(LessonRun)
    case adaptive(TrainingRun)
    case weakSpots(TrainingRun)
    case practice(PracticeRun)

    /// Новый на каждый запуск: по нему пересоздаётся экран и скрывается боковая панель.
    var id: UUID {
        switch self {
        case .lesson(let run): run.id
        case .adaptive(let run), .weakSpots(let run): run.id
        case .practice(let run): run.id
        }
    }

    /// Пункт боковой панели, который возвращает к запуску.
    var sidebarTitle: String {
        switch self {
        case .lesson: String(localized: "Текущий урок")
        case .adaptive: String(localized: "Тренировка идёт")
        case .weakSpots: String(localized: "Слабые места идут")
        case .practice: String(localized: "Практика идёт")
        }
    }

    /// Заголовок алерта при замене скрытого запуска: называет то, что будет завершено.
    var replaceAlertTitle: String {
        switch self {
        case .lesson: String(localized: "Текущий урок будет завершён. Начать новое занятие?")
        case .adaptive: String(localized: "Тренировка будет завершена. Начать новое занятие?")
        case .weakSpots: String(localized: "Слабые места будут завершены. Начать новое занятие?")
        case .practice: String(localized: "Практика будет завершена. Начать новое занятие?")
        }
    }
}

/// Выбор в боковой панели: активный запуск или раздел.
private enum SidebarEntry: Hashable {
    case run
    case section(SidebarItem)
}

struct RootView: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.uiScale) private var uiScale = UIScale.defaultValue
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @Query(filter: #Predicate<AchievementRecord> { !$0.seen }) private var unseenRecords: [AchievementRecord]
    @State private var selection: SidebarItem? = .home
    @State private var activeRun: RunKind?
    @State private var presence = RunPresence()
    @State private var toasts = ToastCenter()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var visibilityBeforeLesson: NavigationSplitViewVisibility?
    @State private var escapeMonitor: Any?
    /// Новый запуск, ждущий подтверждения (скрытый запуск при этом ещё жив).
    @State private var pendingRun: RunKind?
    /// Карточка «Поделиться», открытая из тоста ачивки.
    @State private var shareCard: ShareCard?

    /// Экран запуска показан вместо раздела.
    private var isRunVisible: Bool { activeRun != nil && presence.isVisible }
    /// Новые ачивки (счётчик у пункта «Ачивки»); скрытые «взрослые» при выключенном юморе не считаются.
    private var unseenAchievements: Int {
        AchievementsListing.unseenIds(catalog: AchievementCatalog.all,
                                      earned: unseenRecords.map(StoredAchievement.init), adultHumor: adultHumor).count
    }
    /// Запуск есть, но пользователь ушёл в другой раздел.
    private var isRunHidden: Bool { activeRun != nil && !presence.isVisible }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                if let run = activeRun {
                    Section {
                        Label(run.sidebarTitle, systemImage: presence.showsPauseIcon ? "pause.circle" : "play.circle")
                            .tag(SidebarEntry.run)
                    }
                }
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .badge(item == .achievements ? unseenAchievements : 0)
                            .tag(SidebarEntry.section(item))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Picker("Курс", selection: $activeLanguage) {
                        ForEach(Language.allCases) { Text($0.shortName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(AppVersion.short(info: AppVersion.current))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // Масштабируется содержимое раздела; боковая панель и заголовок окна — оформление окна, как в браузере.
            detail
                .uiScaled(uiScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
        }
        .environment(presence)
        .environment(toasts)
        .overlay { ToastOverlay(toasts: toasts) }
        .onChange(of: activeRun?.id) { _, runId in
            presence.hasRun = runId != nil
            ReminderPresenter.shared.setRunActive(runId != nil)
            if runId != nil {
                if visibilityBeforeLesson == nil { visibilityBeforeLesson = columnVisibility }
                withAnimation { columnVisibility = .detailOnly }
            } else if let previous = visibilityBeforeLesson {
                withAnimation { columnVisibility = previous }
                visibilityBeforeLesson = nil
            }
        }
        .onChange(of: presence.lastEvent) { _, event in
            guard let event,
                  let next = SidebarPolicy.visibility(after: event, hasRun: activeRun != nil,
                                                      isRunVisible: isRunVisible, current: columnVisibility)
            else { return }
            withAnimation { columnVisibility = next }
        }
        .onChange(of: isRunHidden, initial: true) { _, hidden in
            if hidden { installEscapeMonitor() } else { removeEscapeMonitor() }
        }
        .onDisappear(perform: removeEscapeMonitor)
        .shareSheet($shareCard)
        // Первый запуск версии с ачивками выдаёт всё заработанное задним числом (одна сводка вместо лавины тостов).
        // Кнопка «Поделиться» в тостах ачивок открывает карточку здесь.
        .task {
            toasts.shareAchievement = { shareCard = ShareCard(.achievement($0, .now)) }
            AchievementAnnouncer.launchCheck(service: .live(context: modelContext), toasts: toasts,
                                             adultHumor: StoredSettings.adultHumor(), open: openAchievements)
        }
        // Загрузка прогресса из файла (`ProgressImporter`): ачивки выдаются заново, сводкой.
        .onReceive(NotificationCenter.default.publisher(for: .progressReplaced)) { _ in
            AchievementAnnouncer.progressReplaced(service: .live(context: modelContext), toasts: toasts,
                                                  adultHumor: StoredSettings.adultHumor(), open: openAchievements)
        }
        .alert(activeRun?.replaceAlertTitle ?? "",
               isPresented: Binding(get: { pendingRun != nil }, set: { if !$0 { pendingRun = nil } }),
               presenting: pendingRun) { run in
            Button("Начать новое", role: .destructive) { replaceRun(with: run) }
            // Return нажимает «Отмена», а не разрушительную кнопку: случайный Return не должен терять запуск.
            Button("Отмена", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Переход в раздел при активном запуске не завершает его, а только скрывает (запуск встаёт на паузу).
    private var sidebarSelection: Binding<SidebarEntry?> {
        Binding(
            get: { isRunVisible ? .run : selection.map(SidebarEntry.section) },
            set: { entry in
                switch entry {
                case .run: presence.isVisible = true
                case .section(let item):
                    selection = item
                    if activeRun != nil { presence.isVisible = false }
                case nil: break
                }
            })
    }

    @ViewBuilder private var detail: some View {
        if let error = library.loadError {
            ContentUnavailableView("Не удалось загрузить данные", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else {
            // Запуск всегда в иерархии, пока он есть: при уходе в раздел его @State и сессия живут,
            // а onDisappear (запись брошенного упражнения) срабатывает только при настоящем завершении.
            ZStack {
                if let run = activeRun {
                    let visible = presence.isVisible
                    runner(run).id(run.id)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .disabled(!visible)
                        .accessibilityHidden(!visible)
                }
                if !isRunVisible { section }
            }
        }
    }

    @ViewBuilder private var section: some View {
        switch selection ?? .home {
        case .home: HomeView(start: { start($0) }, navigate: { selection = $0 })
        case .course: CourseMapView(start: { start(.lesson($0)) })
        case .training: TrainingView(start: { start($0) })
        case .practice: PracticeView(start: { start($0) })
        case .analytics: AnalyticsView()
        case .achievements: AchievementsView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder private func runner(_ run: RunKind) -> some View {
        switch run {
        case .lesson(let lesson):
            LessonRunnerView(run: lesson, onExit: end, onStart: { start(.lesson($0)) })
        case .adaptive(let training):
            AdaptiveRunnerView(language: training.language, onExit: end)
        case .weakSpots(let training):
            WeakSpotsRunnerView(language: training.language, onExit: end)
        case .practice(let practice):
            PracticeRunnerView(run: practice, onExit: end)
        }
    }

    /// Новый запуск заменяет прежний (тот записывается как брошенный в onDisappear своего раннера).
    /// Если прежний запуск скрыт, сначала спрашиваем: его легко заменить случайно (Return в разделе).
    private func start(_ run: RunKind) {
        if SidebarPolicy.confirmsReplacingRun(hasRun: activeRun != nil, isRunVisible: presence.isVisible) {
            pendingRun = run
        } else {
            replaceRun(with: run)
        }
    }

    /// Состояние сбрасываем до показа, чтобы новый экран не появился скрытым и на паузе.
    private func replaceRun(with run: RunKind) {
        pendingRun = nil
        presence.reset()
        activeRun = run
    }

    /// Раздел «Ачивки»; идущий запуск при этом скрывается (как при выборе раздела в боковой панели).
    private func openAchievements() {
        selection = .achievements
        if activeRun != nil { presence.isVisible = false }
    }

    /// «Выйти» или итог запуска закрыт.
    private func end() {
        presence.reset()
        activeRun = nil
    }

    /// Esc на экране другого раздела возвращает к скрытому запуску. В текстовом поле, листе, алерте,
    /// поповере и других окнах Esc не перехватываем.
    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [presence] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard !presence.isVisible,
                      SidebarPolicy.returnsToRun(keyCode: keyCode, modifiers: modifiers,
                                                 target: EscapeTarget(window: event.window)) else { return false }
                presence.isVisible = true
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
