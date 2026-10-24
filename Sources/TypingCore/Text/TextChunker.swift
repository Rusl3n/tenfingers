import Foundation

/// Нарезает длинный текст на порции по границе слов.
public enum TextChunker {
    public static func chunk(_ text: String, from offset: Int, size: Int = 500) -> (text: String, nextOffset: Int) {
        let characters = Array(text)
        var start = min(max(offset, 0), characters.count)
        while start < characters.count && characters[start] == " " { start += 1 }
        guard start < characters.count else { return ("", characters.count) }
        var end = min(start + size, characters.count)
        // Если сразу за порцией пробел, она уже кончается на границе слова: не отступаем назад.
        if end < characters.count, characters[end] != " ", let space = characters[start..<end].lastIndex(of: " "), space > start {
            end = space
        }
        let chunk = String(characters[start..<end]).trimmingCharacters(in: .whitespaces)
        return (chunk, end)
    }
}
