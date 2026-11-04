import AppKit
import Observation
import SwiftUI

/// Событие паузы активного запуска. `id` растёт с каждым событием, поэтому два одинаковых
/// события подряд различимы для `onChange`.
struct PauseEvent: Equatable {
    let id: Int
    let paused: Bool
    let reason: PauseReason
}

/// Общее состояние активного запуска (урок, тренировка): виден ли он и стоит ли на паузе.
/// `RootView` владеет им и отдаёт через environment; `ExerciseView` сообщает о паузе.
@MainActor @Observable
final class RunPresence {
    /// Экран запуска показан. Скрытый запуск остаётся в иерархии, но без монитора клавиш и на паузе.
    var isVisible = true
    /// Есть активный запуск (виден он или скрыт). Пока он есть, загрузка прогресса из файла недоступна:
    /// запуск держит объекты базы, которые замена удалила бы.
    var hasRun = false
    private(set) var isPaused = false
    /// Последнее событие паузы: по нему `RootView` разворачивает или сворачивает меню.
    private(set) var lastEvent: PauseEvent?

    /// Запуск показывает итоги (пока только «Ритм»): `RootView` разворачивает меню, новый заход сворачивает его.
    private(set) var showsResult = false

    func resultChanged(_ shown: Bool) {
        if showsResult != shown { showsResult = shown }
    }

    func pauseChanged(_ paused: Bool, reason: PauseReason) {
        isPaused = paused
        lastEvent = PauseEvent(id: (lastEvent?.id ?? 0) + 1, paused: paused, reason: reason)
    }

    /// Новый запуск или запуск завершён.
    func reset() {
        isVisible = true
        isPaused = false
    }

    /// Иконка пункта боковой панели: скрытый запуск тоже стоит (на паузе или между экранами).
    var showsPauseIcon: Bool { isPaused || !isVisible }
}

/// Где нажат Esc: решение о возврате к запуску принимается без AppKit-объектов.
struct EscapeTarget: Equatable {
    /// Первый ответчик — текстовое поле или текстовый вид.
    var isEditingText: Bool
    /// Событие пришло в главное окно приложения.
    var isMainWindow: Bool
    /// Окно события — лист, алерт, панель или поповер.
    var isSheetOrPanel: Bool
    /// К окну прикреплён лист (алерт).
    var hasAttachedSheet: Bool

    @MainActor init(window: NSWindow?) {
        let responder = window?.firstResponder
        isEditingText = responder is NSText || responder is NSTextField
        // Локальный монитор получает события только в активном приложении, где главное окно определено;
        // у листа, алерта и поповера своё окно, и оно не главное.
        isMainWindow = window.map { $0 === NSApp.mainWindow } ?? false
        isSheetOrPanel = window.map { $0.sheetParent != nil || $0 is NSPanel } ?? true
        hasAttachedSheet = window?.attachedSheet != nil
    }

    init(isEditingText: Bool, isMainWindow: Bool, isSheetOrPanel: Bool, hasAttachedSheet: Bool) {
        self.isEditingText = isEditingText
        self.isMainWindow = isMainWindow
        self.isSheetOrPanel = isSheetOrPanel
        self.hasAttachedSheet = hasAttachedSheet
    }
}

/// Чистые правила: что делать с боковым меню при паузе и когда Esc возвращает к запуску.
enum SidebarPolicy {
    /// Новая видимость меню после события паузы или `nil`, если менять нечего.
    /// Esc разворачивает меню; снятие паузы, поставленной по Esc или уходом в другой раздел,
    /// сворачивает его обратно. Потеря фокуса меню не трогает.
    private static func visibility(afterPause paused: Bool, reason: PauseReason,
                           current: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility? {
        let target: NavigationSplitViewVisibility
        switch (paused, reason) {
        case (true, .escape): target = .all
        case (false, .escape), (false, .hidden): target = .detailOnly
        case (_, .focusLoss), (_, .layout), (true, .hidden): return nil
        }
        return target == current ? nil : target
    }

    /// Событие паузы применяется к меню только пока запуск есть: после «Выйти» меню восстанавливает
    /// `RootView`, а снятие паузы при остановке сессии приходит позже и не должно его сворачивать.
    /// Пауза скрытого запуска меню не трогает.
    /// Итоги видимого запуска разворачивают меню, новый заход с итогов сворачивает его обратно.
    static func visibility(afterResult shown: Bool, hasRun: Bool, isRunVisible: Bool,
                           current: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility? {
        guard hasRun, isRunVisible else { return nil }
        let target: NavigationSplitViewVisibility = shown ? .all : .detailOnly
        return target == current ? nil : target
    }

    static func visibility(after event: PauseEvent, hasRun: Bool, isRunVisible: Bool,
                           current: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility? {
        guard hasRun, isRunVisible || !event.paused else { return nil }
        return visibility(afterPause: event.paused, reason: event.reason, current: current)
    }

    /// Новый запуск из раздела при скрытом запуске (кнопка или Return) сначала спрашивает подтверждение:
    /// иначе приостановленный урок молча завершился бы. Запуск с экрана самого запуска не спрашивает.
    static func confirmsReplacingRun(hasRun: Bool, isRunVisible: Bool) -> Bool {
        hasRun && !isRunVisible
    }

    /// Esc без модификаторов в главном окне (без листов, алертов и панелей) вне текстового поля
    /// на экране другого раздела возвращает к скрытому запуску.
    static func returnsToRun(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, target: EscapeTarget) -> Bool {
        let significant = modifiers.intersection([.command, .option, .control, .shift])
        return keyCode == ExerciseSession.escapeKeyCode && significant.isEmpty && !target.isEditingText
            && target.isMainWindow && !target.isSheetOrPanel && !target.hasAttachedSheet
    }
}
