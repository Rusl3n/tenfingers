import Foundation

public enum CoreResourceError: Error, Equatable {
    case missing(String)
}

public enum CoreResources {
    /// В собранном .app бандл ресурсов лежит в Contents/Resources (в корне .app он ломает подпись).
    /// При `swift run` и в тестах его находит сгенерированный `Bundle.module`.
    public static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TenFingers_TypingCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    public static func url(_ name: String, _ ext: String) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw CoreResourceError.missing("\(name).\(ext)")
        }
        return url
    }
}
