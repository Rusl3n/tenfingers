import Foundation
import SwiftData

/// Откат с экрана ошибки базы (7b, решение 9): кнопка видна, только если рядом с бандлом лежит
/// `TenFingers.app.previous`, то есть новая версия поставлена обновлением и ещё не открыла базу.
@MainActor struct StoreErrorRecovery {
    let bundleURL: URL

    var canRollBack: Bool {
        bundleURL.pathExtension == "app"
            && FileManager.default.fileExists(atPath: UpdateInstaller.previousURL(for: bundleURL).path)
    }

    /// Обратная замена и перезапуск. База не меняется: её не открывали на запись. Если замена не удалась,
    /// перезапуска нет; если не удался перезапуск, прежняя версия уже на месте.
    func rollBack(relauncher: UpdateInstaller.Relauncher) throws {
        try UpdateInstaller.rollBack(bundleURL: bundleURL)
        try relauncher(bundleURL)
    }
}

/// Открытие базы при запуске: текст ошибки для экрана ошибки и очистка после обновления.
enum StoreLaunch {
    enum Outcome {
        case opened(ModelContainer)
        case failed(message: String, recovery: StoreErrorRecovery)
    }

    /// База открылась: `.previous` и временные папки обновления больше не нужны (§5.3 шаг 8).
    /// Не открылась: ничего не удаляется, экран ошибки получает откат.
    @MainActor static func open(_ make: () throws -> ModelContainer, bundleURL: URL) -> Outcome {
        do {
            let container = try make()
            UpdateInstaller.cleanUpAfterSuccessfulLaunch(bundleURL: bundleURL)
            return .opened(container)
        } catch ModelStoreError.newerStore, ModelStoreError.newerGeneration {
            return .failed(message: String(localized: "Прогресс сохранён более новой версией приложения. Установите последнюю версию."),
                           recovery: StoreErrorRecovery(bundleURL: bundleURL))
        } catch ModelStoreError.unreadableGeneration {
            return .failed(message: String(localized: "Не удалось прочитать версию базы прогресса. Установите последнюю версию приложения."),
                           recovery: StoreErrorRecovery(bundleURL: bundleURL))
        } catch {
            return .failed(message: String(localized: "Не удалось открыть сохранённый прогресс: \(error.localizedDescription)"),
                           recovery: StoreErrorRecovery(bundleURL: bundleURL))
        }
    }
}
