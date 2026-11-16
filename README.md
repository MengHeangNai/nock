# GlassDock

A glass-style replacement Dock for macOS 14 or later, with widgets for Now Playing, Battery and Clock. On macOS 26 Tahoe it uses Liquid Glass, and on earlier versions it uses a frosted material.

## Build and run

```bash
./scripts/build-app.sh
open build/GlassDock.app
```

Run the tests with `swift test`.

To keep it, move `build/GlassDock.app` to `/Applications`. Then turn on **Open at login** in Settings.

## Using it

- **Click an app** to open it or switch to it. The icon darkens while pressed and bounces until the app finishes launching. **Option-click** switches and hides the other apps; **Command-click** shows the app in Finder.
- **Right-click, Control-click or press and hold** an app for the same menu as the macOS Dock: its open windows, **Options** (Keep in Dock, Show in Finder), Show All Windows, Hide and Quit. Hold **Option** while the menu is open to get Hide Others and Force Quit.
- The menu shows **open windows** for running apps (needs Accessibility: **Settings → Dock → Show app windows in Dock menus**) and **recent documents** for apps that aren't running (needs Full Disk Access: **Settings → Dock → Show recent documents in Dock menus**). Because the build is signed ad hoc, macOS may ask again after each rebuild.
- **The menu bar icon** (dock symbol) opens **Settings** and **Quit**. GlassDock has no Dock icon of its own.
- **Several displays:** the Dock appears on every connected display, each with its own auto-hide, magnification and click-through, and all share the same apps and settings. To keep it on the main display (the one with the menu bar) only, choose **Settings → Dock → Show Dock on → Main display only**. Plugging in or unplugging a display, changing its resolution or arrangement, or waking the Mac adds, removes and moves the Docks by itself.
- **Settings:** icon size, magnification and its amount, which displays show the Dock, auto-hide, which widgets to show, whether to show running apps, adding, ordering and removing apps, hiding the macOS Dock, the Island on displays without a notch, hiding the Island in full-screen apps, the Island's lyrics, system HUD and system event notifications, and open at login.
- **Now Playing** follows Music and Spotify, and also any other app that reports what it plays to macOS, such as YouTube or SoundCloud in Chrome, Safari, Arc or Firefox. The first time you use the playback buttons for Music or Spotify, macOS asks permission for GlassDock to control that app. Other apps need no permission. Music or Spotify playing always wins over another app.
- On first launch, GlassDock adds the apps from your current macOS Dock.

## Island (notch panel)

- **Hover over the notch** to open the panel. On Macs without a notch, and on every external display, hover over the pill at the top center of the screen. If the pill gets in the way, choose **Settings → Island → Island on displays without a notch**: **Show on hover** draws nothing there until you hover over that spot (the volume HUD and notifications still appear), and **Off** removes the Island from those displays. Displays with a notch always keep theirs. Turn on **Settings → Island → Hide in full-screen apps** (off by default) to hide the Island on any display showing a full-screen app: no pill, live activities, hover or notifications there, and an open Island closes. The volume and brightness HUD still shows, and other displays keep their Island. It comes back when you leave full screen. Every connected display has its own Island, and only one is open at a time: opening one closes the other. Move the mouse away or click elsewhere to close it.
- **Tabs, left of the notch:** Home, Now Playing, Lyrics, Timer, Battery, Up Next, Shelf, Clipboard and Notes.
- **Tabs, right of the notch:** Terminal, AI Usage, Color Picker, Keep Awake, Downloads, Devices and Stats. Hide any of them under **Settings → Island Tabs**.
- **Permissions:** Calendar is requested when you click **Connect Calendar**, and the Downloads folder when you open **Downloads**.
- **AI Usage** shows Codex's 5-hour and weekly limits, read from its local logs. For Claude Code it shows token counts from local logs. If you turn on **Show plan limits**, it also shows Claude's own limits: GlassDock reads Claude Code's sign-in from the Keychain (macOS asks first) and sends it only to Anthropic.
- **Notes** shows the notes from the Notes app on your Mac. Plain-text notes save back to Notes as you type. Notes with formatting or attachments are read-only in GlassDock, so nothing gets lost; use the open button to edit them in Notes. Pins are kept only in GlassDock. Deleting a note moves it to Recently Deleted in Notes.
- **Shelf actions** work on the selected files, or on all files if none are selected: Quick Look, Open, Show in Finder, Share, AirDrop, convert images (PNG, JPEG, HEIC), combine into a PDF, compress to .zip, and copy text from images and PDFs (text recognition runs on your Mac). New files are saved to Downloads.
- **Live activities** beside the notch: music playing (the bars move with the sound your Mac plays; macOS asks once for permission to record system audio, which GlassDock only measures and never stores or sends), a timer counting down, "Done" when the timer ends, the charge level when you plug in, and a **volume, brightness and keyboard backlight HUD**. The HUD replaces the macOS overlay: the Island grows below the notch (a pill on Macs without a notch) with a large icon, a label, a level bar and the percentage, for about 1.5 seconds, longer while you keep pressing. When the Island is open, the HUD floats over its content instead. The HUD covers the other live activities while it shows, then they return.
With several displays, live activities show beside the notch or pill on every display.
- **System event notifications:** a short HUD in the same place as the volume HUD (the Island drops below the notch or pill, or floats over the open Island) for **Bluetooth devices** connecting and disconnecting (device name, with an icon for AirPods, headphones, speaker, keyboard, mouse, trackpad or game controller), **Wi-Fi** connecting, disconnecting, turning on and turning off, **low battery** at 20% (orange) and 10% (red) while on battery, once each per discharge, and **Fully charged** once per charge. Each shows for about 2.6 seconds (3.2 for battery warnings) with a spring drop, a bouncing icon, and a pulse on warnings. Warnings go first, a few more wait in line, and the volume and brightness HUD always comes first: a notification waits and then starts again. Only real changes show: nothing appears for the state at launch, and events right after waking the Mac are skipped. With **Reduce Motion** on, it only fades. Each notice is announced to VoiceOver. It never shows the Wi-Fi network name (macOS keeps it behind Location access) or a device's battery level, and it never reads other apps' notifications. Turn it on or off, and Bluetooth, Wi-Fi and battery separately, under **Settings → Island → Show system event notifications**. macOS may ask once to allow Bluetooth.
- **Volume and brightness keys:** with **Settings → Island → Replace system volume & brightness HUD** on (the default), GlassDock takes over the volume, mute, display brightness and keyboard backlight keys and makes the change itself, so macOS shows no overlay. Each press moves 1/16 of the range; **Shift-Option** moves 1/64. **Option** alone (or Command or Control) is left to macOS, so Option plus a volume key still opens Sound settings. Brightness changes the display under the mouse when it has built-in brightness control; on any other display (most external monitors) it changes the built-in screen instead, as the macOS keys do, and GlassDock shows the HUD for it. Keys that GlassDock cannot handle, such as brightness with the built-in screen unavailable (lid closed) or backlight on a Mac without one, go to macOS untouched. GlassDock watches the keys at the HID level, before the session event taps, so macOS does not see the keys it takes. Brightness and backlight use private macOS frameworks (DisplayServices and CoreBrightness) that Apple may change. GlassDock makes no volume feedback click.
- **Permission for the keys:** the Island must be on, and GlassDock needs **Accessibility** access (Privacy & Security → Accessibility; the Settings row has a button for it) to take over the keys. If it can't get it, or macOS also asks for **Input Monitoring**, GlassDock takes over nothing: the macOS overlay stays and the Island only shows volume changes. While Accessibility is missing, GlassDock checks every 2 seconds and takes over the keys as soon as you allow it, without turning the setting off and on or restarting. Turning the setting off, turning the Island off, or quitting GlassDock gives the keys back to macOS. Because the build is signed ad hoc, macOS may ask again after each rebuild.
- **Shelf:** drag files onto the notch to keep them there. Drag them back out to use them anywhere, or double-click to open one. The Shelf stores links to the files; it doesn't move or copy them.
- **Clipboard:** keeps your last 100 text copies in memory, and saves only the ones you pin. It skips copies that password managers mark as private. Click an item to copy it again.
- **Clipboard transforms:** click the wand icon on an item, or right-click it and choose **Transform**, to put a changed copy on the clipboard. The copy is added to the history like any other copy. The menu lists only what applies to that item: **Format JSON** and **Minify JSON** (when the text is a JSON object or array; text that looks like JSON but doesn't parse shows "Not valid JSON"), **Remove tracking parameters** (for http and https links; removes `utm_*`, `fbclid`, `gclid`, `mc_eid`, `igshid`, `ref` and similar, and keeps other parameters), **Trim whitespace**, **Collapse blank lines**, **UPPERCASE**, **lowercase**, **Title Case**, **Base64 encode and decode**, and **URL encode and decode**. Images are not kept in the clipboard history, so there is no text recognition for clipboard images yet.
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
| `DockWindow.swift` | One full-width transparent panel at Dock level per display, kept in step with the connected displays; each polls the cursor for magnification, auto-hide and click-through |
| `Displays.swift` | Display IDs for screens and which displays get a Dock (**Show Dock on**); tested in `Tests/GlassDockTests/` |
| `DockView.swift` | The dock bar, magnification math, app and Trash icons |
| `DockItemInteraction.swift` | Clicks, press-and-hold and the right-click menu for Dock items, the app's window list (Accessibility), the name label shape |
| `Widgets.swift` | Now Playing, Battery and Clock widgets |
| `DockModel.swift` | Kept and running apps from NSWorkspace, plus app actions |
| `NowPlaying.swift` | Now Playing: Music and Spotify (distributed notifications and AppleScript), other apps and browsers (MediaRemote) |
| `GlassDockMediaRemote/` | Helper library that reads and controls MediaRemote. macOS only allows Apple-signed programs to use it, so GlassDock loads the library inside `/usr/bin/perl`. The build scripts put it next to the app's executable |
| `AudioLevels.swift` | Reads the level of the sound being played (Core Audio system tap) and splits it into four bands for the music bars in the Island |
| `SystemHUD.swift` | The HUD's pure rules: media key decoding, step sizes, modifier behaviour, symbol, label and percentage; tested in `Tests/GlassDockTests/` |
| `SystemHUDController.swift` | Turns the media keys into changes and publishes what the Island HUD shows; installs and removes the key tap as Accessibility access, the setting and the Island module change |
| `SystemNotifications.swift` | The notifications' pure rules: the notification model, the queue (priority, duplicates, a short line, the HUD going first), battery thresholds, Wi-Fi changes, Bluetooth connection tracking and device icons; tested in `Tests/GlassDockTests/` |
| `SystemNotificationController.swift` | Starts and stops the Bluetooth, Wi-Fi and battery watchers from the settings, feeds the queue, times each notification and announces it to VoiceOver |
| `MediaKeyTap.swift` | The active event tap on the volume, brightness and backlight keys |
| `SystemVolume.swift` | Output volume and mute: Core Audio reads, writes and property listeners on the default output device |
| `Brightness.swift` | Built-in display brightness (private DisplayServices) and keyboard backlight (private CoreBrightness), loaded at run time |
| `Monitors.swift` | Battery (IOKit), Bluetooth connections (IOBluetooth), Wi-Fi state (CoreWLAN), hiding the system Dock |
| `DockSettings.swift` | Preferences saved in UserDefaults |
| `Services.swift` | Shared Clipboard, Shelf, Timer and Notes data |
| `ClipboardTransforms.swift` | The Clipboard's text transforms (JSON, tracking parameters, whitespace, case, Base64, URL encoding) as pure functions; tested in `Tests/GlassDockTests/` |
| `Island/IslandWindow.swift` | One notch-level panel per display, kept in step with the connected displays; opens on hover, accepts file drops, closes on an outside click, and keeps one island open at a time; hides each display's island while it shows a full-screen app (**Hide in full-screen apps**), checked when the Space or the active app changes |
| `Island/IslandSpace.swift` | Puts an island panel in its own top-level WindowServer space (private SkyLight API) so it stays fixed during Space switches and full-screen slides; each display's panel gets its own space; also reads which displays show a full-screen Space, tested in `Tests/GlassDockTests/` |
| `Island/IslandState.swift` | Per display: notch (or pill) size and position, whether it is open, the tab, which live activity to show; whether displays without a notch show the Island (**Island on displays without a notch**), tested in `Tests/GlassDockTests/` |
| `Island/IslandView.swift`, `Island/IslandTabs.swift` | The island and its tabs |
| `Island/HUDView.swift` | The volume, brightness and keyboard backlight HUD |
| `Island/NotificationView.swift` | The system event notification: icon badge, title and subtitle, with the symbol effects |
