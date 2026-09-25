# Caltrain Upcoming — iOS & macOS app

A small SwiftUI app that shows the next Caltrain departures between two
stations. One target builds for both iPhone and Mac from the same source.

## Open & run
1. Open `CaltrainUpcoming.xcodeproj` in Xcode 15 or later.
2. Pick a destination from the scheme menu — an iPhone simulator, your device,
   or **My Mac** — and press **Run** (⌘R).
3. On a device, set **Signing & Capabilities → Team** to your Apple ID first.

Deployment targets: iOS 16+ and macOS 13+.

From the command line:

```sh
xcodebuild -scheme CaltrainUpcoming -destination 'platform=macOS' build
xcodebuild -scheme CaltrainUpcoming -destination 'generic/platform=iOS Simulator' build
```

### One target, two platforms
`SDKROOT = auto` with `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`
means the same target compiles twice, once per SDK, rather than there being a
separate Mac target to keep in sync. Two consequences worth knowing:

- The handful of APIs that exist on only one platform live behind shims in
  `Platform.swift`, so the views themselves stay free of `#if os(...)`.
- Forcing dark takes three separate pieces, because each one covers different
  surfaces: `.preferredColorScheme(.dark)` in the scene handles SwiftUI's own
  views on both platforms, `UIUserInterfaceStyle = Dark` (build settings, iOS
  only) covers UIKit-provided UI such as alerts and the keyboard, and
  `forceDarkAppearance()` sets NSApplication's appearance so the Mac title bar
  and menu bar follow too. Dropping any one of them leaves that surface light.
- Card backgrounds are the one place the platforms can't share a semantic color.
  AppKit's `controlBackgroundColor` and `windowBackgroundColor` are both #1E1E1E
  under the dark appearance — they only differ in light mode — so the cards
  would vanish into the page. The Mac uses `underPageBackgroundColor` instead;
  see the comment in `Platform.swift`.
- The Mac build is sandboxed and so needs `com.apple.security.network.client`
  (in `CaltrainUpcoming-macOS.entitlements`) to fetch the schedule. Without it
  the download fails and the app quietly falls back to its bundled copy — the
  footer is the tell: it keeps saying "Using built-in schedule" after a refresh.
  iOS needs no equivalent; outgoing connections are allowed there by default.

## Sharing a Mac build

`build_dmg.sh` builds the Release app and wraps it in a disk image:

```sh
./build_dmg.sh
```

It writes `dist/Commute-<version>.dmg`, taking the version from
`AppInfo.version` in `Schedule.swift` — the same string the app shows in its
footer — so a DMG can't claim a version the app doesn't report. The image
contains the app, the customary `Applications` symlink to drag onto, and (when
the build isn't notarized) a Read Me explaining the first-launch step below.

### Gatekeeper, and why the first launch is awkward

macOS quarantines anything downloaded from the internet and refuses to open it
unless it carries an Apple-issued signature. What the recipient sees depends
entirely on how the app was signed:

| Signing | What the recipient gets |
| --- | --- |
| **Developer ID + notarized** | Double-click works. No warnings. |
| **ad-hoc** (the current default) | *"Apple cannot check it for malicious software."* They must right-click → **Open** once; macOS remembers the choice. |

The script picks the best identity installed and says which one it used. With
no **Developer ID Application** certificate on the machine it falls back to
ad-hoc — deliberately never to an *Apple Development* certificate, which embeds
a provisioning profile tied to specific registered Macs and so travels worse
than an ad-hoc signature.

To get the friction-free version you need a paid Apple Developer Program
membership and a Developer ID Application certificate. Once that's installed,
store a notarytool credential one time:

```sh
xcrun notarytool store-credentials caltrain-notary \
  --apple-id you@example.com --team-id A7SGPP54UA --password <app-specific-password>
```

then build with:

```sh
./build_dmg.sh --notarize
```

which signs, submits to Apple, waits for the verdict, and staples the ticket to
the DMG so it validates without a network round trip. The script refuses
`--notarize` outright if no Developer ID certificate is present, rather than
producing an image that only looks distributable.

## Features
- Default route **Blossom Hill → Sunnyvale**, fully changeable.
- **Weekday / Weekend** toggle. Opens on the mode matching today's date, then
  stays wherever you put it for the session. The Gilroy / South County branch
  (Blossom Hill, Capitol, Morgan Hill, San Martin, Gilroy) runs weekdays only,
  so weekend searches touching those stations say so explicitly instead of
  reporting an empty time window.
- Tap either station to pick a new one (searchable list); the ⇄ button swaps
  start and stop.
- **Depart "Now" or "At time"** — pick any departure time and the results (and
  every station's clock times) are computed from that moment instead of the
  device clock.
- "Look ahead" slider sets how far into the future to search: **0–90 minutes,
  default 45**.
- Each result expands to show **every station the train stops at**, with the
  boarding and alighting stops highlighted.
- Direct trains are shown when they exist. When there's no direct service
  (e.g. the Gilroy / South County line stations such as Blossom Hill, which
  terminate at San Jose Diridon), the app builds a **one-transfer trip at San
  Jose Diridon** so the route still returns results.
- Uses the device clock and refreshes the countdown every 30 seconds.
- **Dark only.** The app pins itself to the dark appearance and ignores the
  system light/dark setting, on both platforms.
- On the Mac the window opens at roughly phone proportions and stays resizable.
  Refresh is the toolbar button — pull-to-refresh is a touch gesture and has no
  Mac equivalent. The departure-time field accepts any minute as you type and
  snaps to the 15-minute step, where iOS offers a wheel that only stops on one.

## Updating the schedule

The timetable is baked in at build time, so refreshing it is a Mac-side job:
re-run the parser, then rebuild. Needs Python 3 (macOS ships it) and an internet
connection — the script uses only the standard library, nothing to install.

### 1. Has the feed actually changed?

What the bundled data was built from:

```sh
grep '"source"' CaltrainUpcoming/schedule.json
```

When the published feed was last rebuilt:

```sh
curl -sI https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip \
  | grep -i last-modified
```

If the feed is newer, regenerate. Re-running when nothing changed is harmless —
it rewrites the same content, and `git diff` will show nothing.

### 2. Regenerate

From the repo root (the folder holding `build_schedule.py`, alongside
`CaltrainUpcoming.xcodeproj`) — as with every command on this page:

```sh
python3 build_schedule.py      # downloads the feed, rewrites schedule.json in place
```

There's no separate file to copy over — it overwrites
`CaltrainUpcoming/schedule.json` directly. To parse a feed you already have:
`python3 build_schedule.py feed.zip`.

A normal run prints:

```
wrote .../CaltrainUpcoming/schedule.json
  source:   Caltrain GTFS static feed (Trillium), UTC: 10-Jun-2026 22:25
  stations: 30
  trains:   {'weekday': 112, 'weekend': 66}
```

Lines starting `note:` are expected, not errors — they report the holiday and
event-train omissions described under **Data** below.

The script refuses to write rather than produce bad data if the feed is missing
either calendar, or if San Jose Diridon is absent (the app's transfer point).

### 3. Check and rebuild

```sh
git diff --stat CaltrainUpcoming/schedule.json
```

The printed station and train counts shouldn't swing wildly from the previous
run; a large drop usually means the feed changed shape rather than the schedule
changing. Then rebuild in Xcode (⌘R) — `schedule.json` is a bundled resource, so
an ordinary build picks it up.

> If a rebuild doesn't seem to take effect in the Simulator, delete the app from
> the Simulator and run again. A stale install can survive a successful build,
> and the app will keep showing the old timetable.

## Data
`schedule.json` is generated from Caltrain's official **GTFS static feed**
(published by Trillium, linked from
[Caltrain Developer Resources](https://www.caltrain.com/developer-resources) —
no API key required):

    https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip

The feed carries both a weekday and a weekend calendar (Saturday and Sunday
service are identical), which is what the in-app toggle switches between.
As of the June 2026 feed that's **112 weekday** and **66 weekend** trains
across 30 stations.

Two deliberate omissions, both reported when the script runs:
- **Holiday service.** Caltrain runs a separate reduced timetable on ~9 dates
  (MLK Day, Presidents' Day, Christmas Eve, day after Thanksgiving, …), carried
  in `calendar_dates.txt` rather than as a weekday/weekend calendar. On those
  dates the app shows regular weekday service, which will be wrong. Supporting
  it means a third service mode.
- **Event trains.** One-off extras (e.g. World Cup specials) are skipped for the
  same reason. Stanford station is served *only* by such trains, so it's dropped
  from the station list entirely rather than appearing as a station that never
  returns a result.

## Project layout
- `CaltrainUpcomingApp.swift` — app entry point.
- `Platform.swift` — the iOS/macOS differences (semantic background colors,
  navigation and search placement, Mac window sizing), behind shared names.
- `Schedule.swift` — data model, schedule store (loads the bundled JSON), and
  the trip finder (direct + one-transfer, time/day-wrap handling).
- `ContentView.swift` — all UI (route card, depart/time controls, slider,
  result cards, station picker).
- `CaltrainUpcoming/schedule.json` — bundled timetable (weekday + weekend).
- `CaltrainUpcoming/CaltrainUpcoming-macOS.entitlements` — App Sandbox and the
  outgoing-network entitlement; applied to the macOS build only.
- `build_schedule.py` — GTFS parser used to regenerate `schedule.json`.
- `build_dmg.sh` — builds the Mac app and packages `dist/Commute-<version>.dmg`.
# caltraincommute
