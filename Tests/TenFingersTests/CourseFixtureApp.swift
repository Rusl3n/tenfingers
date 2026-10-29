import Foundation
import TypingCore

/// Мини-курс издания 2 для тестов приложения: два этапа по пять уроков (копия `CourseFixtures.ruMini` из
/// `TypingCoreTests` — цель тестов приложения тех тестов не видит).
enum CourseFixtureApp {
    static let ruMiniJSON = """
    {
      "language": "ru",
      "edition": 2,
      "rows": { "top": "йцукенгшщзхъ", "home": "фывапролджэ", "bottom": "ячсмитьбю." },
      "stages": [
        { "id": "ru2.s1", "title": "Этап 1", "targetCpm": 60, "targetCpmEnd": 80, "hint": "full", "gateStars": 2,
          "lengths": { "drill": 30, "combos": 40, "words": 50, "phrases": 60, "check": 60 },
          "textStyle": { "case": "lower", "punctuation": "none", "digits": false },
          "lessons": [
            { "id": "ru2.s1.01", "title": "А и О", "kind": "keys", "newKeys": ["а", "о"] },
            { "id": "ru2.s1.02", "title": "В и Л", "kind": "keys", "newKeys": ["в", "л"] },
            { "id": "ru2.s1.03", "title": "Закрепление основного ряда", "kind": "rows", "rows": ["home"] },
            { "id": "ru2.s1.04", "title": "Повтор", "kind": "review" },
            { "id": "ru2.s1.check", "title": "Проверка этапа", "kind": "stageCheck", "hint": "onError" }
          ]},
        { "id": "ru2.s2", "title": "Этап 2", "targetCpm": 90, "targetCpmEnd": 110, "hint": "full",
          "lengths": { "drill": 60, "combos": 80, "words": 100, "phrases": 120, "sprint": 80, "check": 120 },
          "lessons": [
            { "id": "ru2.s2.01", "title": "К и Е", "kind": "keys", "newKeys": ["к", "е"] },
            { "id": "ru2.s2.02", "title": "Ускорение", "kind": "speedup" },
            { "id": "ru2.s2.03", "title": "Верхний и основной вместе", "kind": "rows", "rows": ["top", "home"], "minShare": 0.6 },
            { "id": "ru2.s2.04", "title": "Ступень 100", "kind": "tier", "targetCpm": 100 },
            { "id": "ru2.s2.check", "title": "Проверка этапа", "kind": "stageCheck" }
          ]}
      ]
    }
    """

    static func ruMini() throws -> Course {
        try JSONDecoder().decode(Course.self, from: Data(ruMiniJSON.utf8))
    }
}
