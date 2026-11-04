import Foundation

/// Описание выпуска `release.json` (7b, §5.1) в том виде, как его пишет `scripts/package-release.sh`.
/// Неизвестный `format` разбирается без ошибки: решение «не предлагать» принимает `UpdatePolicy`.
public struct ReleaseManifest: Decodable, Sendable, Equatable {
    public struct Asset: Decodable, Sendable, Equatable {
        public let name: String
        public let size: Int
        public let sha256: String

        public init(name: String, size: Int, sha256: String) {
            self.name = name
            self.size = size
            self.sha256 = sha256
        }
    }

    /// Единственный формат, который понимает эта версия приложения.
    public static let supportedFormat = 1

    public let format: Int
    public let version: String
    public let build: Int
    public let commit: String
    public let schemaGeneration: Int
    public let minimumSystemVersion: String
    public let zip: Asset
    public let dmg: Asset
    public let notesURL: URL

    /// Бросает `DecodingError` при мусоре и при отсутствии любого поля.
    public static func decode(_ data: Data) throws -> ReleaseManifest {
        try JSONDecoder().decode(ReleaseManifest.self, from: data)
    }
}
