import AppKit
import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

@MainActor
private func makeSession(_ text: String = "ао") -> ExerciseSession {
    let session = ExerciseSession(spec: ExerciseSpec(id: 0, kind: .words, title: "t", text: text),
                                  language: .ru, mode: .course, lessonId: "ru.1.1", hint: .full)
    session.layoutLanguage = .ru
    return session
}

@MainActor
private func record(_ session: ExerciseSession) -> () -> [String] {
    var events: [String] = []
    session.onPauseChanged = { paused, reason in events.append("\(paused) \(reason)") }
    return { events }
}

// MARK: - SidebarPolicy

/// Событие паузы запуска, который есть и виден (единственная публичная точка входа политики).
private func sidebar(paused: Bool, reason: PauseReason,
                     current: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility? {
    SidebarPolicy.visibility(after: PauseEvent(id: 1, paused: paused, reason: reason), hasRun: true,
                             isRunVisible: true, current: current)
}

@Test func resultExpandsSidebarAndNextRunCollapsesIt() {
    #expect(SidebarPolicy.visibility(afterResult: true, hasRun: true, isRunVisible: true, current: .detailOnly) == .all)
    #expect(SidebarPolicy.visibility(afterResult: false, hasRun: true, isRunVisible: true, current: .all) == .detailOnly)
    #expect(SidebarPolicy.visibility(afterResult: true, hasRun: true, isRunVisible: true, current: .all) == nil)
    // Скрытый запуск и запуск, которого уже нет, меню не трогают.
    #expect(SidebarPolicy.visibility(afterResult: true, hasRun: true, isRunVisible: false, current: .detailOnly) == nil)
    #expect(SidebarPolicy.visibility(afterResult: false, hasRun: false, isRunVisible: true, current: .all) == nil)
}

@Test func escapePauseExpandsSidebar() {
    #expect(sidebar(paused: true, reason: .escape, current: .detailOnly) == .all)
}

@Test func resumeAfterEscapePauseCollapsesSidebar() {
    #expect(sidebar(paused: false, reason: .escape, current: .all) == .detailOnly)
}

@Test func layoutPauseLeavesSidebarAlone() {
    #expect(sidebar(paused: true, reason: .layout, current: .detailOnly) == nil)
    #expect(sidebar(paused: false, reason: .layout, current: .detailOnly) == nil)
    #expect(sidebar(paused: true, reason: .layout, current: .all) == nil)
}

@Test func focusLossPauseLeavesSidebarAlone() {
    #expect(sidebar(paused: true, reason: .focusLoss, current: .detailOnly) == nil)
    #expect(sidebar(paused: false, reason: .focusLoss, current: .detailOnly) == nil)
}

@Test func hidingPauseLeavesSidebarAloneButResumeCollapsesIt() {
    #expect(sidebar(paused: true, reason: .hidden, current: .all) == nil)
    #expect(sidebar(paused: false, reason: .hidden, current: .all) == .detailOnly)
}

@Test func policyReturnsNilWhenSidebarAlreadyInPlace() {
    #expect(sidebar(paused: true, reason: .escape, current: .all) == nil)
    #expect(sidebar(paused: false, reason: .escape, current: .detailOnly) == nil)
}

private let mainWindow = EscapeTarget(isEditingText: false, isMainWindow: true, isSheetOrPanel: false,
                                      hasAttachedSheet: false)

@Test func plainEscapeInMainWindowOutsideTextReturnsToRun() {
    #expect(SidebarPolicy.returnsToRun(keyCode: 53, modifiers: [], target: mainWindow))
    #expect(SidebarPolicy.returnsToRun(keyCode: 53, modifiers: .capsLock, target: mainWindow))
}

@Test func escapeInTextFieldOrWithModifiersIsNotHijacked() {
    var editing = mainWindow
    editing.isEditingText = true
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: [], target: editing))
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: .command, target: mainWindow))
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: .option, target: mainWindow))
    #expect(!SidebarPolicy.returnsToRun(keyCode: 36, modifiers: [], target: mainWindow))
}

@Test func escapeInSheetPanelOrOtherWindowIsNotHijacked() {
    var other = mainWindow
    other.isMainWindow = false
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: [], target: other))
    var sheet = mainWindow
    sheet.isSheetOrPanel = true
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: [], target: sheet))
    var withSheet = mainWindow
    withSheet.hasAttachedSheet = true
    #expect(!SidebarPolicy.returnsToRun(keyCode: 53, modifiers: [], target: withSheet))
}

// MARK: - ExerciseSession pause callbacks

@MainActor @Test func escapeReportsPauseAndNextKeyReportsResume() {
    let session = makeSession()
    let events = record(session)
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0)
    #expect(events() == ["true escape"])
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 1)
    #expect(events() == ["true escape", "false escape"])
    #expect(session.engine.position == 0)
}

@MainActor @Test func secondEscapeReportsResume() {
    let session = makeSession()
    let events = record(session)
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0)
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 1)
    #expect(!session.isPaused)
    #expect(events() == ["true escape", "false escape"])
}

@MainActor @Test func focusLossReportsItsReason() {
    let session = makeSession()
    let events = record(session)
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    session.pauseForFocusLoss()
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 1)
    #expect(events() == ["true focusLoss", "false focusLoss"])
}

@MainActor @Test func hidingPausesEvenBeforeStartAndKeepsEscapeReason() {
    let fresh = makeSession()
    let freshEvents = record(fresh)
    fresh.pauseForHiding()
    #expect(fresh.isPaused)
    #expect(freshEvents() == ["true hidden"])

    let escaped = makeSession()
    let events = record(escaped)
    _ = escaped.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0)
    escaped.pauseForHiding()
    _ = escaped.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 1)
    #expect(events() == ["true escape", "false escape"])
}

@MainActor @Test func hidingAfterFocusLossResumesAsHidden() {
    let session = makeSession()
    let events = record(session)
    _ = session.handleKey(characters: "а", keyCode: 3, modifiers: [], timestamp: 0)
    session.pauseForFocusLoss()
    session.pauseForHiding()
    _ = session.handleKey(characters: "о", keyCode: 38, modifiers: [], timestamp: 1)
    #expect(events() == ["true focusLoss", "false hidden"])
}

@MainActor @Test func stoppingPausedSessionReportsResume() {
    let session = makeSession()
    let events = record(session)
    _ = session.handleKey(characters: "\u{1b}", keyCode: 53, modifiers: [], timestamp: 0)
    session.stop()
    #expect(!session.isPaused)
    #expect(events() == ["true escape", "false escape"])
    session.stop()
    #expect(events().count == 2)
}

@MainActor @Test func stoppingRunningSessionReportsNothing() {
    let session = makeSession()
    let events = record(session)
    session.stop()
    #expect(events().isEmpty)
}

@MainActor @Test func stoppedSessionIsNotPausedByHiding() {
    let session = makeSession()
    session.stop()
    session.pauseForHiding()
    #expect(!session.isPaused)
}

// MARK: - RunPresence

@MainActor @Test func presenceTracksPause() {
    let presence = RunPresence()
    #expect(presence.isVisible && !presence.isPaused)
    presence.pauseChanged(true, reason: .escape)
    #expect(presence.isPaused)
    #expect(presence.lastEvent?.paused == true && presence.lastEvent?.reason == .escape)
    presence.pauseChanged(false, reason: .escape)
    #expect(!presence.isPaused)
}

@MainActor @Test func sidebarIconShowsPauseWhenPausedOrHidden() {
    let presence = RunPresence()
    #expect(!presence.showsPauseIcon)
    presence.isVisible = false
    #expect(presence.showsPauseIcon)
    presence.isVisible = true
    presence.pauseChanged(true, reason: .focusLoss)
    #expect(presence.showsPauseIcon)
}

@MainActor @Test func presenceEventsAreDistinctAndResetClearsState() {
    let presence = RunPresence()
    presence.pauseChanged(true, reason: .escape)
    let first = presence.lastEvent
    presence.pauseChanged(false, reason: .escape)
    presence.pauseChanged(true, reason: .escape)
    #expect(presence.lastEvent != first)
    presence.isVisible = false
    presence.reset()
    #expect(presence.isVisible && !presence.isPaused)
}

@Test func runKindSidebarTitles() {
    #expect(RunKind.lesson(LessonRun(language: .ru, lessonId: "ru.1.1")).sidebarTitle == "Текущий урок")
    #expect(RunKind.adaptive(TrainingRun(language: .ru)).sidebarTitle == "Тренировка идёт")
    #expect(RunKind.weakSpots(TrainingRun(language: .ru)).sidebarTitle == "Слабые места идут")
    #expect(RunKind.practice(PracticeRun(language: .ru, source: .frequentWords)).sidebarTitle == "Практика идёт")
}

@Test func sidebarPolicyIgnoresEventsAfterRunEnded() {
    let resume = PauseEvent(id: 1, paused: false, reason: .escape)
    // Esc → «Выйти»: снятие паузы при остановке приходит, когда запуска уже нет — меню не трогаем.
    #expect(SidebarPolicy.visibility(after: resume, hasRun: false, isRunVisible: false, current: .all) == nil)
    #expect(SidebarPolicy.visibility(after: resume, hasRun: true, isRunVisible: true, current: .all) == .detailOnly)
}

@Test func sidebarPolicyIgnoresPausesOfHiddenRun() {
    let pause = PauseEvent(id: 1, paused: true, reason: .escape)
    #expect(SidebarPolicy.visibility(after: pause, hasRun: true, isRunVisible: false, current: .detailOnly) == nil)
    #expect(SidebarPolicy.visibility(after: pause, hasRun: true, isRunVisible: true, current: .detailOnly) == .all)
}

@Test func newRunAsksOnlyWhenAnotherRunIsHidden() {
    #expect(SidebarPolicy.confirmsReplacingRun(hasRun: true, isRunVisible: false))
    // Следующий урок из итога (запуск на экране) и первый запуск не спрашивают.
    #expect(!SidebarPolicy.confirmsReplacingRun(hasRun: true, isRunVisible: true))
    #expect(!SidebarPolicy.confirmsReplacingRun(hasRun: false, isRunVisible: false))
}

@Test func sidebarButtonShowsCollapsedSidebarAndHidesOtherwise() {
    #expect(SidebarPolicy.isCollapsed(.detailOnly))
    #expect(!SidebarPolicy.isCollapsed(.all))
    #expect(!SidebarPolicy.isCollapsed(.doubleColumn))
    #expect(!SidebarPolicy.isCollapsed(.automatic))
    #expect(SidebarPolicy.toggled(.detailOnly) == .all)
    #expect(SidebarPolicy.toggled(.all) == .detailOnly)
    #expect(SidebarPolicy.toggled(.automatic) == .detailOnly)
}

@Test func sidebarAnimatesOnlyOutsideFullScreen() {
    #expect(SidebarPolicy.animatesSidebar(isFullScreen: false))
    #expect(!SidebarPolicy.animatesSidebar(isFullScreen: true))
}
