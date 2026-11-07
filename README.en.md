<p align="center"><img src="docs/images/icon.png" width="128" alt="TenFingers icon"></p>

<h1 align="center">TenFingers</h1>

<p align="center">A touch-typing tutor for macOS — Russian and English layouts.</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0.0-blue" alt="Version 3.0.0">
  <a href="https://github.com/Rusl3n/tenfingers/actions/workflows/tests.yml"><img src="https://github.com/Rusl3n/tenfingers/actions/workflows/tests.yml/badge.svg" alt="tests"></a>
</p>

<p align="center"><a href="README.md">Русская версия</a> · <a href="CHANGELOG.md">Changelog</a> (in Russian)</p>

![On-screen keyboard: Russian layout with "6" and the left Shift highlighted](docs/images/keyboard-ru.png)

## Features

- "Today's plan" on the home screen: a warm-up, a lesson, a training and a text; the items start one at a time, and after each one a screen reads "Item N of 4 done · Next: ...". The size of the plan follows your daily goal.
- The home screen is laid out top to bottom: an update banner (when a new version is out), the "Flame" streak with the daily goal and the "Spark" with your level, the week strip, the metrics, then the tabs "Today's plan", "Challenges", "Continue the course" and "Training and practice", and the latest achievement. The tabs have icons; a red dot on a tab means it has something new: a new plan day, a new or completed challenge, a new course lesson. The app remembers the tab you picked.
- A course of 98 lessons per language in 7 stages, from the home row to long texts: 6-8 steps per lesson (words from the rows, phrases, sentences, connected text, hard letters, words with your mistakes, a sprint, numbers). "Review" is built from your own errors, "Speed-up" runs on your strong letters with a "Beat yourself" reference. Speed tiers start at stage 2. A stage check (★★ on the first stage, ★★★ on the rest) opens the next stage, and you can take it right away to skip ahead. Finish all 7 stages and the "Certificate" card shows your average speed. The old 30-lesson course is kept as an archive.
- An on-screen keyboard that follows your actual system layout (including remapped symbols, such as Shift+6 = ":" in "Russian – PC") and is colored by finger. Keyboard size is adjustable, and the keyboard scales smoothly when you change it.
- A mistake stops the cursor: you have to press the correct key first.
- Hints that are gradually withdrawn: from a highlighted key and finger to typing blind.
- A lesson step indicator and a detailed exercise summary. A lesson resumes from the first step you haven't finished.
- Five stars per lesson for speed and errors; a "?" next to the stars explains the rules, and the result screen tells you, in errors, what is missing for the next star. Lessons show the number of errors instead of percentages. The course map shows errors, speed and stars per lesson and step and lets you replay any single step.
- A space bar hint: the half under the thumb of the hand opposite to the previous character is highlighted.
- A large speed readout in the center of the exercise screen: green when you are at or above the target, red when below; an up or down arrow next to the target repeats the color.
- Adaptive training: letters unlock as you master them, with the focus on your weakest one.
- "Weak spots": 5 minutes on your worst keys and key pairs.
- Practice: frequent words, 120 classic excerpts (60 per language), digits and symbols, and your own text from the clipboard or a .txt file (Windows-1251 included) with your place remembered.
- Esc pauses the exercise and opens the sidebar; from another section, Esc takes you back to the paused lesson.
- Settings are split into sections; dragging the keyboard size or offset slider shows a full-size keyboard preview over the screen.
- Speed and accuracy are collected for every key while you type; the result screen shows the keys with the most errors.
- A daily streak: a full flame for reaching your daily goal (10 minutes of active typing by default), a half flame for any finished exercise. Freezes (up to two, a new one for every 7 full days in a row) cover a missed day. The home screen shows the streak, the calendar week (the first day of the week is configurable), today's goal, and your weekly speed and accuracy.
- "Spark" is a second streak next to the flame: a day counts for any finished exercise, and freezes do not apply to it. It is also in the "Days" block of Analytics and on the "My progress" card; the Spark milestones are achievements for 7, 30, 100 and 365 days. "Goal" (in a row and in total) stays next to the flame.
- "Refresh": weakly passed lessons (two stars or fewer) come back on the course map after 1 day, then after 3 and 7 days, "hard" ones once every 14 days; well-passed lessons are refreshed by a rotation in the plan's warm-up.
- "Training → Fingers": a hand diagram rating each finger from your history; "Finger accuracy" for the weak ones and "Finger speed" for the strong ones.
- Levels and challenges: experience comes from time spent practicing (accurate work counts more), lessons, stars, full days and challenges, counted over your whole history; the level is recomputed and can drop if you raise your daily goal. The home screen shows "Level N · title" with a progress bar under the Spark. Three weekly challenges (one may be hard) and one monthly challenge are picked anew every Monday and on the 1st; the "Challenges" card shows progress and days left. Analytics has experience by week, a speed rank on your records and the completed challenges.
- Streak repair: a missed day with no freezes left can be saved by a double daily goal the next day (no more than once in 7 days). It is marked with a green bandage, the streak is not broken while the repair is under way, the home screen shows a "Streak by a thread" banner, and that day's reminders talk about the repair.
- Analytics: speed and accuracy charts with a trend line, a keyboard heat map of errors and slow keys, per-finger statistics, a year-long activity calendar, records, the last 100 exercises, and course progress.
- Practice reminders: once a day, three times a day, or every N hours within a window you set; a tone for the texts (plain, funny or mixed) and escalation, where each reminder of the day is pushier than the previous one. The text depends on your streak ("Your 12-day streak is at risk", "4 min left until a full flame").
- 164 achievements in eleven categories: streak, speed, accuracy, course, milestones, volume, special, letters, funny ones, "Rhythm" and "Training". Each has a joke, and each earned one has an "Earned for" line. Repeatable achievements (time of day, visits, speed records, five stars and more) can be earned many times: the badge shows "×N", the details list every time with its date and value, and the lesson result shows a "New" or "Repeat" card. 32 of them are secret: until earned they show as "???" and do not reveal how to get them; an "All / Earned / Not earned" filter (and "New" with red dots while there is something unseen) helps you find what you need. Everything you earned in past sessions is awarded the first time you launch a version with achievements, dated from your history, in one summary instead of an avalanche of messages. The latest achievement is on the home screen. The "Adult humor" setting hides the achievements with strong language without stopping you from earning them.
- "Share" cards: an achievement (its joke and the optional "Earned for" line, off by default, can be switched), a speed record, a finished stage or the whole course, and "My progress" with a month or year calendar, as an image with a signature of your choice, light or dark, colored or transparent, wide, square or a vertical 1080×1920 story; optionally with a QR code of the project. Copy it, save it as PNG or send it through the system menu.
- A profile (nickname and name) and progress transfer: all your progress, profile and settings can be saved to a file and loaded from it, for example on another Mac. Before loading, your current progress is backed up automatically.
- Sounds synthesized inside the app: key click, error, exercise finished, lesson passed, new achievement, streak. Each sound has its own volume and switch.
- Light (white, beige, gray) and dark (graphite, night, coffee) palettes; theme follows the system, is set manually, or switches on a schedule. Interface scale from 80 to 150%.
- A first-launch introduction (skippable, and you can replay it from the profile) and hover tips; a "?" next to the harder concepts.
- Russian and English interface; choose the language in Settings → General or follow the system.
- Updates from within the app: a check for a new version once a day (it can be turned off), a banner on the home screen and a one-click install with a backup of your progress (see "Updates").
- "Rhythm": a rhythm game with falling notes. Letters travel down eight finger lanes and you press them in time with a synthesized beat; four note modes (unlocked letters, locked letters, trouble letters and words), levels from "Easy" to "Expert", "My pace" based on your typing speed and an "Endless" level whose tempo keeps rising. After a run there is a breakdown (strong and weak letters, mix-ups, fingers) and "Train weak letters", records for every combination and a "Sound offset" for headphones with a delay. Game minutes count toward the daily goal and the flame, while the game does not change your typing speed.
- Course breakdown: after every step a small speed chart by text segments (slow segments are highlighted, hover shows their words) and two or three lines on what went well and what got in the way; on the lesson result a full breakdown: speed per step, the best step, letters and a finger worth working on, and a "Where next" button. Training, practice and "Rhythm" have no breakdown. A strict step: at most 4 errors per 100 characters (never fewer than 3 allowed), an "errors N of M" counter while you type, and a step with too many errors has to be repeated. Lesson checks and the stage check have no limit. The certificate is visible ahead of time: a "Certificate" row with the condition and your progress at the top of "Course" and in "Analytics → Course progress", with a sample marked "Sample" on click.
- Words with errors: the app remembers the real dictionary words you get wrong (up to 200 per language) and marks them fixed after three clean runs in a row. The "Words with errors" session is in "Training" and on the home screen; in the daily plan it replaces "Review" with 20 or more words; the "Letters in training" setting picks the letters open in the course or all of them. A "Fixed words" series of achievements for 10, 50, 200 and 1000 fixed words.
- Speed test in "Training": 1, 2 or 5 minutes or a 300-character text, kinds "Simple", "Capitals and punctuation" and "With digits", no Backspace; the result compares with your first and previous test, and the history keeps the first and the last 5. "Watch replay" shows your typing with fingertips: "As recorded", ×1.5, ×2, ×3 and "Master" (1000 chars/min). The test is also offered after the first-launch introduction. Two speed-test achievements ("First Speed Test", "Twice the First Test").
- Fingertips above the keyboard on the key introduction (the "Key introduction" button on a lesson row, including passed lessons); a "Finger animation" setting.
- Profiles: several students on one Mac, each with their own progress, flame, achievements and settings. Switch with the profile row at the bottom of the sidebar or the "Profile" menu (the app restarts); no passwords.
- A desktop widget, small and medium: the streak, the daily goal and the latest achievements (see "Widget").
- All data stays local: no accounts and no telemetry. The only network request is the update check; turn it off and the app never touches the network.

## Screenshots

![Home screen (Russian interface): an "Update available 2.6.0" banner with three buttons, a 20-day flame and a 3-day Spark, the daily goal and level, the week, the tabs "Today's plan", "Challenges" (with a red dot), "Continue the course" and "Training and practice"; the four-item plan is open](docs/images/home.png)

![Course map (Russian interface): the first stage with passed lessons, stars and speed, a "Refresh" mark on a weakly passed lesson, the next stage locked until the check](docs/images/course.png)

![Achievements screen (Russian interface): earned badges in color, each with a joke and the date; "All / Earned / Not earned" filters and categories on top](docs/images/achievements.png)

![Share card: a 30-day streak, square, light theme (Russian)](docs/images/share-streak-ru.jpg)

![Share card: a speed record on the English layout, wide, dark theme](docs/images/share-speed-en.jpg)

![Desktop widget, medium size (Russian interface): the streak and Spark, the daily goal (in progress and reached), the three latest achievements](docs/images/widget.png)

![Settings, the General section (Russian interface): language, scale, theme and palettes, update check, window, adult humor](docs/images/settings.png)

![Analytics (Russian interface): error heat map on the Russian layout](docs/images/analytics-heatmap.png)

![Exercise text: typed part in gray, current character highlighted in red after a mistake](docs/images/exercise-text.png)

![Dark "Night" theme, English layout](docs/images/keyboard-en-dark.png)

The images are drawn by tests on made-up data (see "Development"); version 2.6.0 on the update banner is invented for the example.

## Installation

1. Download the `.dmg` file from the [latest release page](https://github.com/Rusl3n/tenfingers/releases/latest), open it and drag "TenFingers" to Applications. Requires macOS 15 or later.
2. First launch. The app is not notarized, so macOS will stop it. Open System Settings → Privacy & Security and click "Open Anyway". Another way is this command in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TenFingers.app
   ```

3. Updates: see the section below.
4. Fallback — [build from source](#build-from-source).

## Updates

The app checks for new versions by itself ("Check for updates automatically" in Settings → General can turn this off; "Check now" is there too). When a version is out, a banner appears at the top of Home: "What's new", "Install" or "Skip this version". On install, the app downloads the version, verifies its size, checksum and signature, replaces itself and restarts. Your progress is kept: before replacing, two verified copies are made — of the database and of the progress archive — in `TenFingers.backups/before-update-*`; the three latest are kept. If the new version cannot open the database, the error screen offers a "Restore the previous version" button.

## Widget

Since version 2.5.0 the app has a "TenFingers" desktop widget, small and medium. To get it, open the app at least once, then right-click the desktop, choose "Edit Widgets" and find "TenFingers".

"Edit Widget" lets you set:

- "Streak", "Daily goal", "Achievements": switches for the pages to show (all on by default). With one on, the widget shows only that page; with several, the pages take turns;
- "Change every, min": how often the pages change by themselves, 5 to 60 (15 by default);
- "Change on tap": a click on the widget turns to the next page and opens the app at that page's section (except the invitation line in the medium widget). The tap counter is shared by all TenFingers widgets;
- "Lesson invitation": a "Continue: <lesson>" line at the bottom of the widget;
- "Hide adult humor 18+": off follows the app, on always hides the humorous achievements.

Clicking the widget opens the app: the streak and the daily goal lead to Home, achievements to Achievements, and the prompt line to the course. The widget takes its data from a file that the app refreshes after practice, at launch and at the start of a new day. If the app has not been opened for a long time, the widget says so.

## Build from source

Requirements: macOS 15 or later, Xcode 26 or later.

```bash
git clone https://github.com/Rusl3n/tenfingers.git
cd tenfingers
./scripts/build-app.sh
```

The script builds a release version, signs it ad hoc and copies it to `/Applications`. The app is installed as `/Applications/TenFingers.app`; Finder and the Dock show it as "Десять пальцев" on a Russian system and "TenFingers" on an English one. The interface language can be changed in Settings → General. The old "Десять пальцев.app" bundle is removed during installation and your progress stays in place. Before installing, the script backs up your progress (the latest copies are kept) and refuses to install a build if the database was written by a newer version of the app. A pinned copy that the rotation never touches is made by `./scripts/pin-backup.sh <label>`. What changed from version to version is in [`CHANGELOG.md`](CHANGELOG.md) (in Russian).

## Development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

The Swift package has four modules:

- `TypingCore` — pure logic with no AppKit or SwiftUI: keyboard geometry, finger map, typing engine, course, text generation, sound synthesis. Covered by tests.
- `TenFingers` — the app: SwiftUI interface, layout detection via TIS, SwiftData storage, sounds, themes, update check and install.
- `WidgetSnapshot` — the model of the `widget.json` file and the widget timeline logic, Foundation only: both the app and the widget read it.
- `TenFingersWidget` — the WidgetKit extension; `scripts/make-bundle.sh` puts it into the app bundle and signs it.

The README images are rendered by tests that are skipped by default; run them one at a time (the `docs/images` folder):

```bash
RENDER_DOCS=1 swift test --filter renderReadmeImages        # keyboard, exercise text, home, heat map
RENDER_DOCS=1 swift test --filter renderCourseMapImage      # course map
RENDER_DOCS=1 swift test --filter renderAchievementsImage   # Achievements screen
RENDER_DOCS=1 swift test --filter renderShareCardImages     # Share cards
RENDER_DOCS=1 swift test --filter renderWidgetImage         # widget
RENDER_DOCS=1 swift test --filter renderSettingsImage       # settings
```

Versions and history: [`CHANGELOG.md`](CHANGELOG.md), development rules: [`CONTRIBUTING.md`](CONTRIBUTING.md) (both in Russian). The app version is shown in About and at the bottom of Settings.

Design and work plans live in [`docs/superpowers`](docs/superpowers): the [specification](docs/superpowers/specs/2026-10-23-typing-tutor-design.md) and the [plans](docs/superpowers/plans). They are written in Russian.

## Licenses

- Code — [MIT](LICENSE). The MIT license covers the code, not the word lists.
- Word lists `Sources/TypingCore/Resources/words-*.txt` — filtered adaptations of the frequency lists from [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (OpenSubtitles 2018), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See also [`CREDITS.md`](Sources/TypingCore/Resources/CREDITS.md).
- Exercise sentences `Sources/TypingCore/Resources/sentences-*.json` — selected and normalized sentences from [Tatoeba](https://tatoeba.org), licensed [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/); each sentence's number is stored in its `source` field.
- The icon is drawn in code: [`scripts/make-icon.swift`](scripts/make-icon.swift).
