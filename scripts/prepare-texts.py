#!/usr/bin/env python3
"""Готовит texts-ru.json и texts-en.json: отрывки из произведений в общественном достоянии.

Источники:
  * Project Gutenberg (gutenberg.org), plain text UTF-8 — английские произведения;
  * ru.wikisource.org, сырая викиразметка (action=raw) — русские произведения
    (на Gutenberg русской классики практически нет).

Все авторы умерли более 70 лет назад. Скрипт не обходит сайты: список работ задан явно,
каждый файл скачивается один раз во временную папку, между запросами пауза 1 с.
Любая ошибка скачивания или разбора останавливает скрипт.

Из каждого произведения берутся пять последовательных отрывков: от начала первой главы (или тела
рассказа) целыми предложениями, 400–900 знаков (цель 650), конец — на границе предложения.
У первого отрывка прежний id (на него ссылается история сессий), у следующих — «<id>.2» … «<id>.5»,
название — «<название> · N». В конце печатается сумма знаков по языку (ожидание 35 000–45 000).

Скачанный файл — не больше 200 МБ, только по https (и после перенаправлений).

Запуск (stdlib only):  python3 -I scripts/prepare-texts.py
"""
import json
import re
import sys
import tempfile
import time
import unicodedata
import urllib.parse
import urllib.error
import urllib.request
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "Sources/TypingCore/Resources"
USER_AGENT = "TenFingersPrep/1.0 (offline typing tutor; one-off download of public-domain texts)"
MIN_LEN, TARGET_LEN, MAX_LEN = 400, 650, 900
MAX_DOWNLOAD = 200 * 1024 * 1024
PASSAGES = 5


def gutenberg(book_id):
    return f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.txt"


def wikisource(title):
    return "https://ru.wikisource.org/w/index.php?title=" + urllib.parse.quote(title.replace(" ", "_")) + "&action=raw"


# (id, автор, название, url, параметры разбора)
# heading — регулярное выражение строки заголовка первой главы (английские тексты),
# unindented — заголовок без отступа (отличает его от строки оглавления);
# skip — сколько абзацев тела пропустить (эпиграфы, посвящения).
EN = [
    ("en.austen.pride-and-prejudice", "Jane Austen", "Pride and Prejudice", gutenberg(1342),
     {"heading": r"^Chapter I\.\]\s*$"}),
    ("en.dickens.tale-of-two-cities", "Charles Dickens", "A Tale of Two Cities", gutenberg(98),
     {"heading": r"^CHAPTER I\.\s*$"}),
    ("en.twain.tom-sawyer", "Mark Twain", "The Adventures of Tom Sawyer", gutenberg(74),
     {"heading": r"^CHAPTER I\s*$"}),
    ("en.doyle.scandal-in-bohemia", "Arthur Conan Doyle", "A Scandal in Bohemia", gutenberg(1661),
     {"heading": r"^I\. A SCANDAL IN BOHEMIA\s*$"}),
    ("en.wilde.dorian-gray", "Oscar Wilde", "The Picture of Dorian Gray", gutenberg(174),
     {"heading": r"^CHAPTER I\.?\s*$"}),
    ("en.carroll.alice", "Lewis Carroll", "Alice's Adventures in Wonderland", gutenberg(11),
     {"heading": r"^CHAPTER I\.\s*Down the Rabbit-Hole\s*$|^CHAPTER I\.\s*$"}),
    ("en.melville.moby-dick", "Herman Melville", "Moby-Dick; or, The Whale", gutenberg(2701),
     {"heading": r"^CHAPTER 1\. Loomings\.?\s*$"}),
    ("en.stevenson.treasure-island", "Robert Louis Stevenson", "Treasure Island", gutenberg(120),
     {"heading": r"^I\s*$"}),
    ("en.wells.time-machine", "H. G. Wells", "The Time Machine", gutenberg(35),
     {"heading": r"^I\.\s*$"}),
    ("en.kipling.jungle-book", "Rudyard Kipling", "The Jungle Book", gutenberg(236),
     {"heading": r"^Mowgli.s Brothers\s*$", "unindented": True}),
    ("en.bronte.jane-eyre", "Charlotte Brontë", "Jane Eyre", gutenberg(1260),
     {"heading": r"^CHAPTER I\s*$"}),
    ("en.london.call-of-the-wild", "Jack London", "The Call of the Wild", gutenberg(215),
     {"heading": r"^Chapter I\. Into the Primitive\s*$", "unindented": True}),
]

RU = [
    ("ru.pushkin.captains-daughter", "Александр Пушкин", "Капитанская дочка",
     wikisource("Капитанская дочка (Пушкин)/Глава I"), {}),
    ("ru.pushkin.queen-of-spades", "Александр Пушкин", "Пиковая дама",
     wikisource("Пиковая дама (Пушкин)"), {}),
    ("ru.pushkin.station-master", "Александр Пушкин", "Станционный смотритель",
     wikisource("Станционный смотритель (Пушкин)"), {}),
    ("ru.lermontov.hero-of-our-time", "Михаил Лермонтов", "Герой нашего времени",
     wikisource("Герой нашего времени (Лермонтов)/Бэла"), {}),
    ("ru.gogol.dead-souls", "Николай Гоголь", "Мёртвые души",
     wikisource("Мёртвые души (Гоголь)/Том I/Глава I"), {}),
    ("ru.gogol.overcoat", "Николай Гоголь", "Шинель",
     wikisource("Шинель (Гоголь)/СС 1967 (СО)"), {}),
    ("ru.turgenev.mumu", "Иван Тургенев", "Муму",
     wikisource("Муму (Тургенев)"), {}),
    ("ru.turgenev.khor-and-kalinych", "Иван Тургенев", "Записки охотника: Хорь и Калиныч",
     wikisource("Хорь и Калиныч (Тургенев)"), {}),
    ("ru.chekhov.kashtanka", "Антон Чехов", "Каштанка",
     wikisource("Каштанка (Чехов)"), {}),
    ("ru.chekhov.lady-with-the-dog", "Антон Чехов", "Дама с собачкой",
     wikisource("Дама с собачкой (Чехов)"), {}),
    ("ru.tolstoy.anna-karenina", "Лев Толстой", "Анна Каренина",
     wikisource("Анна Каренина (Лев Толстой)/Часть I/Глава I"), {}),
    ("ru.dostoevsky.crime-and-punishment", "Фёдор Достоевский", "Преступление и наказание",
     wikisource("Преступление и наказание (Достоевский)/Часть I/Глава I"), {}),
]


def fetch(url, dest):
    if dest.exists():  # --cache: файл уже скачан при прошлом запуске
        return dest.read_text(encoding="utf-8")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    # Серверы (особенно Викитека) иногда обрывают TLS-соединение: до трёх попыток с паузой 5, 10 с.
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                if not response.geturl().startswith("https://"):
                    raise RuntimeError(f"перенаправление не по https: {response.geturl()}")
                data = response.read(MAX_DOWNLOAD + 1)
            break
        except urllib.error.URLError:
            if attempt == 2:
                raise
            time.sleep(5 * (attempt + 1))
    if len(data) > MAX_DOWNLOAD:
        raise RuntimeError(f"файл больше {MAX_DOWNLOAD // (1024 * 1024)} МБ: {url}")
    if not data:
        raise RuntimeError(f"пустой ответ: {url}")
    dest.write_bytes(data)
    return data.decode("utf-8")


REDIRECT = re.compile(r"^\s*#(?:redirect|перенаправление)\s*:?\s*\[\[([^\]|#]+)", re.I)


def fetch_wiki(url, dest):
    """Скачивает страницу Викитеки; редирект (#перенаправление) — следует по нему, возвращает итоговый URL."""
    for hop in range(3):
        raw = fetch(url, dest.with_name(dest.stem + (f".r{hop}" if hop else "") + dest.suffix))
        match = REDIRECT.match(raw)
        if not match:
            return raw, url
        url = wikisource(match.group(1).strip())
        time.sleep(1)
    raise RuntimeError("слишком много редиректов")


# --- очистка ---------------------------------------------------------------

def strip_marks(text):
    """Убирает ударения, мягкие переносы и служебные символы, приводит пробелы к обычным."""
    text = unicodedata.normalize("NFC", text)
    text = text.replace("́", "").replace("­", "").replace("﻿", "")
    text = text.replace(" ", " ").replace(" ", " ").replace(" ", " ")
    # Литературный пропуск названия («***ская губерния») звёздочками не напечатать — пишем «Н-ская» (кириллицей).
    text = re.sub(r"\*{3}(?=[а-яё])", "Н-", text)
    return text


def collapse(text):
    return re.sub(r"\s+", " ", text).strip()


def gutenberg_body(raw):
    start = re.search(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK[^\n]*\n", raw)
    end = re.search(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK", raw)
    if not start or not end:
        raise RuntimeError("не найдены маркеры Gutenberg START/END")
    return raw[start.end():end.start()].replace("\r\n", "\n")


HEADING_LIKE = re.compile(r"^(chapter\b|part\b|book\b|\d+\.\s|[IVXL]+\.?(\s|$))", re.I)


def gutenberg_paragraphs(body, heading, unindented=False):
    """Абзацы после первого заголовка, за которым идёт настоящая проза (не оглавление)."""
    lines = body.split("\n")
    pattern = re.compile(heading)
    for index, line in enumerate(lines):
        if not pattern.match(line.strip()) or (unindented and line.startswith(" ")):
            continue
        # Оглавление: сразу за заголовком идут другие заголовки.
        following = [l.strip() for l in lines[index + 1:index + 12] if l.strip()][:6]
        if sum(1 for l in following if HEADING_LIKE.match(l)) >= 2:
            continue
        paragraphs = []
        current = []
        for follow in lines[index + 1:index + 700]:  # хватает на пять отрывков
            if follow.strip() == "":
                if current:
                    paragraphs.append(current)
                    current = []
            else:
                current.append(follow)
        if current:
            paragraphs.append(current)
        prose = []
        for block in paragraphs:
            # Отступ — цитата/стихи/подзаголовок; в прозе Gutenberg отступов нет.
            if block[0].startswith(" ") or re.match(r"^\s*(\[|\{)", block[0]):
                continue
            # Стихи (эпиграфы): несколько коротких строк.
            if len(block) >= 2 and max(len(l) for l in block) < 55:
                continue
            text = collapse(" ".join(block))
            text = re.sub(r"\[Illustration[^\]]*\]", "", text).strip()
            if text:
                prose.append(text)
        # Оглавление даёт короткие «абзацы»; нужен заголовок, за которым сразу идёт длинный абзац.
        if any(len(p) >= 100 and not p.isupper() for p in prose):
            return prose
    raise RuntimeError("заголовок первой главы не найден")


def replace_templates(text):
    """Удаляет шаблоны {{...}} (вложенные — изнутри наружу), сохраняя текст разрядки."""
    keep = re.compile(r"\{\{\s*(?:razr|разрядка|разр|sp|s|iast|lang\|[^|{}]*|ВАР|нп)\s*\|([^{}|]*)(?:\|[^{}]*)?\}\}", re.I)
    pattern = re.compile(r"\{\{[^{}]*\}\}")
    while True:
        new = keep.sub(r"\1", text)
        new = pattern.sub("", new)
        if new == text:
            return text
        text = new


def wiki_paragraphs(raw):
    text = raw.replace("\r\n", "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"<noinclude>.*?</noinclude>", "", text, flags=re.S | re.I)
    text = re.sub(r"</?includeonly>|</?onlyinclude>", "", text, flags=re.I)
    text = re.sub(r"<(poem|blockquote|ref|references|gallery|table)\b[^>]*>.*?</\1>", "", text, flags=re.S | re.I)
    text = re.sub(r"<ref\b[^>]*/>", "", text, flags=re.I)
    text = replace_templates(text)
    text = re.sub(r"\{\|.*?\|\}", "", text, flags=re.S)
    text = re.sub(r"\[\[(?:Категория|Category|Файл|File|Image|Изображение)\s*:[^\]]*\]\]", "", text, flags=re.I)
    text = re.sub(r"\[\[[a-z\-]{2,8}:[^\]]*\]\]", "", text)  # интервики
    text = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[https?://[^\s\]]+\s*([^\]]*)\]", r"\1", text)
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"'{2,}", "", text)
    text = text.replace("&nbsp;", " ").replace("&mdash;", "—").replace("&ndash;", "–")
    text = re.sub(r"__[A-Z]+__", "", text)  # магические слова вроде __NOTOC__
    text = re.sub(r"^=+[^\n]*?=+[ \t]*$", "\n", text, flags=re.M)  # заголовки разделов — отдельный блок
    paragraphs = []
    for block in re.split(r"\n\s*\n", text):
        lines = [line.rstrip() for line in block.split("\n") if line.strip()]
        if not lines:
            continue
        if any(re.match(r"^\s*(=+|\*|#|:|;|\|)", line) for line in lines):
            continue
        # Стихи (много коротких строк) — не проза.
        if len(lines) >= 2 and sum(len(line) for line in lines) / len(lines) < 60:
            continue
        paragraph = collapse(" ".join(lines))
        if paragraph:
            paragraphs.append(paragraph)
    return paragraphs


# --- выбор отрывка ---------------------------------------------------------

SENTENCE_END = re.compile(r"(?<=[.!?…»\"”])\s+(?=[«\"“—–\-A-ZА-ЯЁ0-9])")


def split_sentences(paragraph):
    return [s for s in SENTENCE_END.split(paragraph) if s]


CHAPTER = re.compile(r"(chapter|part|book|глава|часть)\s+[IVXLC\d]+\b.*", re.I)


def is_chapter_heading(paragraph):
    """Номер или заголовок главы: «IV», «CHAPTER II.», «Глава III»."""
    return bool(re.fullmatch(r"[IVXLC\d]+\.?", paragraph) or (len(paragraph) < 80 and CHAPTER.fullmatch(paragraph)))


def is_subheading(paragraph):
    """Подзаголовок («The Period», «Down the Rabbit-Hole»): короткий, без знака конца предложения."""
    return len(paragraph) < 100 and not re.search(r"[.!?…»\"”]$", paragraph)


def body_paragraphs(paragraphs):
    """Абзацы без заголовков глав. Короткий абзац без конца предложения убирается только в начале текста
    и сразу за заголовком главы (её подзаголовок); посреди главы он остаётся — это может быть реплика."""
    result = []
    after_heading = True  # начало текста — как после заголовка
    for paragraph in paragraphs:
        if is_chapter_heading(paragraph):
            after_heading = True
            continue
        if after_heading and is_subheading(paragraph):
            continue
        after_heading = False
        result.append(paragraph)
    return result


def pick_passages(paragraphs, skip=0, count=PASSAGES, reject=None):
    """`count` последовательных отрывков MIN_LEN–MAX_LEN знаков от начала текста, каждый — целыми предложениями."""
    # Начало — первый «настоящий» абзац; заголовки следующих глав в отрывки не попадают.
    paragraphs = body_paragraphs(paragraphs[skip:])
    if not paragraphs:
        raise RuntimeError("нет подходящего абзаца")
    units = [part for paragraph in paragraphs for part in split_sentences(paragraph)]
    passages = []
    index = 0
    while len(passages) < count:
        # Если с этого предложения отрывок не набирается (слишком длинное), начинаем со следующего.
        for first in range(index, min(len(units), index + 3)):
            found = collect(units, first)
            if found:
                break
        else:
            raise RuntimeError(f"нашлось {len(passages)} отрывков из {count}: "
                               f"нет следующего {MIN_LEN}–{MAX_LEN} знаков, оканчивающегося предложением")
        text, index = found
        # Отрывок, который нельзя набрать на раскладке языка (латиница в русском тексте), пропускаем — берём следующий.
        if reject is None or not reject(text):
            passages.append(text)
    return passages


def collect(units, start):
    """Отрывок из предложений с `start`: первый вариант от TARGET_LEN, иначе самый длинный до MAX_LEN.
    Возвращает (текст, индекс следующего предложения) или None."""
    end_ok = re.compile(r"[.!?…][»\"”'’)\]]*$")
    text = ""
    best = None  # допустимый вариант конца отрывка
    for index in range(start, len(units)):
        extended = (text + " " + units[index]) if text else units[index]
        if len(extended) > MAX_LEN:
            break
        text = extended
        if len(text) >= MIN_LEN and end_ok.search(text):
            best = (text, index + 1)
            if len(text) >= TARGET_LEN:
                break
    return best


def check_modern_russian(text):
    if re.search(r"[ѣіѳѵѢІѲѴ]", text):
        raise RuntimeError("дореформенная орфография (ѣ, і, ѳ, ѵ)")
    if re.search(r"[бвгджзклмнпрстфхцчшщБВГДЖЗКЛМНПРСТФХЦЧШЩ]ъ(?![а-яё])", text):
        raise RuntimeError("дореформенная орфография (ъ на конце слова)")


def main():
    result = {"ru": [], "en": []}
    # --cache DIR: держать скачанные файлы в DIR между запусками (для отладки разбора).
    cache = Path(sys.argv[sys.argv.index("--cache") + 1]) if "--cache" in sys.argv else None
    with tempfile.TemporaryDirectory(prefix="tenfingers-texts-") as tmp:
        tmp_dir = cache or Path(tmp)
        tmp_dir.mkdir(parents=True, exist_ok=True)
        first = True
        for language, works in (("en", EN), ("ru", RU)):
            for work_id, author, title, url, options in works:
                cached = (tmp_dir / (work_id + ".txt")).exists()
                if not first and not cached:
                    time.sleep(1)
                first = False
                try:
                    if language == "en":
                        raw = fetch(url, tmp_dir / (work_id + ".txt"))
                        paragraphs = gutenberg_paragraphs(gutenberg_body(raw), options["heading"], options.get("unindented", False))
                    else:
                        raw, url = fetch_wiki(url, tmp_dir / (work_id + ".txt"))
                        paragraphs = wiki_paragraphs(raw)
                    passages = []
                    latin = (lambda text: re.search(r"[A-Za-z]", text) is not None) if language == "ru" else None
                    for passage in pick_passages(paragraphs, options.get("skip", 0), reject=latin):
                        text = strip_marks(passage)
                        text = text.replace("_", "") if language == "en" else text
                        if language == "ru":
                            check_modern_russian(text)
                        passages.append(text)
                except Exception as error:  # noqa: BLE001 — падаем громко с указанием работы
                    sys.exit(f"{work_id}: {error}  ({url})")
                for number, text in enumerate(passages, 1):
                    result[language].append({
                        "id": work_id if number == 1 else f"{work_id}.{number}",
                        "title": title if number == 1 else f"{title} · {number}",
                        "author": author, "source": url, "text": text,
                    })
                print(f"{work_id}: {' + '.join(str(len(text)) for text in passages)} знаков")
    for language, items in result.items():
        path = OUT_DIR / f"texts-{language}.json"
        path.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        total = sum(len(item["text"]) for item in items)
        print(f"записано {path.name}: {len(items)} отрывков, {total} знаков (ожидание 35 000–45 000)")


if __name__ == "__main__":
    main()
