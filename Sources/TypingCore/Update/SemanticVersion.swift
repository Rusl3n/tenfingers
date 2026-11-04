import Foundation

/// Семантическая версия `major.minor.patch[-pre]` (7b, §5.1). Предрелизная версия ниже такой же без суффикса;
/// суффиксы между собой сравниваются как строки.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Суффикс после первого `-` (без самого дефиса) или `nil`.
    public let prerelease: String?

    public var isPrerelease: Bool { prerelease != nil }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    /// `nil` для всего, что не `число.число.число` с необязательным непустым суффиксом.
    public init?(_ string: String) {
        let halves = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = halves.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 else { return nil }
        var parsed: [Int] = []
        for part in numbers {
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let value = Int(part) else { return nil }
            parsed.append(value)
        }
        var suffix: String?
        if halves.count == 2 {
            guard !halves[1].isEmpty else { return nil }
            suffix = String(halves[1])
        }
        major = parsed[0]
        minor = parsed[1]
        patch = parsed[2]
        prerelease = suffix
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (left?, right?): return left < right
        }
    }
}
