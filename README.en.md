<p align="center"><img src="docs/images/icon.png" width="128" alt="Ten Fingers icon"></p>

<h1 align="center">Ten Fingers</h1>

<p align="center">A touch-typing tutor for macOS — Russian and English layouts.</p>

<p align="center"><a href="README.md">Русская версия</a></p>

![On-screen keyboard: Russian layout with "6" and the left Shift highlighted](docs/images/keyboard-ru.png)

## Features

- A lesson-based course in the spirit of "Solo on the Keyboard": 5 stages for each of Russian and English.
- An on-screen keyboard that follows your actual system layout (including remapped symbols, such as Shift+6 = ":" in "Russian – PC") and is colored by finger. Keyboard size is adjustable.
- A mistake stops the cursor: you have to press the correct key first.
- Hints that are gradually withdrawn: from a highlighted key and finger to typing blind.
- A lesson step indicator and a detailed exercise summary.
- A large speed readout in the center of the exercise screen: green when you are at or above the target, red when below; an up or down arrow next to the target repeats the color.
- Adaptive training: letters unlock as you master them, with the focus on your weakest one.
- "Weak spots": 5 minutes on your worst keys and key pairs.
- Practice: frequent words, 24 classic excerpts (12 per language), digits and symbols, and your own text from the clipboard or a .txt file (Windows-1251 included) with your place remembered.
- Esc pauses the exercise and opens the sidebar; from another section, Esc takes you back to the paused lesson.
- Settings are split into sections; dragging the keyboard size or offset slider shows a full-size keyboard preview over the screen.
- Speed and accuracy are collected for every key while you type; the result screen shows the keys with the most errors.
- Sounds synthesized inside the app: key click, error, exercise finished, lesson passed. Each sound has its own volume and switch.
- Light (white, beige, gray) and dark (graphite, night, coffee) palettes; theme follows the system, is set manually, or switches on a schedule.
- English interface; the language follows your system settings.
- All data stays local: no network, no accounts, no telemetry.

### In development

- A daily streak with full and half fire and freezes, detailed analytics by key, finger and bigram, reminders.
- Achievements, including funny ones.

## Screenshots

![Exercise text: typed part in gray, current character highlighted in red after a mistake](docs/images/exercise-text.png)

![Dark "Night" theme, English layout](docs/images/keyboard-en-dark.png)

## Install from source

Requirements: macOS 15 or later, Xcode 26 or later.

```bash
git clone https://github.com/Rusl3n/tenfingers.git
cd tenfingers
./scripts/build-app.sh
```

The script builds a release version, signs it ad hoc and copies it to `/Applications`. The app appears in Applications as "Десять пальцев" (Ten Fingers).

## Development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

The Swift package has two modules:

- `TypingCore` — pure logic with no AppKit or SwiftUI: keyboard geometry, finger map, typing engine, course, text generation, sound synthesis. Covered by tests.
- `TenFingers` — the app: SwiftUI interface, layout detection via TIS, SwiftData storage, sounds, themes.

The README images are rendered by a test that is skipped by default:

```bash
RENDER_DOCS=1 swift test --filter renderReadmeImages
```

Design and work plans live in [`docs/superpowers`](docs/superpowers): the [specification](docs/superpowers/specs/2026-10-23-typing-tutor-design.md) and the [plans](docs/superpowers/plans). They are written in Russian.

## Licenses

- Code — [MIT](LICENSE). The MIT license covers the code, not the word lists.
- Word lists `Sources/TypingCore/Resources/words-*.txt` — filtered adaptations of the frequency lists from [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (OpenSubtitles 2018), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See also [`CREDITS.md`](Sources/TypingCore/Resources/CREDITS.md).
- The icon is drawn in code: [`scripts/make-icon.swift`](scripts/make-icon.swift).
