import SwiftData
import SwiftUI
import TypingCore
import UniformTypeIdentifiers

/// Экран «Практика»: частотные слова, отрывки классики, цифры и символы, свой текст.
struct PracticeView: View {
    let start: (RunKind) -> Void

    private enum Panel { case library, custom }

    /// Файл больше этого размера не открываем: так много текста не напечатать.
    private static let maximumFileSize = 5_000_000

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @Query(sort: \CustomText.createdAt, order: .reverse) private var customTexts: [CustomText]
    @State private var panel: Panel?
    @State private var showEditor = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var pendingDelete: CustomText?

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Практика: \(language.displayName)").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    card("Частотные слова", subtitle: "Самые употребительные слова языка", icon: "text.word.spacing",
                         isSelected: false) { run(.frequentWords) }
                    card("Отрывки классики", subtitle: "Проза русских и английских авторов", icon: "books.vertical",
                         isSelected: panel == .library) { toggle(.library) }
                    card("Цифры и символы", subtitle: "Числа, даты, скобки, кавычки и знаки", icon: "number",
                         isSelected: false) { run(.symbols) }
                    card("Свой текст", subtitle: "Вставьте текст или откройте файл", icon: "doc.text",
                         isSelected: panel == .custom) { toggle(.custom) }
                }
                switch panel {
                case .library: libraryPanel
                case .custom: customPanel
                case nil: EmptyView()
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showEditor) {
            CustomTextEditor { title, text in saveText(title: title, raw: text) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { importFile($0) }
        .confirmationDialog("Удалить текст?", isPresented: deleteDialogShown, presenting: pendingDelete) { text in
            Button("Удалить", role: .destructive) { delete(text) }
            Button("Отмена", role: .cancel) {}
        } message: { text in
            Text(text.title)
        }
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func toggle(_ target: Panel) {
        panel = panel == target ? nil : target
        message = nil
    }

    private func run(_ source: PracticeSource) {
        start(.practice(PracticeRun(language: language, source: source)))
    }

    // MARK: - Карточки

    private func card(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor)
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(16)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Отрывки

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = library.texts[language] ?? []
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.author).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = SourceLink.pageURL(for: item.source) {
                        Link("Источник", destination: url).font(.caption)
                    }
                    Button("Начать") { run(.library(item)) }
                }
                .padding(.vertical, 8)
                if item.id != items.last?.id { Divider() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Свой текст

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Вставить текст") { showEditor = true }
                Button("Открыть файл…") { showImporter = true }
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if customTexts.isEmpty {
                Text("Сохранённых текстов пока нет").foregroundStyle(.secondary)
            } else {
                ForEach(customTexts) { text in
                    customRow(text)
                    if text.id != customTexts.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func customRow(_ text: CustomText) -> some View {
        let progress = CustomTextDraft.progress(offset: text.offset, length: text.body.count)
        let lang = Language(rawValue: text.language)?.shortName ?? text.language
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.headline).lineLimit(1)
                Text("\(lang) · \(Formatting.percent(progress))").foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button(text.offset > 0 ? "Продолжить" : "Начать") {
                guard let target = Language(rawValue: text.language) else { return }
                start(.practice(PracticeRun(language: target, source: .custom(text.id))))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Удалить", role: .destructive) { pendingDelete = text }
        }
    }

    /// Нормализует и сохраняет текст. Возвращает сообщение об ошибке или `nil`.
    private func saveText(title: String, raw: String) -> String? {
        let courses = library.courses
        let draft = CustomTextDraft.make(title: title, raw: raw, fallback: language) {
            courses[$0]?.typeableCharacters ?? []
        }
        switch draft {
        case .failure(.tooShort):
            return String(localized: "В тексте почти нет символов, которые можно набрать")
        case .success(let draft):
            modelContext.insert(CustomText(title: draft.title, body: draft.body, language: draft.language.rawValue))
            do {
                try modelContext.save()
                message = nil
                panel = .custom
                return nil
            } catch {
                modelContext.rollback()
                return String(localized: "Не удалось сохранить текст: \(error.localizedDescription)")
            }
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        panel = .custom
        switch result {
        case .failure(let error):
            if !isCancellation(error) { message = String(localized: "Не удалось открыть файл") }
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maximumFileSize {
                message = String(localized: "Файл слишком большой")
                return
            }
            guard let raw = TextFileDecoder.read(url) else {
                message = String(localized: "Не удалось прочитать файл: нужен обычный текстовый файл")
                return
            }
            message = saveText(title: url.deletingPathExtension().lastPathComponent, raw: raw)
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }

    private func delete(_ text: CustomText) {
        modelContext.delete(text)
        do {
            try modelContext.save()
            message = nil
        } catch {
            modelContext.rollback()
            message = String(localized: "Не удалось удалить текст: \(error.localizedDescription)")
        }
    }
}
