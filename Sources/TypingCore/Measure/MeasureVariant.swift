/// Длительность замера: по таймеру (секунды) или «Текст 300 знаков».
public enum MeasureDuration: Hashable, Sendable, Codable, RawRepresentable, CaseIterable {
    case seconds(Int)
    case text300

    public static let allCases: [MeasureDuration] = [.seconds(60), .seconds(120), .seconds(300), .text300]

    /// Устойчивый ключ для хранения: "60", "120", "300", "text300".
    public var rawValue: String {
        switch self {
        case .seconds(let s): String(s)
        case .text300: "text300"
        }
    }

    public init?(rawValue: String) {
        if rawValue == "text300" { self = .text300; return }
        guard let s = Int(rawValue), [60, 120, 300].contains(s) else { return nil }
        self = .seconds(s)
    }

    /// Секунды таймера; `nil` у «Текста 300 знаков».
    public var timerSeconds: Int? {
        if case .seconds(let s) = self { s } else { nil }
    }
}

/// Вид текста замера.
public enum MeasureTextKind: String, Hashable, Sendable, Codable, CaseIterable {
    case plain, capsPunctuation, digits
}

/// Вариант замера: длительность + вид текста + язык. Замеры сравниваются только внутри варианта.
public struct MeasureVariant: Hashable, Sendable, Codable {
    public var duration: MeasureDuration
    public var kind: MeasureTextKind
    public var language: Language

    public init(duration: MeasureDuration, kind: MeasureTextKind, language: Language) {
        self.duration = duration
        self.kind = kind
        self.language = language
    }

    /// Строковый ключ варианта: "60:plain:ru".
    public var key: String { "\(duration.rawValue):\(kind.rawValue):\(language.rawValue)" }

    public init?(key: String) {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let d = MeasureDuration(rawValue: parts[0]),
              let k = MeasureTextKind(rawValue: parts[1]), let l = Language(rawValue: parts[2]) else { return nil }
        self.init(duration: d, kind: k, language: l)
    }
}
