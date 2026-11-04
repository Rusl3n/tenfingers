import Foundation
import Testing

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func text(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

@Test func widgetInfoPlistDeclaresAWidgetKitExtension() throws {
    let info = try plist("scripts/TenFingersWidget-Info.plist")
    #expect(info["CFBundlePackageType"] as? String == "XPC!")
    #expect(info["CFBundleIdentifier"] as? String == "local.tenfingers.widget")
    #expect(info["CFBundleExecutable"] as? String == "TenFingersWidget")
    #expect(info["LSMinimumSystemVersion"] as? String == "15.0")
    let localizations = info["CFBundleLocalizations"] as? [String]
    #expect(localizations?.contains("ru") == true && localizations?.contains("en") == true)
    let ext = try #require(info["NSExtension"] as? [String: Any])
    #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
}

@Test func widgetInfoPlistHasVersionPlaceholdersForTheBuildScript() throws {
    let info = try plist("scripts/TenFingersWidget-Info.plist")
    #expect(info["CFBundleShortVersionString"] as? String != nil)
    #expect(info["CFBundleVersion"] as? String != nil)
}

@Test func widgetEntitlementsAreSandboxedWithReadOnlyAccessToAppData() throws {
    let entitlements = try plist("scripts/TenFingersWidget.entitlements")
    #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    #expect(entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String]
        == ["/Library/Application Support/TenFingers/"])
    // App Group с ad-hoc подписью вызывает системный запрос: его не используем
    #expect(entitlements["com.apple.security.application-groups"] == nil)
}

@Test func widgetStringsNameTheWidgetOnBothLanguages() throws {
    let ru = try plist("Sources/TenFingersWidget/Resources/ru.lproj/Localizable.strings")
    let en = try plist("Sources/TenFingersWidget/Resources/en.lproj/Localizable.strings")
    #expect(ru["Десять пальцев"] as? String == "Десять пальцев")
    #expect(en["Десять пальцев"] as? String == "TenFingers")
    #expect(Set(ru.keys) == Set(en.keys))
    #expect(ru.count >= 2)
}

@Test func makeBundleEmbedsTheWidgetAndSignsWithoutDeep() throws {
    let script = try text("scripts/make-bundle.sh")
    #expect(script.contains("--product TenFingersWidget"))
    #expect(script.contains("appintentsmetadataprocessor"))
    #expect(script.contains("Metadata.appintents/extract.actionsdata"))
    #expect(try text("scripts/appintents-protocols.json").contains(#""WidgetConfigurationIntent""#))
    #expect(script.contains("Contents/PlugIns/TenFingersWidget.appex"))
    #expect(script.contains("scripts/TenFingersWidget-Info.plist"))
    #expect(!script.contains("--deep "))
    let signAppex = try #require(script.range(of: #"codesign --force --sign - --entitlements"#))
    let signApp = try #require(script.range(of: #"codesign --force --sign - "$APP""#))
    #expect(signAppex.lowerBound < signApp.lowerBound)
}

@Test func packageDeclaresWidgetTargetsAndSharedSnapshotLibrary() throws {
    let package = try text("Package.swift")
    #expect(package.contains(#".target(name: "WidgetSnapshot")"#))
    #expect(package.contains(#"name: "TenFingersWidget", dependencies: ["WidgetSnapshot"]"#))
    #expect(package.contains(#""-e", "-Xlinker", "_NSExtensionMain""#))
    #expect(package.contains(#"dependencies: ["TypingCore", "WidgetSnapshot"]"#))
}

@Test func widgetStringKeysMatchAndCoverEveryLiteralUsedByTheWidget() throws {
    let ru = try plist("Sources/TenFingersWidget/Resources/ru.lproj/Localizable.strings")
    let en = try plist("Sources/TenFingersWidget/Resources/en.lproj/Localizable.strings")
    #expect(Set(ru.keys) == Set(en.keys))
    // Русские литералы исходников виджета (без комментариев) — ключи строк; каждый должен быть в обеих локализациях.
    let directory = root.appendingPathComponent("Sources/TenFingersWidget")
    let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    #expect(files.count >= 5)
    let literal = try Regex(#""([^"\\\n]*[А-Яа-яЁё][^"\\\n]*)""#)
    var used = Set<String>()
    for file in files {
        let code = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            // Строки примера для галереи уже двуязычные прямо в коде (`ru ? "…" : "…"`): это не ключи.
            .filter { !$0.contains("ru ?") }
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line) }
            .joined(separator: "\n")
        for match in code.matches(of: literal) { used.insert(String(match.output[1].substring ?? "")) }
    }
    #expect(used.count >= 15)
    for key in used.union(["день", "дня", "дней"]) {
        #expect(ru[key] != nil, "нет в ru.lproj: \(key)")
        #expect(en[key] != nil, "нет в en.lproj: \(key)")
    }
}

@Test func makeBundleStampsVersionAndBuildIntoTheWidgetPlist() throws {
    let script = try text("scripts/make-bundle.sh")
    let appexPlist = try #require(script.range(of: #"APPEX_PLIST="$APPEX/Contents/Info.plist""#))
    let tail = String(script[appexPlist.upperBound...])
    #expect(tail.contains(#"Set :CFBundleShortVersionString $VERSION" "$APPEX_PLIST""#))
    #expect(tail.contains(#"Set :CFBundleVersion $BUILD" "$APPEX_PLIST""#))
    // Копия шаблона кладётся раньше, чем в неё подставляются версия и сборка
    let copy = try #require(script.range(of: #"cp scripts/TenFingersWidget-Info.plist "$APPEX/Contents/Info.plist""#))
    #expect(copy.lowerBound < appexPlist.lowerBound)
}

@Test func installAndRelaunchScriptsRestartTheWidgetProcess() throws {
    let build = try text("scripts/build-app.sh")
    let installed = try #require(build.range(of: #"echo "Установлено: /Applications/$NAME""#))
    let buildBeforeInstalled = String(build[..<installed.lowerBound])
    #expect(buildBeforeInstalled.contains("pkill -x TenFingersWidget || true"))
    #expect(buildBeforeInstalled.contains("pluginkit -a"))
    #expect(buildBeforeInstalled.contains("PlugIns/TenFingersWidget.appex"))

    let relaunch = try text("scripts/update-relaunch.sh")
    let open = try #require(relaunch.range(of: #"/usr/bin/open -n "$APP""#))
    let beforeOpen = String(relaunch[..<open.lowerBound])
    #expect(beforeOpen.contains("pkill -x TenFingersWidget || true"))
    #expect(beforeOpen.contains(#"pluginkit -a "$APP/Contents/PlugIns/TenFingersWidget.appex" || true"#))
    // Ожидание выхода старого процесса приложения идёт раньше
    let wait = try #require(relaunch.range(of: "kill -0"))
    let kill = try #require(relaunch.range(of: "pkill -x TenFingersWidget"))
    #expect(wait.lowerBound < kill.lowerBound)
}
