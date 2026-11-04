import AppKit
import Foundation
import Observation
import TypingCore

/// Шаг установки, который видит пользователь (7b, §5.3 шаг 9).
enum UpdateStep: Equatable, Sendable {
    /// Доля 0…1.
    case downloading(Double)
    case verifying
    case backingUp
    case installing
}

/// Ошибка получения `release.json`: ответ сервера не 2xx.
enum UpdateFetchError: Error, Equatable {
    case http(Int)
}

/// Живая загрузка `release.json`: `https://` через `URLSession`, `file://` читается с диска (для проверки на своей сборке).
enum UpdateFeed {
    static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateFetchError.http(http.statusCode)
        }
        return data
    }
}

/// Проверка обновлений, плашка и ход установки (7b, §5.1–5.3). Решения о том, что предлагать, принимает
/// `UpdatePolicy`; шаги установки делает `UpdateInstalling` (в тестах поддельный).
@MainActor @Observable final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseManifest)
        /// Причина (ручная проверка).
        case failed(String)
        /// Сборка для разработки: обновления выключены.
        case development
        case installing(UpdateStep)
        case installFailed(UpdateError)
    }

    static let defaultFeedURL = URL(string: "https://github.com/Rusl3n/tenfingers/releases/latest/download/release.json")!

    private(set) var state: State
    /// Папка резервной копии этой попытки установки (после шага «Резервная копия»); `nil` — копии ещё нет.
    private(set) var backupFolder: URL?
    /// Версия, пропущенная пользователем и новее установленной: настройки показывают, что она есть, но скрыта.
    private(set) var skippedOffer: String?
    /// Последнее предложенное описание выпуска (страница «Что нового», возврат после ошибки).
    private(set) var offer: ReleaseManifest?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @MainActor (URL) async throws -> Data
    @ObservationIgnored private let makeInstaller: @MainActor () -> any UpdateInstalling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let installedVersion: String?
    @ObservationIgnored private let installedBuild: Int
    @ObservationIgnored private let systemVersion: OperatingSystemVersion
    @ObservationIgnored private let isDevelopment: Bool
    @ObservationIgnored private let isBundledApp: Bool
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var checkInFlight = false

    /// `info` — `Info.plist` бандла (`AppVersion.current`); без версии (`swift run`) и вне `.app` считается сборкой
    /// для разработки: заменять нечего.
    init(defaults: UserDefaults, fetch: @escaping @MainActor (URL) async throws -> Data,
         installer: @escaping @MainActor () -> any UpdateInstalling, now: @escaping () -> Date,
         info: [String: Any] = AppVersion.current,
         systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
         isBundledApp: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.defaults = defaults
        self.fetch = fetch
        self.makeInstaller = installer
        self.now = now
        let version = (info[AppVersion.versionKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        installedVersion = version
        installedBuild = (info[AppVersion.buildKey] as? String).flatMap { Int($0) } ?? 0
        self.systemVersion = systemVersion
        self.isBundledApp = isBundledApp
        isDevelopment = !isBundledApp || UpdatePolicy.isDevelopmentBuild(version: version)
        state = .idle
        if feedURL == nil { state = .development }
    }

    // MARK: Источник

    /// Сборка `-dev`: только заданный `updateFeedURL` (и только из настоящего `.app`); без него — `nil`.
    /// Обычная сборка: всегда общий адрес, `updateFeedURL` игнорируется.
    var feedURL: URL? {
        guard isDevelopment else { return Self.defaultFeedURL }
        guard isBundledApp, let text = defaults.string(forKey: SettingsKey.updateFeedURL),
              let url = URL(string: text), ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    /// Архив лежит рядом с `release.json`: работает и для `https://`, и для `file://`.
    func zipURL(for manifest: ReleaseManifest) -> URL? {
        let name = manifest.zip.name
        guard let feedURL, !name.isEmpty, !name.contains("/"), name != "..", name != "." else { return nil }
        return feedURL.deletingLastPathComponent().appending(path: name)
    }

    // MARK: Проверка

    /// Автоматическая проверка: если включена, с прошлой успешной прошло не меньше 20 часов, не идёт установка.
    func checkIfDue() {
        guard defaults.object(forKey: SettingsKey.updateAutoCheck) as? Bool ?? SettingsDefault.updateAutoCheck,
              UpdatePolicy.shouldAutoCheck(lastCheck: defaults.object(forKey: SettingsKey.updateLastCheck) as? Date,
                                           now: now()) else { return }
        checkTask = Task { await check(manual: false) }
    }

    /// «Проверить сейчас»: ошибка показывается.
    func checkNow() {
        checkTask = Task { await check(manual: true) }
    }

    /// Через 10 секунд после запуска, затем раз в сутки, пока приложение открыто.
    func startSchedule(initialDelay: Duration = .seconds(10)) {
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(for: .seconds(UpdatePolicy.autoCheckInterval))
            }
        }
    }

    func waitForCheck() async { await checkTask?.value }
    func waitForInstall() async { await installTask?.value }

    func check(manual: Bool) async {
        guard let feed = feedURL else { state = .development; return }
        if case .installing = state { return }
        if !manual, case .installFailed = state { return }
        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }
        let previous = state
        // Пока плашка «Доступна версия» на экране, повторная проверка её не убирает.
        if case .available = previous {} else if manual { state = .checking }
        do {
            let manifest = try ReleaseManifest.decode(try await fetch(feed))
            defaults.set(now(), forKey: SettingsKey.updateLastCheck)
            // Установка началась, пока шёл запрос: её состояние проверка не трогает.
            if case .installing = state { return }
            apply(manifest, manual: manual, previous: previous)
        } catch {
            if manual { state = .failed(Self.reason(for: error)) } else { restore(previous) }
        }
    }

    private func apply(_ manifest: ReleaseManifest, manual: Bool, previous: State) {
        skippedOffer = nil
        let decision = UpdatePolicy.decide(
            manifest: manifest, installedVersion: installedVersion ?? "0.0.0", installedBuild: installedBuild,
            systemVersion: systemVersion, skippedVersion: defaults.string(forKey: SettingsKey.updateSkippedVersion),
            allowDevelopment: isDevelopment)
        switch decision {
        case .available(let release):
            offer = release
            state = .available(release)
        case .upToDate:
            state = .upToDate
        case .developmentBuild:
            state = .development
        case .unsupported(.skipped):
            // Пропущена версия не новее установленной (например, пропустили, а потом поставили вручную): всё свежо.
            if let installed = installedVersion.flatMap(SemanticVersion.init),
               let offered = SemanticVersion(manifest.version), installed >= offered {
                state = .upToDate
            } else {
                skippedOffer = manifest.version
                state = .idle
            }
        case .unsupported(.format):
            if manual { state = .failed(String(localized: "Формат описания выпуска не поддерживается этой версией")) } else { restore(previous) }
        case .unsupported(.system):
            if manual { state = .failed(String(localized: "Новая версия требует более новой macOS")) } else { restore(previous) }
        }
    }

    /// Тихая неудача автоматической проверки: прежнее предложение остаётся, остальное — как до проверки.
    private func restore(_ previous: State) {
        switch previous {
        case .available, .upToDate, .development: state = previous
        default: state = .idle
        }
    }

    private static func reason(for error: any Error) -> String {
        switch error {
        case UpdateFetchError.http(404): String(localized: "информации о выпусках пока нет")
        case UpdateFetchError.http(let code): String(localized: "сервер ответил кодом \(code)")
        case is DecodingError: String(localized: "ответ сервера не распознан")
        default: error.localizedDescription
        }
    }

    // MARK: Действия с предложением

    func skip() {
        guard case .available(let manifest) = state else { return }
        defaults.set(manifest.version, forKey: SettingsKey.updateSkippedVersion)
        skippedOffer = nil
        state = .idle
    }

    /// «Что нового»: страница выпуска в браузере (она же — «Открыть страницу релиза» при ошибке размещения).
    func openNotes() {
        guard let offer else { return }
        NSWorkspace.shared.open(offer.notesURL)
    }

    /// Закрывает сообщение об ошибке установки: к предложению, а если новая версия уже стоит, — в покой.
    func dismissFailure() {
        guard case .installFailed(let error) = state else { return }
        if case .relaunchFailed = error { state = .idle } else if let offer { state = .available(offer) } else { state = .idle }
    }

    // MARK: Установка

    var showsBanner: Bool {
        switch state {
        case .available, .installing, .installFailed: true
        default: false
        }
    }

    /// «Отмена» работает до шага замены.
    var canCancel: Bool {
        guard case .installing(let step) = state else { return false }
        return step != .installing
    }

    func install() {
        guard installTask == nil, case .available = state else { return }
        installTask = Task {
            await performInstall()
            installTask = nil
        }
    }

    func cancel() {
        guard canCancel else { return }
        installTask?.cancel()
    }

    /// preflight → download → backup → replace → relaunch; останавливается на первой ошибке. До `replace` любая
    /// ошибка или отмена оставляют приложение и базу как были.
    func performInstall() async {
        guard case .available(let manifest) = state else { return }
        guard let zip = zipURL(for: manifest) else { state = .installFailed(.badBundle("zip")); return }
        offer = manifest
        backupFolder = nil
        let installer = makeInstaller()
        state = .installing(.downloading(0))

        do { try installer.preflight(manifest: manifest) } catch {
            fail(error, fallback: { .preflightFailed($0) }, manifest: manifest)
            return
        }
        let newApp: URL
        do {
            newApp = try await installer.download(manifest, zipURL: zip, progress: { [weak self] value in
                Task { @MainActor in self?.progress(value) }
            })
        } catch {
            fail(error, fallback: { .downloadFailed($0) }, manifest: manifest)
            return
        }
        if Task.isCancelled { abandon(newApp, installer: installer, manifest: manifest); return }

        state = .installing(.backingUp)
        await Task.yield()   // дать окну показать шаг: копия базы блокирует главный поток
        if Task.isCancelled { abandon(newApp, installer: installer, manifest: manifest); return }
        do { backupFolder = try installer.backup(version: manifest.version) } catch {
            installer.discardDownload(newApp)
            fail(error, fallback: { .backupFailed($0) }, manifest: manifest)
            return
        }
        if Task.isCancelled { abandon(newApp, installer: installer, manifest: manifest); return }

        state = .installing(.installing)
        do { try installer.replace(with: newApp) } catch {
            installer.discardDownload(newApp)
            fail(error, fallback: { .replaceFailed($0) }, manifest: manifest)
            return
        }
        do { try installer.relaunch() } catch {
            // Бандл уже новый: старое приложение продолжает работать, но надо перезапустить вручную.
            state = .installFailed(.relaunchFailed(error.localizedDescription))
        }
    }

    private func progress(_ value: Double) {
        guard case .installing(.downloading) = state else { return }
        state = .installing(value >= 1 ? .verifying : .downloading(min(max(value, 0), 1)))
    }

    private func abandon(_ newApp: URL, installer: any UpdateInstalling, manifest: ReleaseManifest) {
        installer.discardDownload(newApp)
        state = .available(manifest)
    }

    private func fail(_ error: any Error, fallback: (String) -> UpdateError, manifest: ReleaseManifest) {
        let mapped: UpdateError
        if let known = error as? UpdateError {
            mapped = known
        } else if error is CancellationError || (error as? URLError)?.code == .cancelled {
            mapped = .cancelled
        } else if error is SchemaGeneration.UnreadableMarker {
            mapped = .unreadableGeneration
        } else {
            mapped = fallback(error.localizedDescription)
        }
        if mapped == .cancelled { state = .available(manifest) } else { state = .installFailed(mapped) }
    }

    // MARK: Тексты

    static func stepText(_ step: UpdateStep) -> String {
        switch step {
        case .downloading(let value):
            let percent = Int((value * 100).rounded(.down))
            return String(localized: "Скачивание… \(percent)%")
        case .verifying: return String(localized: "Проверка")
        case .backingUp: return String(localized: "Резервная копия")
        case .installing: return String(localized: "Установка")
        }
    }

    /// Строка состояния для настроек и плашки.
    var statusText: String {
        switch state {
        case .idle:
            skippedOffer.map { String(localized: "Версия \($0) пропущена") } ?? ""
        case .checking: String(localized: "Проверка обновлений…")
        case .upToDate: String(localized: "Установлена последняя версия")
        case .available(let manifest): String(localized: "Доступна версия \(manifest.version)")
        case .failed(let reason): String(localized: "Не удалось проверить: \(reason)")
        case .development: String(localized: "Сборка для разработки, обновления выключены")
        case .installing(let step): Self.stepText(step)
        case .installFailed(let error): Self.message(for: error, backup: backupFolder)
        }
    }

    /// Заголовок плашки.
    var bannerTitle: String {
        switch state {
        case .installing:
            let version = offer?.version ?? ""
            return String(localized: "Установка версии \(version)")
        case .installFailed: return String(localized: "Не удалось установить обновление")
        default: return statusText
        }
    }

    /// Текст ошибки установки: причина, что приложение и прогресс не изменены, и где лежит копия (если сделана).
    static func message(for error: UpdateError, backup: URL?) -> String {
        var parts: [String]
        switch error {
        case .translocated:
            parts = [String(localized: "Приложение запущено из временного места. Перенесите его в папку «Программы» и повторите.")]
        case .notWritable:
            parts = [String(localized: "Нет прав на запись в папку с приложением. Скачайте .dmg вручную со страницы релиза.")]
        case .olderGeneration:
            parts = [String(localized: "Прогресс записан более новой версией приложения, чем в этом обновлении.")]
        case .checksum:
            parts = [String(localized: "Скачанный файл не прошёл проверку контрольной суммы.")]
        case .size:
            parts = [String(localized: "Размер скачанного файла не совпал с ожидаемым.")]
        case .badBundle(let detail):
            parts = [String(localized: "Скачанное приложение не прошло проверку: \(detail).")]
        case .signature:
            parts = [String(localized: "Подпись скачанного приложения не прошла проверку.")]
        case .backupFailed:
            parts = [String(localized: "Не удалось сделать резервную копию прогресса.")]
        case .replaceFailed(let detail):
            if detail.contains("restore failed") {
                parts = [String(localized: "Не удалось заменить приложение, и прежняя версия не встала на место. Она лежит рядом: TenFingers.app.previous. Переименуйте её в TenFingers.app.")]
            } else {
                parts = [String(localized: "Не удалось заменить приложение.")]
            }
        case .cancelled:
            parts = [String(localized: "Установка отменена.")]
        case .unreadableGeneration:
            parts = [String(localized: "Не удалось прочитать версию базы прогресса.")]
        case .preflightFailed(let detail):
            parts = [String(localized: "Не удалось начать установку: \(detail)")]
        case .downloadFailed(let detail):
            parts = [String(localized: "Не удалось скачать обновление: \(detail)")]
        case .relaunchFailed:
            parts = [String(localized: "Новая версия установлена, но не перезапустилась. Закройте приложение и откройте его снова вручную. Прогресс не изменён.")]
        }
        switch error {
        case .relaunchFailed: break
        case .replaceFailed(let detail) where detail.contains("restore failed"):
            parts.append(String(localized: "Прогресс не изменён."))
        default:
            parts.append(String(localized: "Приложение и прогресс не изменены."))
        }
        if let backup { parts.append(String(localized: "Резервная копия прогресса: \(backup.path)")) }
        return parts.joined(separator: " ")
    }
}
