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
The app uses the timetable bundled at `CaltrainUpcoming/schedule.json`. To
update it when Caltrain publishes a new weekday timetable, regenerate that file
with `build_schedule.py` (point it at the new PDF), replace
`CaltrainUpcoming/schedule.json`, and rebuild the app.

## Data
The timetable is bundled as `schedule.json`, generated from Caltrain's
printer-friendly **weekday** timetable, *effective January 27, 2025*
(https://www.caltrain.com/media/34716). It contains all 112 weekday trains
across 29 stations. This is weekday service only — no weekend/holiday data.

To update the schedule later, re-run the parser (`build_schedule.py`) on a newer
timetable and replace `schedule.json`.

## Project layout
- `CaltrainUpcomingApp.swift` — app entry point.
- `Schedule.swift` — data model, schedule store (loads the bundled JSON), and
  the trip finder (direct + one-transfer, time/day-wrap handling).
- `ContentView.swift` — all UI (route card, depart/time controls, slider,
  result cards, station picker).
- `CaltrainUpcoming/schedule.json` — bundled timetable.
- `build_schedule.py` — offline parser used to regenerate `schedule.json`.
# caltraincommute
