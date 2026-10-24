import AppKit
import Testing
import TypingCore
@testable import TenFingers

/// Каждый значок каталога и замок секретной ачивки — существующие SF Symbols (иначе на месте значка пусто).
@Test func everyAchievementIconIsASystemSymbol() {
    for name in Set(AchievementCatalog.all.map(\.icon)).union(["lock.fill"]).sorted() {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа «\(name)»")
    }
}
