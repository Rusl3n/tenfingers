# Источники данных

- Частотные словари: hermitdave/FrequencyWords (OpenSubtitles 2018), лицензия CC BY-SA 4.0.
  https://github.com/hermitdave/FrequencyWords
- Файлы `words-*.txt` — отфильтрованные адаптации этих списков (только буквы, длина 2–12, первые 20000 слов); получены скриптом `scripts/prepare-words.sh`.
- Отрывки для практики (`texts-ru.json`, `texts-en.json`): фрагменты произведений в общественном достоянии (авторы умерли более 70 лет назад), по пять отрывков из каждого произведения. Английские тексты — Project Gutenberg (https://www.gutenberg.org), русские — Викитека (https://ru.wikisource.org). Точный адрес каждого текста записан в поле `source` соответствующего JSON; файлы получены скриптом `scripts/prepare-texts.py`.
- Корпус предложений (`sentences-ru.json`, `sentences-en.json`): Tatoeba (https://tatoeba.org), лицензия CC BY 2.0 FR (https://creativecommons.org/licenses/by/2.0/fr/). Предложения отобраны и нормализованы скриптом `scripts/prepare-sentences.py`; номер каждого предложения записан в поле `source` (`tatoeba:<id>`, страница https://tatoeba.org/sentences/show/<id>).
