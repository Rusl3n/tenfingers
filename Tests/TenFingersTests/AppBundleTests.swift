import Foundation
import Testing

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

@Test func infoPlistNamesTheBundleTenFingers() throws {
    let info = try plist("scripts/Info.plist")
    #expect(info["CFBundleName"] as? String == "TenFingers")
    #expect(info["CFBundleIdentifier"] as? String == "local.tenfingers")
    #expect(info["LSHasLocalizedDisplayName"] as? Bool == true)
}

@Test func displayNameIsLocalized() throws {
    #expect(try plist("Localization/ru.lproj/InfoPlist.strings")["CFBundleDisplayName"] as? String == "Десять пальцев")
    #expect(try plist("Localization/en.lproj/InfoPlist.strings")["CFBundleDisplayName"] as? String == "TenFingers")
}

@Test func buildScriptInstallsNewBundleAndRemovesOldOne() throws {
    let script = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
    #expect(script.contains(#"NAME="TenFingers.app""#))
    #expect(script.contains(#"rm -rf "/Applications/$OLD_NAME""#))
}

@Test func englishStringsSpellTheNameWithoutSpace() throws {
    let en = try plist("Localization/en.lproj/Localizable.strings")
    for (key, value) in en {
        if let text = value as? String { #expect(!text.contains("Ten Fingers"), "en: «\(key)» → \(text)") }
    }
}
