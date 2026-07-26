# Caltrain Upcoming — iOS app

A small SwiftUI iPhone app that shows the next Caltrain departures between two
stations.

## Open & run
1. Open `CaltrainUpcoming.xcodeproj` in Xcode 15 or later.
2. Select an iPhone simulator (or your device) and press **Run** (⌘R).
3. On a device, set **Signing & Capabilities → Team** to your Apple ID first.

Deployment target: iOS 16+.

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
- `Schedule.swift` — data model, schedule store (loads the bundled JSON), and
  the trip finder (direct + one-transfer, time/day-wrap handling).
- `ContentView.swift` — all UI (route card, depart/time controls, slider,
  result cards, station picker).
- `CaltrainUpcoming/schedule.json` — bundled timetable (weekday + weekend).
- `build_schedule.py` — GTFS parser used to regenerate `schedule.json`.
# caltraincommute
