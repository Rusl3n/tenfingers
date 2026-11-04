import Foundation
import WidgetSnapshot

/// Читает `widget.json` из папки данных приложения. Виджет в песочнице, поэтому путь строится по реальному
/// домашнему каталогу (`getpwuid`), а не по HOME песочницы; доступ даёт исключение в entitlements.
enum SnapshotReader {
    static var realHome: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static var defaultFileURL: URL {
        URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent("Library/Application Support/TenFingers", isDirectory: true)
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    /// `nil` — файла нет, он не читается или записан незнакомым форматом: виджет просит открыть приложение.
    static func read(from url: URL = defaultFileURL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }
}
