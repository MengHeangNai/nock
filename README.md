# GlassDock

A glass-style replacement Dock for macOS 14 or later, with widgets for Now Playing, Battery and Clock. On macOS 26 Tahoe it uses Liquid Glass, and on earlier versions it uses a frosted material.

## Build and run

```bash
./scripts/build-app.sh
open build/GlassDock.app
```

To keep it, move `build/GlassDock.app` to `/Applications`. Then turn on **Open at login** in Settings.

## Using it

- **Click an app** to open it or switch to it. The icon darkens while pressed and bounces until the app finishes launching. **Option-click** switches and hides the other apps; **Command-click** shows the app in Finder.
- **Right-click, Control-click or press and hold** an app for the same menu as the macOS Dock: its open windows, **Options** (Keep in Dock, Show in Finder), Show All Windows, Hide and Quit. Hold **Option** while the menu is open to get Hide Others and Force Quit.
- The menu shows **open windows** for running apps (needs Accessibility: **Settings → Dock → Show app windows in Dock menus**) and **recent documents** for apps that aren't running (needs Full Disk Access: **Settings → Dock → Show recent documents in Dock menus**). Because the build is signed ad hoc, macOS may ask again after each rebuild.
- **The menu bar icon** (dock symbol) opens **Settings** and **Quit**. GlassDock has no Dock icon of its own.
- **Settings:** icon size, magnification and its amount, auto-hide, which widgets to show, whether to show running apps, adding, ordering and removing apps, hiding the macOS Dock, and open at login.
- **Now Playing** follows Music and Spotify, and also any other app that reports what it plays to macOS, such as YouTube or SoundCloud in Chrome, Safari, Arc or Firefox. The first time you use the playback buttons for Music or Spotify, macOS asks permission for GlassDock to control that app. Other apps need no permission. Music or Spotify playing always wins over another app.
- On first launch, GlassDock adds the apps from your current macOS Dock.

## Island (notch panel)

- **Hover over the notch** to open the panel. On Macs without a notch, hover over the pill at the top center of the screen. Move the mouse away or click elsewhere to close it.
- **Tabs, left of the notch:** Home, Now Playing, Lyrics, Timer, Battery, Up Next, Shelf, Clipboard and Notes.
- **Tabs, right of the notch:** Terminal, AI Usage, Color Picker, Keep Awake, Downloads, Devices and Stats. Hide any of them under **Settings → Island Tabs**.
- **Permissions:** Calendar is requested when you click **Connect Calendar**, and the Downloads folder when you open **Downloads**.
- **AI Usage** shows Codex's 5-hour and weekly limits, read from its local logs. For Claude Code it shows token counts from local logs. If you turn on **Show plan limits**, it also shows Claude's own limits: GlassDock reads Claude Code's sign-in from the Keychain (macOS asks first) and sends it only to Anthropic.
- **Notes** shows the notes from the Notes app on your Mac. Plain-text notes save back to Notes as you type. Notes with formatting or attachments are read-only in GlassDock, so nothing gets lost; use the open button to edit them in Notes. Pins are kept only in GlassDock. Deleting a note moves it to Recently Deleted in Notes.
- **Shelf actions** work on the selected files, or on all files if none are selected: Quick Look, Open, Show in Finder, Share, AirDrop, convert images (PNG, JPEG, HEIC), combine into a PDF, compress to .zip, and copy text from images and PDFs (text recognition runs on your Mac). New files are saved to Downloads.
- **Live activities** beside the notch: music playing (the bars move with the sound your Mac plays; macOS asks once for permission to record system audio, which GlassDock only measures and never stores or sends), a timer counting down, "Done" when the timer ends, and the charge level when you plug in.
- **Shelf:** drag files onto the notch to keep them there. Drag them back out to use them anywhere, or double-click to open one. The Shelf stores links to the files; it doesn't move or copy them.
- **Clipboard:** keeps your last 100 text copies in memory, and saves only the ones you pin. It skips copies that password managers mark as private. Click an item to copy it again.
- Turn Dock and Island on or off separately under **Settings → Modules**.

## Hiding the macOS Dock

The setting **Hide the macOS Dock while GlassDock is running** turns on auto-hide for the system Dock and sets a very long reveal delay. When you quit GlassDock, it restores your original values. If GlassDock crashes or is force-quit, it restores them on the next launch. To restore them by hand:

```bash
defaults delete com.apple.dock autohide-delay; killall Dock
```

## Code layout

| File | What it does |
| --- | --- |
| `GlassDockApp.swift` | App entry, menu bar item, Settings window |
| `DockWindow.swift` | Full-width transparent panel at Dock level; polls the cursor for magnification, auto-hide and click-through |
| `DockView.swift` | The dock bar, magnification math, app and Trash icons |
| `DockItemInteraction.swift` | Clicks, press-and-hold and the right-click menu for Dock items, the app's window list (Accessibility), the name label shape |
| `Widgets.swift` | Now Playing, Battery and Clock widgets |
| `DockModel.swift` | Kept and running apps from NSWorkspace, plus app actions |
| `NowPlaying.swift` | Now Playing: Music and Spotify (distributed notifications and AppleScript), other apps and browsers (MediaRemote) |
| `GlassDockMediaRemote/` | Helper library that reads and controls MediaRemote. macOS only allows Apple-signed programs to use it, so GlassDock loads the library inside `/usr/bin/perl`. The build scripts put it next to the app's executable |
| `AudioLevels.swift` | Reads the level of the sound being played (Core Audio system tap) and splits it into four bands for the music bars in the Island |
| `Monitors.swift` | Battery (IOKit), hiding the system Dock |
| `DockSettings.swift` | Preferences saved in UserDefaults |
| `Services.swift` | Shared Clipboard, Shelf, Timer and Notes data |
| `Island/IslandWindow.swift` | Notch-level panel; opens on hover, accepts file drops, closes on an outside click |
| `Island/IslandSpace.swift` | Puts the island panel in its own top-level WindowServer space (private SkyLight API) so it stays fixed during Space switches and full-screen slides |
| `Island/IslandState.swift` | Notch size and position, tabs, which live activity to show |
| `Island/IslandView.swift`, `Island/IslandTabs.swift` | The island and its tabs |
