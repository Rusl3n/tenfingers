import Foundation

/// Часть суток для приветствия на «Главной» (спецификация фазы 8, §5a).
public enum GreetingPart: String, CaseIterable, Sendable {
    case morning, day, evening, night
}

public enum Greeting {
    /// По часу (0…23) часов Mac: утро 5–11, день 12–16, вечер 17–22, ночь 23–4.
    public static func part(hour: Int) -> GreetingPart {
        switch hour {
        case 5...11: .morning
        case 12...16: .day
        case 17...22: .evening
        default: .night
        }
    }
}
