import Foundation
import Testing
@testable import TypingCore

// release.json (7b, §5.1, §5.5): тот же вид, что пишет scripts/package-release.sh.

private func manifestJSON(format: Int = 1, extra: String = "") -> String {
    """
    {
      "format": \(format),
      "version": "2.4.0",
      "build": 42,
      "commit": "abc1234",
      "schemaGeneration": 3,
      "minimumSystemVersion": "15.0",
      "zip": { "name": "TenFingers-2.4.0.zip", "size": 1234567, "sha256": "aa11" },
      "dmg": { "name": "TenFingers-2.4.0.dmg", "size": 2345678, "sha256": "bb22" },
      "notesURL": "https://github.com/Rusl3n/tenfingers/releases/tag/v2.4.0"\(extra)
    }
    """
}

@Test func releaseManifestDecodesValidFile() throws {
    let manifest = try ReleaseManifest.decode(Data(manifestJSON().utf8))
    #expect(manifest.format == ReleaseManifest.supportedFormat)
    #expect(manifest.version == "2.4.0")
    #expect(manifest.build == 42)
    #expect(manifest.commit == "abc1234")
    #expect(manifest.schemaGeneration == 3)
    #expect(manifest.minimumSystemVersion == "15.0")
    #expect(manifest.zip == ReleaseManifest.Asset(name: "TenFingers-2.4.0.zip", size: 1_234_567, sha256: "aa11"))
    #expect(manifest.dmg == ReleaseManifest.Asset(name: "TenFingers-2.4.0.dmg", size: 2_345_678, sha256: "bb22"))
    #expect(manifest.notesURL == URL(string: "https://github.com/Rusl3n/tenfingers/releases/tag/v2.4.0"))
}

@Test func releaseManifestDecodesUnknownFormatWithoutError() throws {
    let manifest = try ReleaseManifest.decode(Data(manifestJSON(format: 2).utf8))
    #expect(manifest.format == 2)
}

@Test func releaseManifestIgnoresUnknownFields() throws {
    let manifest = try ReleaseManifest.decode(Data(manifestJSON(extra: ",\n  \"future\": [1, 2]").utf8))
    #expect(manifest.version == "2.4.0")
}

@Test func releaseManifestThrowsOnMissingField() {
    let missingBuild = manifestJSON().replacingOccurrences(of: "\"build\": 42,", with: "")
    let missingSha = manifestJSON().replacingOccurrences(of: ", \"sha256\": \"bb22\"", with: "")
    let missingNotes = manifestJSON().replacingOccurrences(of: "\"notesURL\"", with: "\"notes\"")
    for text in [missingBuild, missingSha, missingNotes] {
        #expect(throws: (any Error).self) { try ReleaseManifest.decode(Data(text.utf8)) }
    }
}

@Test func releaseManifestThrowsOnGarbage() {
    for text in ["", "not json", "[]", "{}", "<html>404</html>"] {
        #expect(throws: (any Error).self) { try ReleaseManifest.decode(Data(text.utf8)) }
    }
}
