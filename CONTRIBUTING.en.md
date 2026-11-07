# Contributing

[Русская версия](CONTRIBUTING.md)

Thanks for wanting to help TenFingers! The app is a native typing tutor for macOS (Swift 6.2, SwiftUI, SwiftData).

## Bugs and ideas

- Found a bug? Open an [issue](https://github.com/Rusl3n/tenfingers/issues/new/choose) with the "Bug" template: app version (shown in About), macOS version, keyboard layout, what you did and what happened.
- Use the "Idea" template for suggestions. English or Russian are both fine.

## Build and test

Requirements: macOS 15 or later, Xcode 26 or later.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
./scripts/build-app.sh
```

`build-app.sh` builds a release version, signs it ad hoc, backs up your progress (`~/Library/Application Support/TenFingers.backups`) and installs the app as `/Applications/TenFingers.app`. To build the bundle without installing anything, run `./scripts/make-bundle.sh [--output DIR]`.

## Pull requests

- Work on a separate branch; changes reach `main` only through a pull request.
- `swift test` must pass and the build must have no warnings; CI checks the same (`.github/workflows/tests.yml`, compiler warnings are errors).
- Every change comes with tests: write the test and see it fail, then write the code and see it pass.
- Anything users will notice goes into `CHANGELOG.md` under `[Unreleased]` (Added, Changed, Fixed). The changelog is written in Russian.

## Code

- Pure logic lives in `TypingCore` (no AppKit, SwiftUI, Carbon or AVFoundation) and is covered by Swift Testing tests. Tests that call Carbon TIS are marked `@MainActor`.
- New UI strings are added in both languages: `Localization/{ru,en}.lproj/Localizable.strings` (for the core, `Sources/TypingCore/Resources/{ru,en}.lproj`). A guard test checks the translations. Source strings are in Russian.
- No emoji in the UI, only SF Symbols.
- The repository (code, texts, docs) does not mention other products by name; use a neutral description such as "an adaptive trainer that unlocks letters as you master them". Data sources and licenses are the exception. CI checks this with `./scripts/check-names.sh`.

## Keeping user data safe

Users' progress must never be lost.

- The database schema only changes additively: new models, and new fields only with default values. No renaming or removing fields.
- When the schema changes, the schema generation is bumped (`SchemaGeneration.swift`); the app refuses to open a database from a newer generation.
- Do not experiment on your own `~/Library/Application Support/TenFingers` folder; work on a copy.

## License

By contributing, you agree that your changes are distributed under the [MIT License](LICENSE).
