<p align="center"><img src="docs/images/icon.png" width="128" alt="Ten Fingers icon"></p>

<h1 align="center">Ten Fingers</h1>

<p align="center">A touch-typing tutor for macOS — Russian and English layouts.</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version 1.0.0">
  <a href="https://github.com/Rusl3n/tenfingers/actions/workflows/tests.yml"><img src="https://github.com/Rusl3n/tenfingers/actions/workflows/tests.yml/badge.svg" alt="tests"></a>
</p>

<p align="center"><a href="README.md">Русская версия</a> · <a href="CHANGELOG.md">Changelog</a> (in Russian)</p>

![On-screen keyboard: Russian layout with "6" and the left Shift highlighted](docs/images/keyboard-ru.png)

## Features

- A lesson-based course in the spirit of "Solo on the Keyboard": 5 stages for each of Russian and English.
- An on-screen keyboard that follows your actual system layout (including remapped symbols, such as Shift+6 = ":" in "Russian – PC") and is colored by finger. Keyboard size is adjustable.
- A mistake stops the cursor: you have to press the correct key first.
- Hints that are gradually withdrawn: from a highlighted key and finger to typing blind.
- A lesson step indicator and a detailed exercise summary. A lesson resumes from the first step you haven't finished.
- Lesson stars take both speed and accuracy into account; a "?" next to the stars explains the rules, and the result screen tells you what is missing for the next star. The course map shows per-step details and lets you replay any single step.
- A space bar hint: the half under the thumb of the hand opposite to the previous character is highlighted.
- A large speed readout in the center of the exercise screen: green when you are at or above the target, red when below; an up or down arrow next to the target repeats the color.
- Adaptive training: letters unlock as you master them, with the focus on your weakest one.
- "Weak spots": 5 minutes on your worst keys and key pairs.
- Practice: frequent words, 24 classic excerpts (12 per language), digits and symbols, and your own text from the clipboard or a .txt file (Windows-1251 included) with your place remembered.
- Esc pauses the exercise and opens the sidebar; from another section, Esc takes you back to the paused lesson.
- Settings are split into sections; dragging the keyboard size or offset slider shows a full-size keyboard preview over the screen.
- Speed and accuracy are collected for every key while you type; the result screen shows the keys with the most errors.
- A daily streak: a full flame for reaching your daily goal (10 minutes of active typing by default), a half flame for any finished exercise. Freezes (up to two, a new one for every 7 full days in a row) cover a missed day. The home screen shows the streak, the last seven days, today's goal, and your weekly speed and accuracy.
- Analytics: speed and accuracy charts with a trend line, a keyboard heat map of errors and slow keys, per-finger statistics, a year-long activity calendar, records, the last 100 exercises, and course progress.
- Practice reminders at the time you choose; the text depends on your streak ("Your 12-day streak is at risk", "4 min left until a full flame").
- 68 achievements in eight categories: streak, speed, accuracy, course, volume, special, letters and funny ones. Everything you earned in past sessions is awarded the first time you launch a version with achievements, dated from your history, in one summary instead of an avalanche of messages. The Achievements screen shows your progress and, for the ones you do not have yet, how to get them; the latest achievement is on the home screen. The "Adult humor" setting hides the achievements with strong language without stopping you from earning them.
- "Share" cards: an achievement, a streak, a speed record, a finished stage or the whole course as an image with a signature of your choice, light or dark, colored or transparent, wide or square; copy it, save it as PNG or send it through the system menu.
- A profile (nickname and name) and progress transfer: all your progress, profile and settings can be saved to a file and loaded from it, for example on another Mac. Before loading, your current progress is backed up automatically.
- Sounds synthesized inside the app: key click, error, exercise finished, lesson passed, new achievement, streak. Each sound has its own volume and switch.
- Light (white, beige, gray) and dark (graphite, night, coffee) palettes; theme follows the system, is set manually, or switches on a schedule. Interface scale from 80 to 150%.
- English interface; the language follows your system settings.
- All data stays local: no network, no accounts, no telemetry.

## Screenshots

![Achievements screen (Russian interface): earned badges in color, the rest as gray silhouettes with the way to get them](docs/images/achievements.png)

![Share card: a 30-day streak, square, light theme (Russian)](docs/images/share-streak-ru.jpg)

![Share card: a speed record on the English layout, wide, dark theme](docs/images/share-speed-en.jpg)

![Home screen (Russian interface): a 20-day streak with 17 full days, the week with fires and a freeze, today's goal](docs/images/home.png)

![Analytics (Russian interface): error heat map on the Russian layout](docs/images/analytics-heatmap.png)

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

The README images are rendered by tests that are skipped by default:

```bash
RENDER_DOCS=1 swift test --filter renderReadmeImages
RENDER_DOCS=1 swift test --filter renderAchievementsImage
RENDER_DOCS=1 swift test --filter renderShareCardImages
```

Versions and history: [`CHANGELOG.md`](CHANGELOG.md), development rules: [`CONTRIBUTING.md`](CONTRIBUTING.md) (both in Russian). The app version is shown in About and at the bottom of Settings.

Design and work plans live in [`docs/superpowers`](docs/superpowers): the [specification](docs/superpowers/specs/2026-10-23-typing-tutor-design.md) and the [plans](docs/superpowers/plans). They are written in Russian.

## Licenses

- Code — [MIT](LICENSE). The MIT license covers the code, not the word lists.
- Word lists `Sources/TypingCore/Resources/words-*.txt` — filtered adaptations of the frequency lists from [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (OpenSubtitles 2018), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See also [`CREDITS.md`](Sources/TypingCore/Resources/CREDITS.md).
- The icon is drawn in code: [`scripts/make-icon.swift`](scripts/make-icon.swift).
