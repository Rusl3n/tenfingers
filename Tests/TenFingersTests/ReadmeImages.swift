import SwiftUI
import Testing
import TypingCore
@testable import TenFingers

/// Рендерит картинки для README в docs/images. Запуск: RENDER_DOCS=1 swift test --filter renderReadmeImages
@MainActor
private func render<V: View>(_ view: V, to name: String) throws {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/images")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: dir.appendingPathComponent(name))
}

/// Подписи легенды на английском из Localization/en.lproj: в тестах `Bundle.main` не содержит локализации приложения.
private func englishLegendTitles() throws -> [String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization/en.lproj/Localizable.strings")
    let strings = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    return try FingerLegend.titleKeys.map { try #require(strings[$0], "нет перевода: \($0)") }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DOCS"] == "1"))
func renderReadmeImages() throws {
    let ru = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.RussianWin"))
    let en = try #require(KeyboardLayoutService.source(withID: "com.apple.keylayout.ABC"))
    let ruSnap = KeyboardLayoutService.snapshot(for: ru, shape: .ansi)
    let enSnap = KeyboardLayoutService.snapshot(for: en, shape: .ansi)
    let enLegend = try englishLegendTitles()
    let marks = KeyboardView.marks(for: KeyHighlight(keyCode: 22, shiftKeyCode: 56, isError: false))

    let light = LightPalette.beige.palette
    try render(
        VStack(spacing: 16) {
            KeyboardView(snapshot: ruSnap, marks: marks)
            FingerLegend()
        }
        .padding(24)
        .background(light.background)
        .environment(\.palette, light)
        .environment(\.colorScheme, .light),
        to: "keyboard-ru.png"
    )

    let dark = DarkPalette.night.palette
    try render(
        VStack(spacing: 16) {
            KeyboardView(snapshot: enSnap, marks: marks)
            FingerLegend(titles: enLegend)
        }
        .padding(24)
        .background(dark.background)
        .environment(\.palette, dark)
        .environment(\.colorScheme, .dark),
        to: "keyboard-en-dark.png"
    )

    try render(
        TypingTextView(target: Array("щука щит цвет цепь щель цапля ещё"), position: 14, errorAtCursor: true)
            .padding(24)
            .frame(width: 520, alignment: .leading)
            .background(light.background)
            .environment(\.palette, light)
            .environment(\.colorScheme, .light),
        to: "exercise-text.png"
    )
}
