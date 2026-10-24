import Foundation
import Testing
@testable import TenFingers

private func englishStrings() throws -> [String: String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Localization/en.lproj/Localizable.strings")
    return try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
}

@Test func settingsSectionsAreUnique() {
    let all = SettingsSection.allCases
    #expect(all.count == 4)
    #expect(Set(all.map(\.rawValue)).count == all.count)
    #expect(Set(all.map(\.titleKey)).count == all.count)
    #expect(Set(all.map(\.icon)).count == all.count)
}

@Test func settingsSectionTitlesAreTranslated() throws {
    let en = try englishStrings()
    for section in SettingsSection.allCases {
        let translation = try #require(en[section.titleKey], "нет перевода: \(section.titleKey)")
        #expect(!translation.isEmpty)
    }
}

@Test func settingsSectionStorageIsStable() {
    #expect(SettingsSection(rawValue: "keyboard") == .keyboard)
    #expect(SettingsSection(rawValue: "unknown") == nil)
}

@Test func keyboardPreviewShowsFullSizeWhileAnySliderIsDragged() {
    var state = KeyboardPreviewState()
    #expect(!state.showsFullSize)
    state.isEditingSize = true
    #expect(state.showsFullSize)
    state.isEditingOffset = true
    state.isEditingSize = false
    #expect(state.showsFullSize)
    state.isEditingOffset = false
    #expect(!state.showsFullSize)
}
