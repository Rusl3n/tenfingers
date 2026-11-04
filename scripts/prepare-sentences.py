#!/usr/bin/env python3
"""Готовит sentences-ru.json и sentences-en.json: корпус предложений для шагов «Предложения» и «Текст».

Источник — Tatoeba (https://tatoeba.org), лицензия CC BY 2.0 FR: выгрузки по языкам
  https://downloads.tatoeba.org/exports/per_language/rus/rus_sentences.tsv.bz2
  https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
(строки «id<TAB>lang<TAB>text»). Каждый файл скачивается один раз во временную папку, между запросами
пауза 1 с; любая ошибка скачивания или разбора — выход с кодом 1.

Фильтр: типографские кавычки, тире, многоточие и необычные пробелы приводятся к набираемым; длина 20–140;
только буквы языка (без чужого алфавита), пробел, цифры и знаки «. , - ! ? : ; " ( )», у RU ещё «№ %»,
у EN ещё «' % $ & # @»; у RU заглавная «Ё» → «Е» (Shift+ё в RussianWin не печатается); без двух пробелов
подряд и без пробела перед знаком; кавычки и скобки парные; повторы (без учёта регистра) — один раз;
предложения со словами из списка-исключения Sources/TypingCore/Resources/blocklist.txt (грубая лексика;
тот же список читает WordFilter в приложении) отбрасываются; с именем «Tom»/«Том» — не больше 10% выборки.
Скачанный файл — не больше 200 МБ, только по https (и после перенаправлений); строка — не длиннее 4096 знаков.
Файлы пишутся, только когда оба языка отобраны без ошибок.

Выбор: детерминированный порядок по sha256(f"{lang}:{id}"); 2000 предложений на язык: сначала с цифрами
(не больше 300), остальное по длине: 20–60 знаков — 40%, 61–100 — 40%, 101–140 — 20%.

Вывод: Sources/TypingCore/Resources/sentences-{ru,en}.json — массив {"text", "traits", "source"}
по одной записи на строку, по возрастанию id; traits — как TextTraits.of (1 заглавные, 2 знаки, 4 цифры),
source — "tatoeba:<id>".

Запуск (stdlib only):  python3 -I scripts/prepare-sentences.py
Без сети (проверка на своих файлах):  python3 -I scripts/prepare-sentences.py --from DIR [--out DIR] [--count N]
  DIR содержит rus_sentences.tsv(.bz2) и eng_sentences.tsv(.bz2).
Проверка списка-исключения на примерах (без сети и без записи):  python3 -I scripts/prepare-sentences.py --check
"""
import bz2
import hashlib
import json
import re
import shutil
import sys
import tempfile
import time
import unicodedata
import urllib.request
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "Sources/TypingCore/Resources"
BLOCKLIST = OUT_DIR / "blocklist.txt"
MAX_DOWNLOAD = 200 * 1024 * 1024
MAX_LINE = 4096
USER_AGENT = "TenFingersPrep/1.0 (offline typing tutor; one-off download of CC BY sentences)"
URL = "https://downloads.tatoeba.org/exports/per_language/{code}/{code}_sentences.tsv.bz2"

TOTAL = 2000
MAX_DIGITS = 300
MIN_LEN, MAX_LEN = 20, 140
# Корзины длины: (от, до, доля).
BUCKETS = [(20, 60, 0.4), (61, 100, 0.4), (101, 140, 0.2)]
MAX_NAME_SHARE = 0.10

COMMON_SIGNS = set(" 0123456789.,-!?:;\"()")
LANGUAGES = {
    "ru": {
        "code": "rus",
        "chars": set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя") | set("АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        | COMMON_SIGNS | set("№%"),
        "name": re.compile(r"(?<![а-яё])том(?:а|у|ом|е)?(?![а-яё])"),
    },
    "en": {
        "code": "eng",
        "chars": set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") | COMMON_SIGNS | set("'%$&#@"),
        "name": re.compile(r"(?<![a-z])tom(?:'s)?(?![a-z])"),
    },
}

REPLACEMENTS = {
    "«": '"', "»": '"', "„": '"', "“": '"', "”": '"', "‘": "'", "’": "'",
    "—": "-", "–": "-", "−": "-", "…": "...",
}
INVISIBLE = {"​", "‌", "‍", "⁠", "﻿", "­"}
SPACE_BEFORE_SIGN = re.compile(r" [.,!?:;)%]")


def normalize(text, language):
    text = unicodedata.normalize("NFC", text)
    out = []
    for ch in text:
        if ch in INVISIBLE:
            continue
        if ch in REPLACEMENTS:
            out.append(REPLACEMENTS[ch])
        elif ch.isspace() or unicodedata.category(ch) in ("Zs", "Zl", "Zp"):
            out.append(" ")
        elif language == "ru" and ch == "Ё":
            out.append("Е")
        else:
            out.append(ch)
    return "".join(out).strip()


LETTER = "[a-zа-яё]"


def blocklist_pattern(path=BLOCKLIST):
    """Выражение по списку-исключению: строки «any|start|word фрагмент» (как WordFilter.pattern в Swift)."""
    parts = []
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split(" ", 1)
        if len(fields) != 2 or fields[0].startswith("#"):
            continue
        kind, fragment = fields
        if kind == "any":
            parts.append(f"(?:{fragment})")
        elif kind == "start":
            parts.append(f"(?<!{LETTER})(?:{fragment})")
        elif kind == "word":
            parts.append(f"(?<!{LETTER})(?:{fragment})(?!{LETTER})")
    if not parts:
        raise RuntimeError(f"пустой список-исключение: {path}")
    return re.compile("|".join(parts))


# Примеры для --check (те же — в WordFilterTests).
BLOCKED_EXAMPLES = [
    "нахуй", "похуй", "охуеть", "спиздил", "распиздяй", "наебал", "поебать", "проебал", "ебёт", "ебля",
    "выблядок", "блядь", "бля", "сука", "срал", "сраный", "ублюдок", "дерьмо", "задницу", "секс", "педик",
    "motherfucker", "bullshit", "goddamn", "jackass", "dumbass", "dickhead", "fuck", "shit", "damn", "ass",
    "bitch", "bastard", "asshole", "dick", "cunts",
    "сукин", "насрать", "засранец", "обосрался", "сиськи", "херня", "гондон", "пидр", "педераст", "долбоёб",
    "долбоеб", "уёбок", "ебошить", "наёбка", "порно", "порнографический", "гей", "геи", "геев",
    "cocksucker", "blowjob", "dildo", "skank", "prostitute", "hooker", "stripper", "prick", "pricks", "bugger",
    "buggered", "pimp", "pimps", "penis", "vaginas", "sperm", "nude", "nudes",
    "ниггер", "ниггеры", "нигер", "негр", "негры", "негром", "негритянской", "геем", "гомик", "лесбиянка", "чурка",
    "хачи", "жид", "жиды", "жидовка", "пиндос", "nigger", "niggas", "negro", "negroes", "japs", "dyke", "homo", "tranny",
]
CLEAN_EXAMPLES = [
    "корабля", "хлеб", "сравнить", "срам", "колебать", "небо", "ребус", "убедить", "обедать", "набег", "сук",
    "педикюр", "трахея", "класс", "sushi", "essex", "scunthorpe", "assist", "class", "grass", "dickens", "cocktail", "grape",
    "swanky", "sniggering", "сражение", "упорно", "упорный", "гейзер", "гейша", "сергей", "precious", "primp", "stripe",
    "неграмотны", "негромко", "жидкость", "жидкий", "хачапури", "japan", "japanese", "homogeneous", "raccoon",
]


def check(blocked):
    wrong = [w for w in BLOCKED_EXAMPLES if not blocked.search(w)] + [w for w in CLEAN_EXAMPLES if blocked.search(w)]
    if wrong:
        raise RuntimeError("список-исключение ошибается на: " + ", ".join(wrong))
    print(f"список-исключение: {len(BLOCKED_EXAMPLES)} отсеяно, {len(CLEAN_EXAMPLES)} пропущено — верно")


def traits(text):
    """Как TextTraits.of: заглавная — 1; иначе цифра ASCII — 4; иначе знак (P*, S*) — 2."""
    value = 0
    for ch in text:
        if ch.isupper():
            value |= 1
        elif ch in "0123456789":
            value |= 4
        elif unicodedata.category(ch)[0] in "PS":
            value |= 2
    return value


# Дореформенные и канцелярские формы из старых указов в корпусе («другаго», «паки», «буде»): для упражнений не годятся.
ARCHAIC_RU = re.compile(r"(?<![а-яё])(?:[а-яё]+(?:аго|яго)|паки|ежели|буде|инако|понеже|аще|дабы|оныя|сиих|сего|онаго)(?![а-яё])")
ARCHAIC_KEEP = {"благо", "сего"}


def archaic(text):
    """Есть ли в русском предложении старинная форма (кроме обычных слов вроде «много», «благо»)."""
    return any(m.group(0) not in ARCHAIC_KEEP for m in ARCHAIC_RU.finditer(text.lower()))


def accept(text, language, blocked):
    """Годится ли нормализованное предложение (без проверки повторов)."""
    if language == "ru" and archaic(text):
        return False
    if not MIN_LEN <= len(text) <= MAX_LEN:
        return False
    if any(ch not in LANGUAGES[language]["chars"] for ch in text):
        return False
    if "  " in text or SPACE_BEFORE_SIGN.search(text):
        return False
    if text.count('"') % 2 or text.count("(") != text.count(")"):
        return False
    return not blocked.search(text.lower())


def read_rows(path):
    opener = bz2.open if path.suffix == ".bz2" else open
    with opener(path, "rt", encoding="utf-8") as handle:
        line_number = 0
        while True:
            line = handle.readline(MAX_LINE)
            if not line:
                break
            line_number += 1
            if len(line) == MAX_LINE and not line.endswith("\n"):
                # Слишком длинная строка — не предложение: дочитываем её кусками и пропускаем.
                while (rest := handle.readline(MAX_LINE)) and not rest.endswith("\n"):
                    pass
                continue
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 2)
            if len(parts) != 3 or not parts[0].isdigit():
                raise RuntimeError(f"{path.name}:{line_number}: ожидалось «id<TAB>lang<TAB>text»")
            yield int(parts[0]), parts[2]


def candidates(rows, language, blocked):
    seen = set()
    result = []
    for sentence_id, raw in rows:
        text = normalize(raw, language)
        if not accept(text, language, blocked):
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append((sentence_id, text))
    return result


def order_key(language, sentence_id):
    return hashlib.sha256(f"{language}:{sentence_id}".encode()).hexdigest()


def select(pool, language, total=TOTAL):
    """Выбор по детерминированному порядку: цифры (до 300), затем корзины длины; имя — не больше 10%."""
    name = LANGUAGES[language]["name"]
    ordered = sorted(pool, key=lambda item: order_key(language, item[0]))
    max_digits = total * MAX_DIGITS // TOTAL  # 300 из 2000; при --count — в той же доле
    name_limit = int(total * MAX_NAME_SHARE)
    chosen, chosen_ids = [], set()
    names = 0

    def take(item):
        nonlocal names
        has_name = bool(name.search(item[1].lower()))
        if has_name and names >= name_limit:
            return False
        names += has_name
        chosen.append(item)
        chosen_ids.add(item[0])
        return True

    digits = [item for item in ordered if any(ch.isdigit() for ch in item[1])]
    plain = [item for item in ordered if not any(ch.isdigit() for ch in item[1])]
    for item in digits:
        if len(chosen) >= max_digits:
            break
        take(item)

    rest = total - len(chosen)
    quotas = [round(rest * share) for _, _, share in BUCKETS]
    quotas[-1] = rest - sum(quotas[:-1])
    for (low, high, _), quota in zip(BUCKETS, quotas):
        taken = 0
        for item in plain:
            if taken >= quota:
                break
            if item[0] not in chosen_ids and low <= len(item[1]) <= high and take(item):
                taken += 1
    # Корзине не хватило — добираем из остальных предложений без цифр в том же порядке.
    for item in plain:
        if len(chosen) >= total:
            break
        if item[0] not in chosen_ids:
            take(item)
    # Итог меньше нормы — доля имени считается от фактического числа.
    while names > int(len(chosen) * MAX_NAME_SHARE):
        index = max(i for i, item in enumerate(chosen) if name.search(item[1].lower()))
        chosen_ids.discard(chosen.pop(index)[0])
        names -= 1
    return sorted(chosen)


def write(items, path):
    records = [
        json.dumps({"text": text, "traits": traits(text), "source": f"tatoeba:{sentence_id}"}, ensure_ascii=False)
        for sentence_id, text in items
    ]
    path.write_text("[\n" + ",\n".join(records) + "\n]\n", encoding="utf-8")


def fetch(url, dest):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, open(dest, "wb") as out:
        if not response.geturl().startswith("https://"):
            raise RuntimeError(f"перенаправление не по https: {response.geturl()}")
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_DOWNLOAD:
                raise RuntimeError(f"файл больше {MAX_DOWNLOAD // (1024 * 1024)} МБ: {url}")
            out.write(chunk)
    if size == 0:
        raise RuntimeError(f"пустой ответ: {url}")


def source_file(directory, code):
    for name in (f"{code}_sentences.tsv.bz2", f"{code}_sentences.tsv"):
        if (directory / name).exists():
            return directory / name
    raise RuntimeError(f"в {directory} нет {code}_sentences.tsv(.bz2)")


def option(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    blocked = blocklist_pattern()
    check(blocked)
    if "--check" in sys.argv:
        return
    local = option("--from")
    out_dir = Path(option("--out", OUT_DIR))
    total = int(option("--count", TOTAL))
    tmp = None if local else Path(tempfile.mkdtemp(prefix="tenfingers-sentences-"))
    selected = {}
    try:
        for index, (language, spec) in enumerate(LANGUAGES.items()):
            if local:
                path = source_file(Path(local), spec["code"])
            else:
                if index:
                    time.sleep(1)
                url = URL.format(code=spec["code"])
                path = tmp / f"{spec['code']}_sentences.tsv.bz2"
                print(f"скачиваю {url}")
                fetch(url, path)
            pool = candidates(read_rows(path), language, blocked)
            selected[language] = (select(pool, language, total), len(pool))
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    # Пишем только после того, как отобраны оба языка: половинчатого обновления не бывает.
    for language, (items, pool_size) in selected.items():
        out = out_dir / f"sentences-{language}.json"
        write(items, out)
        count = len(items) or 1
        share = lambda bit: 100 * sum(1 for _, text in items if traits(text) & bit) / count  # noqa: E731
        print(f"{out.name}: {len(items)} предложений из {pool_size} подходящих; "
              f"с цифрами {share(4):.0f}%, с заглавными {share(1):.0f}%, со знаками {share(2):.0f}%")
        if len(items) < total:
            print(f"  внимание: меньше {total} предложений", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 — любая ошибка: сообщение и код 1
        print(f"ошибка: {error}", file=sys.stderr)
        sys.exit(1)
