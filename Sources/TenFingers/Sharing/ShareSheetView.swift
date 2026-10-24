import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

private let shareLog = Logger(subsystem: "local.tenfingers", category: "share")

/// Лист «Поделиться»: живой предпросмотр карточки, опции (подпись, тема, фон, формат) и действия
/// «Поделиться…», «Сохранить PNG…», «Скопировать». Опции запоминаются. Esc закрывает лист.
struct ShareSheetView: View {
    let card: ShareCard
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ShareProfile.stored()
    @State private var options: ShareOptions
    @State private var anchor = ShareAnchor()
    @State private var status: Status?

    private enum Status: Equatable {
        case copied, saved, failed
    }

    /// Ширина и высота области предпросмотра.
    private static let previewSize = CGSize(width: 560, height: 340)

    init(card: ShareCard) {
        self.card = card
        _options = State(initialValue: ShareOptions.load(profile: ShareProfile.stored()))
    }

    private var cardView: ShareCardView { ShareCardView.make(card: card, options: options, profile: profile) }

    var body: some View {
        VStack(spacing: 18) {
            Text("Поделиться").font(.title2.bold())
            preview
            controls
            actions
        }
        .padding(24)
        .frame(width: Self.previewSize.width + 48)
        .onChange(of: options) { _, new in
            new.save()
            status = nil
        }
    }

    // MARK: Предпросмотр

    private var preview: some View {
        let size = options.format.size
        let scale = min(Self.previewSize.width / size.width, Self.previewSize.height / size.height)
        return cardView
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .background {
                if options.background == .transparent { Checkerboard() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Предпросмотр карточки"))
    }

    // MARK: Опции

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Подпись").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Подпись", selection: $options.signature) {
                        ForEach(profile.available) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(profile.isEmpty)
                    if profile.isEmpty {
                        Text("Заполните профиль в настройках").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            GridRow {
                Text("Тема")
                segmented("Тема", selection: $options.theme, ShareTheme.allCases) { $0.title }
            }
            GridRow {
                Text("Фон")
                segmented("Фон", selection: $options.background, ShareBackground.allCases) { $0.title }
            }
            GridRow {
                Text("Формат")
                segmented("Формат", selection: $options.format, ShareFormat.allCases) { $0.title }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segmented<T: Hashable & Identifiable>(_ label: LocalizedStringKey, selection: Binding<T>, _ values: [T],
                                                       title: @escaping (T) -> String) -> some View {
        Picker(label, selection: selection) {
            ForEach(values) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Действия

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Поделиться…", action: share)
                .background(ShareAnchorView(anchor: anchor))
            Button("Сохранить PNG…", action: save)
            Button("Скопировать", action: copy)
            statusLabel
            Spacer(minLength: 8)
            Button("Готово") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .copied: Label("Скопировано", systemImage: "checkmark").foregroundStyle(.secondary)
        case .saved: Label("Сохранено", systemImage: "checkmark").foregroundStyle(.secondary)
        case .failed: Label("Не удалось создать картинку", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        case nil: EmptyView()
        }
    }

    private func png() -> Data? {
        do {
            return try ShareCardRenderer.png(cardView)
        } catch {
            shareLog.error("Rendering share card failed: \(String(describing: error), privacy: .public)")
            status = .failed
            return nil
        }
    }

    /// Системное меню macOS (Сообщения, Почта, AirDrop…) с PNG во временной папке и короткой подписью.
    /// Меню привязано к кнопке; если её `NSView` нет — к окну.
    private func share() {
        guard let view = anchor.view ?? NSApp.keyWindow?.contentView else {
            shareLog.error("Share picker has no anchor view")
            status = .failed
            return
        }
        guard let data = png() else { return }
        do {
            let url = try ShareTempFile.write(data, name: card.fileName)
            let picker = NSSharingServicePicker(items: [url, ShareCardText.message()])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } catch {
            shareLog.error("Writing share card failed: \(String(describing: error), privacy: .public)")
            status = .failed
        }
    }

    /// Окно сохранения — листом на окне «Поделиться» (если его нет — отдельным окном). PNG рисуется после выбора
    /// файла. Отмена ничего не рисует.
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.fileName
        panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let data = png() else { return }
            do {
                try data.write(to: url, options: .atomic)
                status = .saved
            } catch {
                shareLog.error("Saving share card failed: \(String(describing: error), privacy: .public)")
                status = .failed
            }
        }
        if let window = anchor.view?.window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func copy() {
        guard let data = png() else { return }
        // PNG и TIFF: одни приложения берут PNG, другие (старые) — только TIFF.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(data, forType: .png)
        if let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        status = .copied
    }
}

/// Временный PNG для меню «Поделиться…»: каждая карточка — в своей подпапке `$TMPDIR/TenFingers-share/<UUID>`.
/// Прежняя карточка не удаляется сразу (AirDrop или Почта могут ещё читать её, если отправить снова), а подпапки
/// старше `lifetime` удаляются при следующей записи, чтобы карточки не копились.
enum ShareTempFile {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TenFingers-share", isDirectory: true)

    /// Сколько живёт временная карточка.
    static let lifetime: TimeInterval = 10 * 60

    static func write(_ data: Data, name: String, in directory: URL = directory, now: Date = .now) throws -> URL {
        removeExpired(in: directory, now: now)
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Удаляет всё в папке, созданное раньше `now - lifetime` (и подпапки, и файлы прежнего устройства папки).
    /// Ошибки только в журнал: из-за мусора во временной папке отправка не должна срываться.
    static func removeExpired(in directory: URL, now: Date) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        for item in items {
            let created = (try? item.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard now.timeIntervalSince(created) > lifetime else { continue }
            do {
                try manager.removeItem(at: item)
            } catch {
                shareLog.error("Removing old share card failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension View {
    /// Лист «Поделиться» для карточки (`nil` — лист закрыт).
    func shareSheet(_ card: Binding<ShareCard?>) -> some View {
        sheet(item: card) { ShareSheetView(card: $0) }
    }
}

/// Кнопка-ссылка «Поделиться» (рисуется SwiftUI, поэтому видна и на картинках `ImageRenderer`).
struct ShareLinkButton: View {
    var title: LocalizedStringKey = "Поделиться"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "square.and.arrow.up")
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

/// `NSView` под кнопкой «Поделиться…»: к нему привязывается системное меню `NSSharingServicePicker`.
@MainActor
final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// Шахматка под прозрачной карточкой в предпросмотре.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.78)))
                }
            }
        }
    }
}
