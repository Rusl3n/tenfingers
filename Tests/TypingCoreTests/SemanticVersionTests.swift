import Testing
@testable import TypingCore

// Семантические версии для проверки обновлений (7b, §5.1).

@Test func semanticVersionOrdersNumerically() throws {
    let v231 = try #require(SemanticVersion("2.3.1"))
    let v240 = try #require(SemanticVersion("2.4.0"))
    let v290 = try #require(SemanticVersion("2.9.0"))
    let v2100 = try #require(SemanticVersion("2.10.0"))
    #expect(v240 > v231)
    #expect(v2100 > v290)
    #expect(v231 == SemanticVersion("2.3.1"))
    #expect(try #require(SemanticVersion("3.0.0")) > v2100)
}

@Test func semanticVersionPrereleaseIsBelowRelease() throws {
    let dev = try #require(SemanticVersion("2.4.0-dev"))
    let release = try #require(SemanticVersion("2.4.0"))
    let previous = try #require(SemanticVersion("2.3.1"))
    #expect(dev < release)
    #expect(dev > previous)
    #expect(dev.isPrerelease)
    #expect(!release.isPrerelease)
}

@Test func semanticVersionPrereleaseSuffixesCompareAsStrings() throws {
    let dev = try #require(SemanticVersion("2.4.0-dev"))
    let dev2 = try #require(SemanticVersion("2.4.0-dev.2"))
    let rc = try #require(SemanticVersion("2.4.0-rc"))
    #expect(dev < dev2)
    #expect(dev2 < rc)
}

@Test func semanticVersionRejectsGarbage() {
    for text in ["", "2", "2.4", "2.4.0.1", "a.b.c", "2.4.x", "2.4.0-", "-1.0.0", "2..0", " 2.4.0", "2.4.0 ", "v2.4.0", "2.4.-1"] {
        #expect(SemanticVersion(text) == nil, "\(text)")
    }
}

@Test func semanticVersionDescriptionRoundTrips() throws {
    for text in ["2.3.1", "2.4.0-dev", "10.20.30-rc.1"] {
        #expect(try #require(SemanticVersion(text)).description == text)
    }
}
