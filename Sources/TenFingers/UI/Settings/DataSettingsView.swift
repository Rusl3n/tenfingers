import AppKit
import SwiftData
import SwiftUI

/// Раздел «Данные»: сохранить весь прогресс в файл, загрузить из файла (со сводкой и резервной копией),
/// показать резервные копии.
struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ReminderScheduler.self) private var scheduler
    @Environment(RunPresence.self) private var presence
    @Environment(ToastCenter.self) private var toasts
    @State private var pending: PendingImport?
    @State private var failure: String?
    /// Загрузка прошла: адрес резервной копии прежнего прогресса.
    @State private var importedBackup: URL?

    var body: some View {
        Form {
            Section {
                Button("Сохранить прогресс в файл…", action: exportProgress)
            } header: {
                Text("Сохранение")
            } footer: {
                Text("В файл попадают все занятия, статистика клавиш, прогресс уроков, свои тексты, профиль и настройки.")
            }
            Section {
                Button("Загрузить прогресс из файла…", action: chooseArchive)
                    .disabled(presence.hasRun)
            } header: {
                Text("Загрузка")
            } footer: {
                if presence.hasRun {
                    Text("Завершите текущее упражнение, чтобы загрузить прогресс.")
                } else {
                    Text("Текущий прогресс будет заменён. Перед заменой он автоматически сохраняется в резервную копию.")
                }
            }
            Section {
                Button("Показать резервные копии в Finder", action: Self.revealBackups)
            } footer: {
                Text("Резервные копии лежат в папке ~/Library/Application Support/TenFingers.backups")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $pending) { item in
            ImportPreview(item: item, onCancel: { pending = nil }, onReplace: { replace(with: item) })
        }
        // Упражнение началось, пока открыта сводка файла: замена базы под идущим упражнением недопустима.
        .onChange(of: presence.hasRun) { _, hasRun in
            if hasRun { pending = nil }
        }
        .alert("Не удалось", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
               presenting: failure) { _ in
            Button("Готово", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert("Прогресс загружен",
               isPresented: Binding(get: { importedBackup != nil }, set: { if !$0 { importedBackup = nil } }),
               presenting: importedBackup) { backup in
            Button("Готово", role: .cancel) {}
            Button("Показать копию в Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
        } message: { backup in
            Text("Прежний прогресс сохранён в резервную копию «\(backup.lastPathComponent)».")
        }
    }

    private func exportProgress() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Сохранить прогресс")
        panel.allowedContentTypes = [ProgressArchive.fileType]
        panel.nameFieldStringValue = ProgressArchive.defaultFileName(now: .now)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProgressArchive.export(context: context).write(to: url, options: .atomic)
            toasts.show(Toast(icon: "checkmark.circle", message: String(localized: "Прогресс сохранён в файл"),
                              tint: .green))
        } catch {
            failure = String(localized: "Не удалось сохранить прогресс: \(error.localizedDescription)")
        }
    }

    private func chooseArchive() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Загрузить прогресс")
        panel.allowedContentTypes = [ProgressArchive.fileType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = try ProgressArchive.decode(Data(contentsOf: url))
            pending = PendingImport(fileName: url.lastPathComponent, archive: archive)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func replace(with item: PendingImport) {
        pending = nil
        // Проверка ещё раз: упражнение могло начаться, пока открыта сводка.
        guard !presence.hasRun else {
            failure = String(localized: "Завершите текущее упражнение, чтобы загрузить прогресс.")
            return
        }
        do {
            importedBackup = try ProgressImporter(context: context).importArchive(item.archive)
            // Цель, начало дня и время напоминаний могли поменяться вместе с настройками.
            scheduler.rescheduleSoon()
        } catch let error as ProgressImportError {
            failure = error.localizedDescription
        } catch {
            failure = String(localized: "Не удалось загрузить прогресс. Текущий прогресс не изменён: \(error.localizedDescription)")
        }
    }

    /// Папка резервных копий (создаётся, если её ещё нет).
    private static func revealBackups() {
        let directory = ProgressArchive.backupsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

/// Прочитанный файл, ждущий подтверждения.
struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let archive: ProgressArchive.Archive
    var summary: ProgressArchive.ArchiveSummary { ProgressArchive.summary(archive) }
}

/// Лист со сводкой файла и подтверждением замены. Разрушительная кнопка — не кнопка по умолчанию:
/// Return ничего не заменяет, Esc — «Отмена».
private struct ImportPreview: View {
    let item: PendingImport
    let onCancel: () -> Void
    let onReplace: () -> Void

    private var summary: ProgressArchive.ArchiveSummary { item.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Загрузить прогресс из файла?").font(.title3.bold())
                Text(verbatim: item.fileName).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let exportedAt = summary.exportedAt {
                    row("Файл сохранён", Text(exportedAt, format: .dateTime.day().month().year().hour().minute()))
                }
                if !summary.appVersion.isEmpty {
                    row("Версия приложения", Text(verbatim: summary.appVersion))
                }
                if let first = summary.firstDate, let last = summary.lastDate {
                    row("Период занятий", Text(verbatim: "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"))
                } else {
                    row("Период занятий", Text("нет"))
                }
                row("Упражнений", Text(verbatim: "\(summary.sessionCount)"))
                row("Дней с занятиями", Text(verbatim: "\(summary.dayCount)"))
                if !summary.nickname.isEmpty { row("Никнейм", Text(verbatim: summary.nickname)) }
                if !summary.fullName.isEmpty { row("Имя", Text(verbatim: summary.fullName)) }
            }
            Label("Весь текущий прогресс, профиль и настройки будут заменены данными из файла. Перед заменой текущий прогресс сохранится в резервную копию.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Заменить текущий прогресс", role: .destructive, action: onReplace)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value
        }
    }
}
