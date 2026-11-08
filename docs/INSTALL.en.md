# Installation and setup

[Русская версия](INSTALL.md) · [← Back to README](../README.en.md)

- [Requirements](#requirements)
- [Installing the ready-made app](#installing-the-ready-made-app)
- [First launch: the macOS warning](#first-launch-the-macos-warning)
- [First-time setup](#first-time-setup)
- [Updates](#updates)
- [Where your progress lives and how to move it](#where-your-progress-lives-and-how-to-move-it)
- [Building from source](#building-from-source)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)

## Requirements

- macOS 15 Sequoia or later.
- A Mac with Apple silicon (M1 or later). The ready-made build targets Apple silicon; on an Intel Mac you can try [building the app yourself](#building-from-source), but this hasn't been tested.
- About 30 MB of disk space. The internet is only needed to check for updates; you can practice offline.

## Installing the ready-made app

1. Open the [latest release page](https://github.com/Rusl3n/tenfingers/releases/latest) and download `TenFingers-<version>.dmg` (under **Assets** at the bottom).
2. Double-click the downloaded `.dmg`.
3. Drag the TenFingers icon onto the Applications folder in the same window.
4. Close the window and eject the "TenFingers" disk (on the desktop or in the Finder sidebar → ⏏).
5. Launch the app from Applications or Launchpad. On first launch macOS shows a warning; that's expected, see the next section.

> **Verifying the download (optional).** The release also contains `SHA256SUMS`. In Terminal run `shasum -a 256 ~/Downloads/TenFingers-*.dmg`; the output must match the line in `SHA256SUMS`.

## First launch: the macOS warning

**Why it appears.** Apple lets apps open without questions only after a paid check (notarization) through the Apple Developer Program. TenFingers is a free open-source project and isn't notarized. Every release is built automatically on GitHub from the public code in this repository; the app works offline (except for update checks) and collects no data.

macOS shows a message like "Apple could not verify "TenFingers" is free of malware". Allow it once and the app opens normally from then on.

### Option 1: System Settings

1. In the warning, click **Done** (not "Move to Trash").
2. Open **Apple menu → System Settings → Privacy & Security**.
3. Scroll down to **Security**. You'll see ""TenFingers" was blocked…" with an **Open Anyway** button; click it.
4. Confirm with your Mac password or Touch ID.
5. In the next dialog, click **Open**.

The Open Anyway button appears for about an hour after the blocked launch. If you don't see it, try launching the app again and go straight back to Settings.

> On macOS 15 and later the old "right-click → Open" trick no longer works; use option 1 or 2.

### Option 2: one Terminal command

Open **Terminal** (Applications → Utilities → Terminal), paste the command and press Return:

```bash
xattr -dr com.apple.quarantine /Applications/TenFingers.app
```

It removes the "downloaded from the internet" flag, after which the app opens without the warning. No output means it worked.

## First-time setup

1. **Introduction.** On first launch the app asks for your name (used on Share cards; you can skip it), the interface language and the course language. You can run it again under Settings → Profile → Run the introduction again.
2. **Keyboard layouts.** The app types in the layouts enabled in macOS and draws the on-screen keyboard from your actual layout. The Russian course needs a Russian layout ("Russian" or "Russian – PC"); the English course needs "ABC" or "U.S.". To add one: **System Settings → Keyboard → Input Sources → Edit… → +**. If the wrong layout is active, the app tells you to switch.
3. **Speed test.** After the introduction the app offers a short speed test as your starting point. You can skip it and take it later under Training.
4. **Daily goal.** 10 minutes of active typing per day by default. Change it under Settings → Learning → Daily goal.
5. **Reminders** (optional). Settings → Reminders: once a day, three times a day or every N hours. macOS will ask for notification permission; click Allow.
6. **Appearance.** Settings → General: light or dark theme, palette, interface scale. On-screen keyboard size: Settings → Keyboard.
7. **Widget** (optional). Right-click the desktop → **Edit Widgets** → find TenFingers. Widget settings choose the pages (streak, daily goal, achievements) and how often they rotate.
8. **Several learners on one Mac.** Each gets a profile: the profile row at the bottom of the sidebar or the Profile menu.

The interface is available in English and Russian (Settings → General).

## Updates

Once a day the app checks for a new version (turn it off under Settings → General, where you'll also find Check now). When one is out, a banner appears at the top of Home: What's new, Install or Skip this version.

On install the app downloads the new version, verifies its size, checksum and signature, replaces itself and relaunches. Before replacing, it makes two verified copies, of the database and the progress archive, in `~/Library/Application Support/TenFingers.backups/before-update-*` (the last three are kept). If the new version can't open the database, the error screen offers Restore the previous version.

You can also update manually: download the new `.dmg` and drag the app into Applications, replacing the old one. Your progress stays.

## Where your progress lives and how to move it

- Progress, history, achievements and settings live in `~/Library/Application Support/TenFingers` (the Library folder is hidden: in Finder use **Go → Go to Folder…** and paste the path).
- **Moving to another Mac:** Settings → Data → Save Progress to File…, then on the other Mac Load Progress from File…. Before loading, your current progress is backed up automatically.

## Building from source

If you'd rather not install the ready-made build, or want to change something, you can build the app yourself. An app built on your own Mac opens without the macOS warning.

### 1. Install Xcode

1. Install **Xcode 26** or later from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835) (about 10 GB). It must be at `/Applications/Xcode.app`; the build script looks for it there.
2. Launch Xcode once: accept the license and wait for the components to install. Then you can quit it.
3. Check in Terminal:

   ```bash
   /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -version
   ```

   It should print `Xcode 26…`.

### 2. Get the source

```bash
git clone https://github.com/Rusl3n/tenfingers.git
cd tenfingers
```

If `git` isn't installed, macOS offers to install the command line tools; accept. You can also skip git: **Code → Download ZIP** on the repository page, unzip it and open its folder in Terminal (the build number will be 0, otherwise it works the same).

### 3. Build and install

```bash
./scripts/build-app.sh
```

The first build takes a few minutes. The script:

- builds a release version and signs it locally (ad hoc);
- backs up your progress to `~/Library/Application Support/TenFingers.backups`;
- quits the running app and installs the new one as `/Applications/TenFingers.app`;
- refuses to install if your progress was written by a newer app version (so you don't lose it).

Done: launch TenFingers from Applications. To update later, run `git pull` and `./scripts/build-app.sh` again.

### For development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test                       # tests
./scripts/make-bundle.sh         # only build TenFingers.app into build/, install nothing
./scripts/pin-backup.sh <label>  # a pinned progress backup that rotation never deletes
```

Project layout and rules: [CONTRIBUTING.en.md](../CONTRIBUTING.en.md).

## Uninstalling

1. Quit the app and drag `/Applications/TenFingers.app` to the Trash.
2. To remove your progress too, delete `~/Library/Application Support/TenFingers` and `~/Library/Application Support/TenFingers.backups`.

## Troubleshooting

- **"The app is damaged and can't be opened."** Run the command from [option 2](#option-2-one-terminal-command).
- **The on-screen keyboard doesn't match your keyboard.** Make sure the right layout is active (see [first-time setup](#first-time-setup)); the app draws the one currently selected in macOS.
- **No reminders.** System Settings → Notifications → TenFingers: allow notifications.
- **`build-app.sh`: "xcrun: error" or "unable to find utility".** Xcode isn't at `/Applications/Xcode.app` or has never been launched; see step 1 of the build.
- **Anything else.** Open an [issue](https://github.com/Rusl3n/tenfingers/issues/new/choose) with the app version (shown in About) and your macOS version.
