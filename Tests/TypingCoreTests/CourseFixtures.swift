import Foundation
@testable import TypingCore

/// Мини-курс издания 2 для тестов формата, гейта и проверки структуры: два этапа по пять уроков.
/// Урок — одна строка JSON, чтобы тесты могли портить копию заменой строк.
enum CourseFixtures {
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

    /// Курс из 7 этапов для планировщика связного текста: этап 1 открывает все буквы, кроме «ё»; на этапах 4 и 7 —
    /// длина `text` и стиль (на этапе 4 ещё «Ускорение» и ступень), этапы 2, 3, 5, 6 — только проверки. Структура не проходит `CourseValidator` (и не должна).
    static let ruTextJSON = """
    {
      "language": "ru",
      "edition": 2,
      "rows": { "top": "йцукенгшщзхъ", "home": "фывапролджэ", "bottom": "ячсмитьбю." },
      "stages": [
        { "id": "ru2.s1", "title": "Этап 1", "targetCpm": 60, "hint": "full",
          "lengths": { "drill": 30, "combos": 40, "words": 50, "phrases": 60, "check": 60 },
          "lessons": [
            { "id": "ru2.s1.01", "title": "Все буквы", "kind": "keys",
              "newKeys": ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ", "ф", "ы", "в", "а", "п", "р",
                          "о", "л", "д", "ж", "э", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю"] },
            { "id": "ru2.s1.check", "title": "Проверка этапа", "kind": "stageCheck" }
          ]},
        { "id": "ru2.s2", "title": "Этап 2", "targetCpm": 90, "hint": "full", "lengths": { "check": 120 },
          "lessons": [ { "id": "ru2.s2.check", "title": "Проверка этапа", "kind": "stageCheck" } ]},
        { "id": "ru2.s3", "title": "Этап 3", "targetCpm": 110, "hint": "full", "lengths": { "check": 160 },
          "lessons": [ { "id": "ru2.s3.check", "title": "Проверка этапа", "kind": "stageCheck" } ]},
        { "id": "ru2.s4", "title": "Этап 4", "targetCpm": 130, "targetCpmEnd": 150, "hint": "onError",
          "lengths": { "drill": 100, "combos": 120, "words": 200, "phrases": 240, "text": 280, "sprint": 100, "check": 280 },
          "textStyle": { "case": "lower", "punctuation": "none", "digits": false },
          "lessons": [
            { "id": "ru2.s4.01", "title": "Буква Ё", "kind": "keys", "newKeys": ["ё"] },
            { "id": "ru2.s4.02", "title": "Связный текст I", "kind": "text" },
            { "id": "ru2.s4.03", "title": "Классика: Пушкин", "kind": "text", "textSource": "ru.pushkin." },
            { "id": "ru2.s4.04", "title": "Ускорение", "kind": "speedup" },
            { "id": "ru2.s4.05", "title": "Ступень 140", "kind": "tier", "targetCpm": 140 },
            { "id": "ru2.s4.check", "title": "Проверка этапа", "kind": "stageCheck" }
          ]},
        { "id": "ru2.s5", "title": "Этап 5", "targetCpm": 140, "hint": "hidden", "lengths": { "check": 300 },
          "lessons": [ { "id": "ru2.s5.check", "title": "Проверка этапа", "kind": "stageCheck" } ]},
        { "id": "ru2.s6", "title": "Этап 6", "targetCpm": 150, "hint": "hidden", "lengths": { "check": 300 },
          "lessons": [ { "id": "ru2.s6.check", "title": "Проверка этапа", "kind": "stageCheck" } ]},
        { "id": "ru2.s7", "title": "Этап 7", "targetCpm": 200, "hint": "hidden",
          "lengths": { "words": 300, "phrases": 400, "text": 500, "sprint": 150, "check": 600 },
          "textStyle": { "case": "lower", "punctuation": "none", "digits": false },
          "lessons": [
            { "id": "ru2.s7.01", "title": "Длинный текст I", "kind": "text" },
            { "id": "ru2.s7.check", "title": "Итоговая проверка курса", "kind": "stageCheck" }
          ]}
      ]
    }
    """

    static func ruText() throws -> Course { try decode(ruTextJSON) }

    static func decode(_ json: String) throws -> Course {
        try JSONDecoder().decode(Course.self, from: Data(json.utf8))
    }

    static func ruMini() throws -> Course { try decode(ruMiniJSON) }

    /// Встроенный курс издания 1: архив `course-<lang>-v1.json`; у языка без архива — текущий файл (ещё издание 1).
    static func editionOne(_ language: Language) throws -> Course {
        try CourseCatalog.legacy(language) ?? CourseCatalog.load(language)
    }
}
