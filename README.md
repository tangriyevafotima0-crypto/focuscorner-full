# FocusCorner — Desktop App

A quiet desktop overlay for deep work: pinned focus rules, optional notes,
and a permanent history log. This is the Electron desktop version.

## Requirements
- Node.js 20 or newer (https://nodejs.org) — includes npm

## Run it (all systems)
```bash
cd focuscorner-desktop
npm install
npm start
```

## Develop with hot reload
```bash
npm run dev
```

## Build an installer
```bash
npm run dist:mac      # macOS  -> release/*.dmg
npm run dist:win      # Windows -> release/*.exe (installer + portable)
npm run dist:linux    # Linux  -> release/*.AppImage and *.deb
```
Build each installer on its own operating system (a .dmg needs a Mac, an .exe needs Windows).

### Install the result
- **macOS:** open `release/FocusCorner-1.0.0.dmg`, drag FocusCorner to Applications.
  If macOS blocks it (unsigned app): right-click the app → Open.
- **Windows:** run `release/FocusCorner Setup 1.0.0.exe`.
- **Linux (AppImage):** `chmod +x release/FocusCorner-1.0.0.AppImage && ./release/FocusCorner-1.0.0.AppImage`
- **Linux (Debian/Ubuntu):** `sudo apt install ./release/focuscorner_1.0.0_amd64.deb`

## Desktop features
- Global shortcut **Ctrl/Cmd + Shift + F** shows the window and toggles notes, even when another app is focused
- **View → Always on Top** (Ctrl/Cmd + Shift + T)
- **Launch at login** in Settings now really registers the app with your OS (installed app only)
- Rules, tasks and history are mirrored to `~/.focus_corner/rules.json`, `tasks.json`, `history.md`
- Works fully offline (fonts and wallpaper are bundled)
- Single instance: opening it twice focuses the existing window

## Project layout
```
electron/main.cjs      window, menu, global shortcut, login item, file export
electron/preload.cjs   safe bridge between the app and Electron
src/                   React UI (unchanged design from the original)
build/icon.png         app icon
```
