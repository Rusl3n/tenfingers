import Foundation
import SwiftData

enum ModelStore {
    static let schema = Schema([
        SessionRecord.self, LessonProgress.self, KeyStat.self, DayRecord.self, CounterRecord.self,
    ])

    /// Хранилище в ~/Library/Application Support/TenFingers/TenFingers.store.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "TenFingers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "TenFingers.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
