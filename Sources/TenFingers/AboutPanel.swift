import AppKit

/// Стандартное окно «О программе» с версией, ссылкой на GitHub, лицензией и источниками данных.
enum AboutPanel {
    static let repositoryURL = URL(string: "https://github.com/Rusl3n/tenfingers")!

    @MainActor static func show() {
        let info = AppVersion.current
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: String(localized: "Десять пальцев"),
            // Версия уже содержит номер сборки; пустое поле убирает вторую пару скобок.
            .applicationVersion: AppVersion.display(info: info),
            .version: "",
            .credits: credits(commit: AppVersion.commit(info: info)),
        ]
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    static func credits(commit: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        func line(_ string: String, attributes: [NSAttributedString.Key: Any] = [:], last: Bool = false) {
            text.append(NSAttributedString(string: string + (last ? "" : "\n"),
                                           attributes: base.merging(attributes) { $1 }))
        }
        line("github.com/Rusl3n/tenfingers", attributes: [.link: repositoryURL])
        if let commit { line(String(localized: "Коммит: \(commit)")) }
        line(String(localized: "Лицензия кода: MIT"))
        line(String(localized: "Списки слов: hermitdave/FrequencyWords (OpenSubtitles 2018), CC BY-SA 4.0. Отрывки для практики: общественное достояние, Project Gutenberg и Викитека."),
             last: true)
        return text
    }
}
