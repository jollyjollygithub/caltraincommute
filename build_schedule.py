#!/usr/bin/env python3
"""
Build schedule.json for the Caltrain "Upcoming Trains" iOS app.

Source: Caltrain's official GTFS static feed, published by Trillium.
        https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip
        (linked from https://www.caltrain.com/developer-resources — no API key)

This replaces the previous version of this script, which had the timetable
hand-transcribed into Python string literals. Parsing GTFS instead means:
  * weekend service comes for free (the feed carries both calendars), and
  * refreshing the schedule is re-running this script, not re-keying times.

Usage:
    python3 build_schedule.py                # downloads the feed, writes JSON
    python3 build_schedule.py path/to.zip    # uses a local feed instead

Writes CaltrainUpcoming/schedule.json next to this script.
"""
import csv
import io
import json
import os
import sys
import urllib.request
import zipfile

FEED_URL = "https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip"
OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "CaltrainUpcoming", "schedule.json")
TRANSFER_STATION = "San Jose Diridon"

# The app groups the feed's two calendars into these two modes. GTFS gives one
# weekend calendar covering both Saturday and Sunday, so a two-way split is
# faithful to the data rather than a simplification we're imposing.
WEEKDAY, WEEKEND = "weekday", "weekend"


def load_feed(source):
    """Returns a zipfile.ZipFile for a local path, or downloads the feed."""
    if source:
        return zipfile.ZipFile(source)
    print(f"downloading {FEED_URL} ...")
    with urllib.request.urlopen(FEED_URL) as resp:
        return zipfile.ZipFile(io.BytesIO(resp.read()))


def read_csv(zf, name):
    """GTFS files are UTF-8 CSV; utf-8-sig drops the BOM some publishers add."""
    with zf.open(name) as fh:
        return list(csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8-sig")))


def clean_station_name(raw):
    """'San Jose Diridon Station' -> 'San Jose Diridon'.

    The feed suffixes parent stations inconsistently ('... Caltrain Station',
    '... Station', or neither), so strip the longest match first.
    """
    for suffix in (" Caltrain Station", " Station", " Caltrain"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)]
    return raw


def parse_time(tok):
    """'26:30:00' -> minutes since midnight, wrapped into 0..1439.

    GTFS expresses trips past midnight as hours >= 24 so a single service day
    stays contiguous. The app stores plain minute-of-day and has its own
    day-wrap handling, so fold the overflow here.
    """
    h, m, _ = tok.split(":")
    return (int(h) * 60 + int(m)) % 1440


def build(zf):
    stops = read_csv(zf, "stops.txt")
    calendar = read_csv(zf, "calendar.txt")
    routes = read_csv(zf, "routes.txt")
    trips = read_csv(zf, "trips.txt")
    stop_times = read_csv(zf, "stop_times.txt")

    # --- stations -------------------------------------------------------
    # Platform-level stops (location_type 0) carry the times; each points at a
    # parent station (location_type 1). Resolve platforms to their parent so
    # the northbound and southbound platforms collapse to one station.
    parents = {s["stop_id"]: clean_station_name(s["stop_name"])
               for s in stops if s["location_type"] == "1"}
    platform_station = {}
    for s in stops:
        parent = s.get("parent_station") or ""
        if parent in parents:
            platform_station[s["stop_id"]] = parents[parent]

    # Canonical order is north -> south, which is just descending latitude.
    # Deriving it beats hard-coding a list: new stations land in the right slot.
    lat = {s["stop_id"]: float(s["stop_lat"]) for s in stops}
    station_order = sorted(parents, key=lambda sid: -lat[sid])
    stations = [parents[sid] for sid in station_order]

    # --- services -------------------------------------------------------
    # Classify each calendar row: it's weekday service if it runs on ANY weekday,
    # otherwise weekend. Keying off weekday-presence (rather than "runs Sat/Sun")
    # avoids mislabeling a hypothetical Mon–Sat calendar as weekend-only.
    weekdays = ("monday", "tuesday", "wednesday", "thursday", "friday")
    service_mode = {}
    for row in calendar:
        runs_weekday = any(row[d] == "1" for d in weekdays)
        service_mode[row["service_id"]] = WEEKDAY if runs_weekday else WEEKEND
    if set(service_mode.values()) != {WEEKDAY, WEEKEND}:
        raise SystemExit(f"expected both calendars, got: {service_mode}")

    # --- routes ---------------------------------------------------------
    # 'Local Weekday' and 'Local Weekend' are the same service class to a rider;
    # the calendar already says which days apply, so collapse them to 'Local'.
    route_type = {}
    for r in routes:
        name = r["route_short_name"]
        route_type[r["route_id"]] = name.replace(" Weekday", "").replace(" Weekend", "")

    # --- trips ----------------------------------------------------------
    times_by_trip = {}
    for st in stop_times:
        station = platform_station.get(st["stop_id"])
        if station is None:
            continue  # non-station stop (shuttle stand, elevator, etc.)
        times_by_trip.setdefault(st["trip_id"], []).append(
            (int(st["stop_sequence"]), station, parse_time(st["departure_time"]))
        )

    trains = []
    skipped = {}
    for t in trips:
        seq = times_by_trip.get(t["trip_id"])
        if not seq:
            continue
        # Trips on a service_id that isn't in calendar.txt run only on specific
        # exception dates in calendar_dates.txt — Caltrain's reduced holiday
        # schedule, plus one-off event trains. Neither is weekday or weekend
        # service, so they can't be represented by the app's two-way toggle.
        # Count them so the omission shows up in the run output.
        if t["service_id"] not in service_mode:
            skipped[t["service_id"]] = skipped.get(t["service_id"], 0) + 1
            continue
        seq.sort()  # by stop_sequence — the feed's own travel order
        trains.append({
            "id": t["trip_short_name"] or t["trip_id"],
            "service": service_mode[t["service_id"]],
            # directions.txt: 0 = North, 1 = South.
            "direction": "NB" if t["direction_id"] == "0" else "SB",
            "type": route_type.get(t["route_id"], "Local"),
            "stops": [{"station": s, "min": m} for _, s, m in seq],
        })

    trains.sort(key=lambda tr: (tr["service"], tr["stops"][0]["min"], tr["id"]))

    # Drop stations no scheduled train actually calls at. Stanford is the live
    # case: it only sees Stanford-football special trains, which ride the
    # exception-date calendars we skipped above. Listing it in the picker would
    # offer the rider a station that can never return a result.
    called_at = {s["station"] for tr in trains for s in tr["stops"]}
    unserved = [s for s in stations if s not in called_at]
    for s in unserved:
        print(f"  note: dropped station with no scheduled service: {s}")
    stations = [s for s in stations if s in called_at]

    for sid, n in sorted(skipped.items()):
        print(f"  note: skipped {n} exception-date trips (service {sid})")

    feed_info = read_csv(zf, "feed_info.txt")
    version = feed_info[0]["feed_version"] if feed_info else "unknown"

    return {
        "source": f"Caltrain GTFS static feed (Trillium), {version}",
        "services": [WEEKDAY, WEEKEND],
        "stations": stations,
        "transferStation": TRANSFER_STATION,
        "trains": trains,
    }


def main():
    zf = load_feed(sys.argv[1] if len(sys.argv) > 1 else None)
    data = build(zf)

    if TRANSFER_STATION not in data["stations"]:
        raise SystemExit(f"transfer station {TRANSFER_STATION!r} missing from feed")

    with open(OUT_PATH, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")

    counts = {}
    for t in data["trains"]:
        counts[t["service"]] = counts.get(t["service"], 0) + 1
    print(f"wrote {OUT_PATH}")
    print(f"  source:   {data['source']}")
    print(f"  stations: {len(data['stations'])}")
    print(f"  trains:   {counts}")


if __name__ == "__main__":
    main()
