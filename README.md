<p align="center">
  <h1 align="center">Hermes Agent Bar</h1>
  <p align="center">A tiny macOS menu bar app for running Hermes Agent without leaving your desktop.</p>
</p>

<p align="center">
  <a href="https://github.com/cerealskill/hermes-agent-bar"><img alt="GitHub repo" src="https://img.shields.io/badge/github-hermes--agent--bar-181717?logo=github"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-yellow">
</p>

Hermes Agent Bar, packaged as `HermesBar`, puts Hermes Agent in your macOS menu bar. Open a focused chat popover, send prompts, switch projects, run diagnostics, and jump back into Terminal when you need the full CLI.

Built for people who live in agents all day and want the fast path: click, ask, ship.

## Highlights

- Native macOS menu bar app built with Swift and AppKit.
- Left click opens the chat instantly.
- Right click opens a clean action menu.
- Terminal-style chat UI with a Hermes-like status bar.
- Project picker, clipboard support, file attach flow, output copy/save, and local slash commands.
- Runs `hermes doctor` from the app for quick diagnostics.
- Opens normal Hermes sessions, continued sessions, and session browser in Terminal.
- Remembers your selected project, font size, and output panel height.

## Preview

```text
⚚ Hermes
┌──────────────────────────────────────────────┐
│ ⚕ gpt-5.5 │ session 1 │ turn 1 │ Ready       │
├──────────────────────────────────────────────┤
│ Ask Hermes anything from a native macOS pane. │
├──────────────────────────────────────────────┤
│ > Build the app, run checks, summarize diff   │
└──────────────────────────────────────────────┘
```

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools.
- Hermes Agent CLI installed.
- `hermes` available in one of these locations:
  - `~/.local/bin/hermes`
  - `/opt/homebrew/bin/hermes`
  - `/usr/local/bin/hermes`
  - your current `PATH`

Check your setup:

```bash
command -v hermes
hermes doctor
```

Install Apple's command line tools if Swift is missing:

```bash
xcode-select --install
```

## Install

Clone the repo:

```bash
git clone https://github.com/cerealskill/hermes-agent-bar.git
cd hermes-agent-bar
```

Build the app bundle:

```bash
./scripts/build_app.sh
```

Try it locally:

```bash
open build/HermesBar.app
```

Install it into `/Applications`:

```bash
./scripts/install_app.sh
```

Launch it:

```bash
open /Applications/HermesBar.app
```

## Update

```bash
git pull --ff-only
./scripts/install_app.sh
open /Applications/HermesBar.app
```

## Usage

Left click `⚚ Hermes` in the menu bar to open chat.

Right click `⚚ Hermes` for actions:

- Open chat
- Show slash commands
- Cancel current run
- Copy, save, or clear output
- Paste from clipboard
- Attach a file
- Choose a project folder
- Run `hermes doctor`
- Open Hermes in Terminal
- Continue a session in Terminal
- Browse sessions in Terminal
- Open Hermes config
- Adjust text size
- Quit

Keyboard shortcuts inside chat:

```text
Enter        Send prompt
Shift+Enter  New line
```

Local wrapper commands:

```text
/copy      Copy output
/save      Save output
/paste     Paste clipboard into input
/doctor    Run hermes doctor
/project   Choose a project folder
/clear     Clear local output
/new       Start a new local session view
/reset     Reset local session state
```

## Build from source

The simple Swift build:

```bash
swift build -c release
```

The app bundle build:

```bash
./scripts/build_app.sh
```

The bundle script does four things:

1. Builds `HermesBar` in release mode.
2. Creates `build/HermesBar.app`.
3. Generates and validates `Info.plist`.
4. Signs the app locally with an ad hoc signature.

Validate the bundle manually:

```bash
plutil -lint build/HermesBar.app/Contents/Info.plist
codesign --verify --deep --strict build/HermesBar.app
```

## Project layout

```text
Package.swift
Sources/HermesBar/main.swift
scripts/build_app.sh
scripts/install_app.sh
README.md
LICENSE
```

## Troubleshooting

### The app cannot find Hermes

Apps launched from Finder do not always inherit your shell environment. Hermes Agent Bar searches common install paths, then falls back to `PATH`.

Check where Hermes is installed:

```bash
command -v hermes
hermes doctor
```

If your binary lives somewhere else, update `hermesCandidates` in:

```text
Sources/HermesBar/main.swift
```

### macOS blocks the app

The app is signed locally with an ad hoc signature. If Gatekeeper warns you, open:

```text
System Settings -> Privacy & Security
```

Then allow the app to open.

### Clean reinstall

```bash
osascript -e 'tell application "HermesBar" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/HermesBar.app
./scripts/install_app.sh
open /Applications/HermesBar.app
```

## Development

Run a release build:

```bash
swift build -c release
```

Build the `.app` bundle:

```bash
./scripts/build_app.sh
```

Install locally:

```bash
./scripts/install_app.sh
```

## License

MIT
