#!/usr/bin/env python3
"""
Build schedule.json for the Caltrain "Upcoming Trains" iOS app.
Source: Caltrain printer-friendly WEEKDAY timetable, EFFECTIVE January 27, 2025
(https://www.caltrain.com/media/34716)

Data was decoded from the timetable using header-order column mapping for
main-line rows (San Jose Diridon and north) plus explicit encoding of the
South County Connector (Gilroy line) shuttle trains, which terminate at /
originate from San Jose Diridon.
"""
import json, re

# Canonical station order, NORTH -> SOUTH
STATIONS = [
    "San Francisco", "22nd Street", "Bayshore", "South San Francisco",
    "San Bruno", "Millbrae", "Burlingame", "San Mateo", "Hayward Park",
    "Hillsdale", "Belmont", "San Carlos", "Redwood City", "Menlo Park",
    "Palo Alto", "California Avenue", "San Antonio", "Mountain View",
    "Sunnyvale", "Lawrence", "Santa Clara", "College Park",
    "San Jose Diridon", "Tamien", "Capitol", "Blossom Hill",
    "Morgan Hill", "San Martin", "Gilroy",
]
ORDER = {s: i for i, s in enumerate(STATIONS)}

BYPASS = {"-", "–", "—", "x", ""}  # hyphen, en-dash, em-dash, marker, blank


def parse_time(tok):
    """'6:01a' / '12:48a' / '1:23a' -> minutes since midnight (0..1439)."""
    m = re.match(r"^(\d{1,2}):(\d{2})([ap])$", tok)
    if not m:
        raise ValueError(f"bad time token: {tok!r}")
    h, mn, ap = int(m.group(1)), int(m.group(2)), m.group(3)
    if ap == "a":
        if h == 12:
            h = 0
    else:
        if h != 12:
            h += 12
    return h * 60 + mn


def toks(s):
    return s.split()


# Per-train accumulator: train_id -> {"type":..,"dir":..,"stops":{station:minute}}
trains = {}


def train_type(num):
    n = int(num)
    if 800 <= n < 900:
        return "South County Connector"
    last = n % 100
    if last in (0, 1):  # not a real rule; fall through
        pass
    if 500 <= (n % 1000) < 600 or (n % 100) in range(0, 100) and str(num).startswith("5"):
        pass
    s = str(num)
    if s.startswith("5"):
        return "Express"
    if s.startswith("4"):
        return "Limited"
    if s.startswith("8"):
        return "South County Connector"
    return "Local"


def add_row(direction, train_list, station, token_str):
    """Map tokens in header order onto train_list for one station row."""
    tk = toks(token_str)
    assert len(tk) == len(train_list), (
        f"{direction} {station}: {len(tk)} tokens != {len(train_list)} trains")
    for num, t in zip(train_list, tk):
        if t in BYPASS:
            continue
        minute = parse_time(t)
        tr = trains.setdefault(num, {"type": train_type(num), "dir": direction, "stops": {}})
        tr["stops"][station] = minute


def add_stop(num, direction, station, tok):
    minute = parse_time(tok)
    tr = trains.setdefault(num, {"type": train_type(num), "dir": direction, "stops": {}})
    tr["stops"][station] = minute


# ----------------------------------------------------------------------------
# NORTHBOUND  (to San Francisco)
# ----------------------------------------------------------------------------
NB1 = ["101","103","401","105","503","107","405","109","507","111","409","113",
       "511","115","413","117","119","121","123","125","127","129","131","133"]

nb1_rows = {
"San Francisco":      "6:01a 6:26a 6:53a 7:16a 7:22a 7:46a 7:53a 8:16a 8:22a 8:46a 8:53a 9:16a 9:22a 9:46a 9:53a 10:16a 10:46a 11:16a 11:46a 12:16p 12:46p 1:16p 1:46p 2:16p",
"22nd Street":        "5:55a 6:20a 6:47a 7:10a 7:16a 7:40a 7:47a 8:10a 8:16a 8:40a 8:47a 9:10a 9:16a 9:40a 9:47a 10:10a 10:40a 11:10a 11:40a 12:10p 12:40p 1:10p 1:40p 2:10p",
"Bayshore":           "5:50a 6:15a - 7:05a - 7:35a - 8:05a - 8:35a - 9:05a - 9:35a - 10:05a 10:35a 11:05a 11:35a 12:05p 12:35p 1:05p 1:35p 2:05p",
"South San Francisco":"5:45a 6:10a 6:39a 7:00a 7:09a 7:30a 7:39a 8:00a 8:09a 8:30a 8:39a 9:00a 9:09a 9:30a 9:39a 10:00a 10:30a 11:00a 11:30a 12:00p 12:30p 1:00p 1:30p 2:00p",
"San Bruno":          "5:42a 6:07a - 6:57a - 7:27a - 7:57a - 8:27a - 8:57a - 9:27a - 9:57a 10:27a 10:57a 11:27a 11:57a 12:27p 12:57p 1:27p 1:57p",
"Millbrae":           "5:39a 6:04a 6:33a 6:54a 7:04a 7:24a 7:33a 7:54a 8:04a 8:24a 8:33a 8:54a 9:04a 9:24a 9:33a 9:54a 10:24a 10:54a 11:24a 11:54a 12:24p 12:54p 1:24p 1:54p",
"Burlingame":         "5:35a 6:00a - 6:50a - 7:20a - 7:50a - 8:20a - 8:50a - 9:20a - 9:50a 10:20a 10:50a 11:20a 11:50a 12:20p 12:50p 1:20p 1:50p",
"San Mateo":          "5:32a 5:57a 6:28a 6:47a 6:59a 7:17a 7:28a 7:47a 7:59a 8:17a 8:28a 8:47a 8:59a 9:17a 9:28a 9:47a 10:17a 10:47a 11:17a 11:47a 12:17p 12:47p 1:17p 1:47p",
"Hayward Park":       "5:30a 5:55a - 6:45a - 7:15a - 7:45a - 8:15a - 8:45a - 9:15a - 9:45a 10:15a 10:45a 11:15a 11:45a 12:15p 12:45p 1:15p 1:45p",
"Hillsdale":          "5:27a 5:52a 6:25a 6:42a 6:56a 7:12a 7:25a 7:42a 7:56a 8:12a 8:25a 8:43a 8:56a 9:12a 9:25a 9:42a 10:12a 10:42a 11:12a 11:42a 12:12p 12:42p 1:12p 1:42p",
"Belmont":            "5:24a 5:49a - 6:39a - 7:09a - 7:39a - 8:09a - 8:39a - 9:09a - 9:39a 10:09a 10:39a 11:09a 11:39a 12:09p 12:39p 1:09p 1:39p",
"San Carlos":         "5:22a 5:47a - 6:37a - 7:07a - 7:37a - 8:07a - 8:37a - 9:07a - 9:37a 10:07a 10:37a 11:07a 11:37a 12:07p 12:37p 1:07p 1:37p",
"Redwood City":       "5:18a 5:43a 6:18a 6:33a 6:49a 7:03a 7:18a 7:33a 7:49a 8:03a 8:18a 8:34a 8:49a 9:03a 9:18a 9:33a 10:03a 10:33a 11:03a 11:33a 12:03p 12:33p 1:03p 1:33p",
"Menlo Park":         "5:13a 5:38a 6:13a 6:28a - 6:58a 7:13a 7:28a - 7:58a 8:13a 8:28a - 8:58a 9:13a 9:28a 9:58a 10:28a 10:58a 11:28a 11:58a 12:28p 12:58p 1:28p",
"Palo Alto":          "5:10a 5:35a 6:10a 6:25a 6:43a 6:55a 7:10a 7:25a 7:43a 7:55a 8:10a 8:25a 8:43a 8:55a 9:11a 9:25a 9:55a 10:25a 10:55a 11:25a 11:55a 12:25p 12:55p 1:25p",
"California Avenue":  "5:07a 5:32a 6:07a 6:22a - 6:52a 7:07a 7:22a - 7:52a 8:07a 8:22a - 8:52a 9:07a 9:22a 9:52a 10:22a 10:52a 11:22a 11:52a 12:22p 12:52p 1:22p",
"San Antonio":        "5:04a 5:29a 6:04a 6:19a - 6:49a 7:04a 7:19a - 7:49a 8:04a 8:19a - 8:49a 9:04a 9:19a 9:49a 10:19a 10:49a 11:19a 11:49a 12:19p 12:49p 1:19p",
"Mountain View":      "5:01a 5:26a 6:01a 6:16a 6:36a 6:46a 7:01a 7:16a 7:36a 7:46a 8:01a 8:16a 8:36a 8:46a 9:01a 9:16a 9:46a 10:16a 10:46a 11:16a 11:46a 12:16p 12:46p 1:16p",
"Sunnyvale":          "4:57a 5:22a 5:57a 6:12a 6:32a 6:42a 6:57a 7:12a 7:32a 7:42a 7:57a 8:12a 8:32a 8:42a 8:58a 9:12a 9:42a 10:12a 10:42a 11:12a 11:42a 12:12p 12:42p 1:12p",
"Lawrence":           "4:54a 5:19a 5:54a 6:09a - 6:39a 6:54a 7:09a - 7:39a 7:54a 8:09a - 8:39a 8:54a 9:09a 9:39a 10:09a 10:39a 11:09a 11:39a 12:09p 12:39p 1:09p",
"Santa Clara":        "4:49a 5:14a 5:49a 6:04a - 6:34a 6:49a 7:04a - 7:34a 7:49a 8:04a - 8:34a 8:49a 9:04a 9:34a 10:04a 10:34a 11:04a 11:34a 12:04p 12:34p 1:04p",
"San Jose Diridon":   "4:43a 5:08a 5:43a 5:58a 6:22a 6:28a 6:43a 6:58a 7:22a 7:28a 7:43a 7:53a 8:22a 8:28a 8:43a 8:58a 9:28a 9:58a 10:28a 10:58a 11:28a 11:58a 12:28p 12:58p",
}
for st, row in nb1_rows.items():
    add_row("N", NB1, st, row)

# College Park NB: only train 113 stops, 8:01a
add_stop("113", "N", "College Park", "8:01a")

# Tamien NB origins (locals that start at Tamien)
for num, t in [("101","4:37a"),("105","5:52a"),("109","6:52a"),("113","7:47a"),
               ("117","8:52a"),("121","9:52a"),("125","10:52a"),("129","11:52a"),("133","12:52p")]:
    add_stop(num, "N", "Tamien", t)

NB2 = ["135","137","139","141","515","143","417","145","519","147","421","149",
       "523","151","425","153","527","155","429","157","159","161","163","165",
       "167","169","171","173"]
nb2_rows = {
"San Francisco":      "2:46p 3:16p 3:46p 4:16p 4:22p 4:46p 4:53p 5:16p 5:22p 5:46p 5:53p 6:16p 6:22p 6:46p 6:53p 7:16p 7:22p 7:46p 7:53p 8:16p 8:46p 9:16p 9:46p 10:16p 10:46p 11:16p 11:48p 12:48a",
"22nd Street":        "2:40p 3:10p 3:40p 4:10p 4:16p 4:40p 4:47p 5:10p 5:16p 5:40p 5:47p 6:10p 6:16p 6:40p 6:47p 7:10p 7:16p 7:40p 7:47p 8:10p 8:40p 9:10p 9:40p 10:10p 10:40p 11:10p 11:42p 12:42a",
"Bayshore":           "2:35p 3:05p 3:35p 4:05p - 4:35p - 5:05p - 5:35p - 6:05p - 6:35p - 7:05p - 7:35p - 8:05p 8:35p 9:05p 9:35p 10:05p 10:35p 11:05p 11:37p 12:37a",
"South San Francisco":"2:30p 3:00p 3:30p 4:00p 4:09p 4:30p 4:39p 5:00p 5:09p 5:30p 5:39p 6:00p 6:09p 6:30p 6:39p 7:00p 7:09p 7:30p 7:39p 8:00p 8:30p 9:00p 9:30p 10:00p 10:30p 11:00p 11:32p 12:32a",
"San Bruno":          "2:27p 2:57p 3:27p 3:57p - 4:27p - 4:57p - 5:27p - 5:57p - 6:27p - 6:57p - 7:27p - 7:57p 8:27p 8:57p 9:27p 9:57p 10:27p 10:57p 11:29p 12:29a",
"Millbrae":           "2:24p 2:54p 3:24p 3:54p 4:04p 4:24p 4:33p 4:54p 5:04p 5:24p 5:33p 5:54p 6:04p 6:24p 6:33p 6:54p 7:04p 7:24p 7:33p 7:54p 8:24p 8:54p 9:24p 9:54p 10:24p 10:54p 11:26p 12:26a",
"Burlingame":         "2:20p 2:50p 3:20p 3:50p - 4:20p - 4:50p - 5:20p - 5:50p - 6:20p - 6:50p - 7:20p - 7:50p 8:20p 8:50p 9:20p 9:50p 10:20p 10:50p 11:22p 12:22a",
"San Mateo":          "2:17p 2:47p 3:17p 3:47p 3:59p 4:17p 4:28p 4:47p 4:59p 5:17p 5:28p 5:47p 5:59p 6:17p 6:28p 6:47p 6:59p 7:17p 7:28p 7:47p 8:17p 8:47p 9:17p 9:47p 10:17p 10:47p 11:19p 12:19a",
"Hayward Park":       "2:15p 2:45p 3:15p 3:45p - 4:15p - 4:45p - 5:15p - 5:45p - 6:15p - 6:45p - 7:15p - 7:45p 8:15p 8:45p 9:15p 9:45p 10:15p 10:45p 11:17p 12:17a",
"Hillsdale":          "2:12p 2:42p 3:12p 3:43p 3:56p 4:12p 4:25p 4:42p 4:56p 5:12p 5:25p 5:42p 5:56p 6:12p 6:25p 6:42p 6:56p 7:12p 7:25p 7:42p 8:12p 8:42p 9:12p 9:42p 10:12p 10:42p 11:14p 12:14a",
"Belmont":            "2:09p 2:39p 3:09p 3:39p - 4:09p - 4:39p - 5:09p - 5:39p - 6:09p - 6:39p - 7:09p - 7:39p 8:09p 8:39p 9:09p 9:39p 10:09p 10:39p 11:11p 12:11a",
"San Carlos":         "2:07p 2:37p 3:07p 3:37p - 4:07p - 4:37p - 5:07p - 5:37p - 6:07p - 6:37p - 7:07p - 7:37p 8:07p 8:37p 9:07p 9:37p 10:07p 10:37p 11:09p 12:09a",
"Redwood City":       "2:03p 2:33p 3:03p 3:34p 3:49p 4:03p 4:18p 4:33p 4:49p 5:03p 5:18p 5:33p 5:49p 6:03p 6:18p 6:33p 6:49p 7:03p 7:18p 7:33p 8:03p 8:33p 9:03p 9:33p 10:03p 10:33p 11:05p 12:05a",
"Menlo Park":         "1:58p 2:28p 2:58p 3:28p - 3:58p 4:13p 4:28p - 4:58p 5:13p 5:28p - 5:58p 6:13p 6:28p - 6:58p 7:13p 7:28p 7:58p 8:28p 8:58p 9:28p 9:58p 10:28p 11:00p 12:00a",
"Palo Alto":          "1:55p 2:25p 2:55p 3:25p 3:43p 3:55p 4:10p 4:25p 4:43p 4:55p 5:10p 5:25p 5:43p 5:55p 6:10p 6:25p 6:43p 6:55p 7:10p 7:25p 7:55p 8:25p 8:55p 9:25p 9:55p 10:25p 10:57p 11:57p",
"California Avenue":  "1:52p 2:22p 2:52p 3:22p - 3:52p 4:07p 4:22p - 4:52p 5:07p 5:22p - 5:52p 6:07p 6:22p - 6:52p 7:07p 7:22p 7:52p 8:22p 8:52p 9:22p 9:52p 10:22p 10:54p 11:54p",
"San Antonio":        "1:49p 2:19p 2:49p 3:19p - 3:49p 4:04p 4:19p - 4:49p 5:04p 5:19p - 5:49p 6:04p 6:19p - 6:49p 7:04p 7:19p 7:49p 8:19p 8:49p 9:19p 9:49p 10:19p 10:51p 11:51p",
"Mountain View":      "1:46p 2:16p 2:46p 3:16p 3:36p 3:46p 4:01p 4:16p 4:36p 4:46p 5:01p 5:16p 5:36p 5:46p 6:01p 6:16p 6:36p 6:46p 7:01p 7:16p 7:46p 8:16p 8:46p 9:16p 9:46p 10:16p 10:48p 11:48p",
"Sunnyvale":          "1:42p 2:12p 2:42p 3:12p 3:32p 3:42p 3:57p 4:12p 4:32p 4:42p 4:57p 5:12p 5:32p 5:42p 5:57p 6:12p 6:32p 6:42p 6:57p 7:12p 7:42p 8:12p 8:42p 9:12p 9:42p 10:12p 10:44p 11:44p",
"Lawrence":           "1:39p 2:09p 2:39p 3:09p - 3:39p 3:54p 4:09p - 4:39p 4:54p 5:09p - 5:39p 5:54p 6:09p - 6:39p 6:54p 7:09p 7:39p 8:09p 8:39p 9:09p 9:39p 10:09p 10:41p 11:41p",
"Santa Clara":        "1:34p 2:04p 2:34p 3:04p - 3:34p 3:49p 4:04p - 4:34p 4:49p 5:04p - 5:34p 5:49p 6:04p - 6:34p 6:49p 7:04p 7:34p 8:04p 8:34p 9:04p 9:34p 10:04p 10:36p 11:36p",
"San Jose Diridon":   "1:28p 1:58p 2:28p 2:53p 3:22p 3:28p 3:43p 3:58p 4:22p 4:28p 4:43p 4:58p 5:22p 5:28p 5:43p 5:58p 6:22p 6:28p 6:43p 6:58p 7:28p 7:58p 8:28p 8:58p 9:28p 9:58p 10:30p 11:30p",
}
for st, row in nb2_rows.items():
    add_row("N", NB2, st, row)
for num, t in [("137","1:52p"),("141","2:47p"),("145","3:52p"),("149","4:52p"),
               ("153","5:52p"),("157","6:52p"),("161","7:52p"),("165","8:52p"),
               ("169","9:52p"),("173","11:24p")]:
    add_stop(num, "N", "Tamien", t)

# NB South County Connector shuttles (Gilroy -> San Jose Diridon, terminate there)
nb_scc = {
"805": [("Gilroy","5:52a"),("San Martin","6:04a"),("Morgan Hill","6:10a"),("Blossom Hill","6:23a"),("Capitol","6:29a"),("Tamien","6:35a"),("San Jose Diridon","6:40a")],
"807": [("Gilroy","6:31a"),("San Martin","6:43a"),("Morgan Hill","6:49a"),("Blossom Hill","7:02a"),("Capitol","7:08a"),("Tamien","7:14a"),("San Jose Diridon","7:19a")],
"809": [("Gilroy","6:52a"),("San Martin","7:04a"),("Morgan Hill","7:10a"),("Blossom Hill","7:23a"),("Capitol","7:29a"),("Tamien","7:35a"),("San Jose Diridon","7:40a")],
"811": [("Gilroy","7:31a"),("San Martin","7:43a"),("Morgan Hill","7:49a"),("Blossom Hill","8:02a"),("Capitol","8:08a"),("Tamien","8:14a"),("San Jose Diridon","8:19a")],
}
for num, stops in nb_scc.items():
    for st, t in stops:
        add_stop(num, "N", st, t)

# ----------------------------------------------------------------------------
# SOUTHBOUND  (to San Jose / Gilroy)
# ----------------------------------------------------------------------------
SB1 = ["102","104","502","106","404","108","506","110","408","112","510","114",
       "412","116","118","120","122","124","126","128","130","132","134","136",
       "138","140","514"]
sb1_rows = {
"San Francisco":      "4:55a 5:30a 6:20a 6:25a 6:48a 6:55a 7:20a 7:25a 7:48a 7:55a 8:20a 8:25a 8:48a 8:55a 9:25a 9:55a 10:25a 10:55a 11:25a 11:55a 12:25p 12:55p 1:25p 1:55p 2:25p 2:55p 3:20p",
"22nd Street":        "5:00a 5:35a 6:24a 6:30a 6:53a 7:00a 7:24a 7:30a 7:53a 8:00a 8:24a 8:30a 8:53a 9:00a 9:30a 10:00a 10:30a 11:00a 11:30a 12:00p 12:30p 1:00p 1:30p 2:00p 2:30p 3:00p 3:24p",
"Bayshore":           "5:04a 5:39a - 6:34a - 7:04a - 7:34a - 8:04a - 8:34a - 9:04a 9:34a 10:04a 10:34a 11:04a 11:34a 12:04p 12:34p 1:04p 1:34p 2:04p 2:34p 3:04p -",
"South San Francisco":"5:10a 5:46a 6:32a 6:40a 7:01a 7:10a 7:32a 7:40a 8:01a 8:10a 8:32a 8:40a 9:01a 9:10a 9:40a 10:10a 10:40a 11:10a 11:40a 12:10p 12:40p 1:10p 1:40p 2:10p 2:40p 3:10p 3:32p",
"San Bruno":          "5:13a 5:49a - 6:43a - 7:13a - 7:43a - 8:13a - 8:43a - 9:13a 9:43a 10:13a 10:43a 11:13a 11:43a 12:13p 12:43p 1:13p 1:43p 2:13p 2:43p 3:13p -",
"Millbrae":           "5:16a 5:52a 6:38a 6:46a 7:07a 7:16a 7:38a 7:46a 8:07a 8:16a 8:38a 8:46a 9:07a 9:16a 9:46a 10:16a 10:46a 11:16a 11:46a 12:16p 12:46p 1:16p 1:46p 2:16p 2:46p 3:16p 3:38p",
"Burlingame":         "5:20a 5:56a - 6:50a - 7:20a - 7:50a - 8:20a - 8:50a - 9:20a 9:50a 10:20a 10:50a 11:20a 11:50a 12:20p 12:50p 1:20p 1:50p 2:20p 2:50p 3:20p -",
"San Mateo":          "5:23a 5:59a 6:43a 6:53a 7:12a 7:23a 7:43a 7:53a 8:12a 8:23a 8:43a 8:53a 9:12a 9:23a 9:53a 10:23a 10:53a 11:23a 11:53a 12:23p 12:53p 1:23p 1:53p 2:23p 2:53p 3:23p 3:43p",
"Hayward Park":       "5:25a 6:02a - 6:55a - 7:25a - 7:55a - 8:25a - 8:55a - 9:25a 9:55a 10:25a 10:55a 11:25a 11:55a 12:25p 12:55p 1:25p 1:55p 2:25p 2:55p 3:25p -",
"Hillsdale":          "5:27a 6:05a 6:46a 6:57a 7:15a 7:27a 7:46a 7:57a 8:15a 8:27a 8:46a 8:57a 9:15a 9:27a 9:57a 10:27a 10:57a 11:27a 11:57a 12:27p 12:57p 1:27p 1:57p 2:27p 2:57p 3:27p 3:46p",
"Belmont":            "5:31a 6:09a - 7:01a - 7:31a - 8:01a - 8:31a - 9:01a - 9:31a 10:01a 10:31a 11:01a 11:31a 12:01p 12:31p 1:01p 1:31p 2:01p 2:31p 3:01p 3:31p -",
"San Carlos":         "5:33a 6:12a - 7:03a - 7:33a - 8:03a - 8:33a - 9:03a - 9:33a 10:03a 10:33a 11:03a 11:33a 12:03p 12:33p 1:03p 1:33p 2:03p 2:33p 3:03p 3:33p -",
"Redwood City":       "5:37a 6:16a 6:53a 7:07a 7:22a 7:37a 7:53a 8:07a 8:22a 8:37a 8:53a 9:07a 9:22a 9:37a 10:07a 10:37a 11:07a 11:37a 12:07p 12:37p 1:07p 1:37p 2:07p 2:37p 3:07p 3:37p 3:53p",
"Menlo Park":         "5:41a 6:20a - 7:11a 7:26a 7:41a - 8:11a 8:26a 8:41a - 9:11a 9:26a 9:41a 10:11a 10:41a 11:11a 11:41a 12:11p 12:41p 1:11p 1:41p 2:11p 2:41p 3:11p 3:41p -",
"Palo Alto":          "5:44a 6:24a 6:59a 7:14a 7:29a 7:44a 7:59a 8:14a 8:29a 8:44a 8:59a 9:14a 9:29a 9:44a 10:14a 10:44a 11:14a 11:44a 12:14p 12:44p 1:14p 1:44p 2:14p 2:44p 3:14p 3:44p 3:59p",
"California Avenue":  "5:47a 6:27a - 7:17a 7:32a 7:47a - 8:17a 8:32a 8:47a - 9:17a 9:32a 9:47a 10:17a 10:47a 11:17a 11:47a 12:17p 12:47p 1:17p 1:47p 2:17p 2:47p 3:17p 3:47p -",
"San Antonio":        "5:51a 6:31a - 7:21a 7:36a 7:51a - 8:21a 8:36a 8:51a - 9:21a 9:36a 9:51a 10:21a 10:51a 11:21a 11:51a 12:21p 12:51p 1:21p 1:51p 2:21p 2:51p 3:21p 3:51p -",
"Mountain View":      "5:54a 6:34a 7:06a 7:24a 7:39a 7:54a 8:06a 8:24a 8:39a 8:54a 9:06a 9:24a 9:39a 9:54a 10:24a 10:54a 11:24a 11:54a 12:24p 12:54p 1:24p 1:54p 2:24p 2:54p 3:24p 3:54p 4:06p",
"Sunnyvale":          "5:58a 6:38a 7:09a 7:28a 7:43a 7:58a 8:09a 8:28a 8:43a 8:58a 9:09a 9:28a 9:43a 9:58a 10:28a 10:58a 11:28a 11:58a 12:28p 12:58p 1:28p 1:58p 2:28p 2:58p 3:28p 3:58p 4:09p",
"Lawrence":           "6:01a 6:41a - 7:31a 7:46a 8:01a - 8:31a 8:46a 9:01a - 9:31a 9:46a 10:01a 10:31a 11:01a 11:31a 12:01p 12:31p 1:01p 1:31p 2:01p 2:31p 3:01p 3:31p 4:01p -",
"Santa Clara":        "6:06a 6:46a - 7:36a 7:51a 8:06a - 8:36a 8:51a 9:06a - 9:36a 9:51a 10:06a 10:36a 11:06a 11:36a 12:06p 12:36p 1:06p 1:36p 2:06p 2:36p 3:06p 3:36p 4:06p -",
"San Jose Diridon":   "6:12a 7:03a 7:20a 7:42a 7:58a 8:23a 8:20a 8:42a 8:58a 9:13a 9:20a 9:42a 9:58a 10:13a 10:42a 11:13a 11:42a 12:13p 12:42p 1:13p 1:42p 2:13p 2:42p 3:13p 3:42p 4:14p 4:20p",
}
for st, row in sb1_rows.items():
    add_row("S", SB1, st, row)
# College Park SB
add_stop("108", "S", "College Park", "8:08a")
add_stop("140", "S", "College Park", "4:08p")
# Tamien SB terminations (locals continuing to Tamien)
for num, t in [("104","7:08a"),("108","8:28a"),("112","9:18a"),("116","10:18a"),
               ("120","11:18a"),("124","12:18p"),("128","1:18p"),("132","2:18p"),
               ("136","3:18p"),("140","4:19p")]:
    add_stop(num, "S", "Tamien", t)

SB2 = ["142","416","144","518","146","420","148","522","150","424","152","526",
       "154","428","156","158","160","162","164","166","168","170","172","174","176"]
sb2_rows = {
"San Francisco":      "3:25p 3:48p 3:55p 4:20p 4:25p 4:48p 4:55p 5:20p 5:25p 5:48p 5:55p 6:20p 6:25p 6:48p 6:55p 7:25p 7:55p 8:25p 8:55p 9:25p 9:55p 10:25p 10:55p 11:25p 12:05a",
"22nd Street":        "3:30p 3:53p 4:00p 4:24p 4:30p 4:53p 5:00p 5:24p 5:30p 5:53p 6:00p 6:24p 6:30p 6:53p 7:00p 7:30p 8:00p 8:30p 9:00p 9:30p 10:00p 10:30p 11:00p 11:30p 12:10a",
"Bayshore":           "3:34p - 4:04p - 4:34p - 5:04p - 5:34p - 6:04p - 6:34p - 7:04p 7:34p 8:04p 8:34p 9:04p 9:34p 10:04p 10:34p 11:04p 11:34p 12:14a",
"South San Francisco":"3:40p 4:01p 4:10p 4:32p 4:40p 5:01p 5:10p 5:32p 5:40p 6:01p 6:10p 6:32p 6:40p 7:01p 7:10p 7:40p 8:10p 8:40p 9:10p 9:40p 10:10p 10:40p 11:10p 11:40p 12:20a",
"San Bruno":          "3:43p - 4:13p - 4:43p - 5:13p - 5:43p - 6:13p - 6:43p - 7:13p 7:43p 8:13p 8:43p 9:13p 9:43p 10:13p 10:43p 11:13p 11:43p 12:23a",
"Millbrae":           "3:46p 4:07p 4:16p 4:38p 4:46p 5:07p 5:16p 5:38p 5:46p 6:07p 6:16p 6:38p 6:46p 7:07p 7:16p 7:46p 8:16p 8:46p 9:16p 9:46p 10:16p 10:46p 11:16p 11:46p 12:26a",
"Burlingame":         "3:50p - 4:20p - 4:50p - 5:20p - 5:50p - 6:20p - 6:50p - 7:20p 7:50p 8:20p 8:50p 9:20p 9:50p 10:20p 10:50p 11:20p 11:50p 12:30a",
"San Mateo":          "3:53p 4:12p 4:23p 4:43p 4:53p 5:12p 5:23p 5:43p 5:53p 6:12p 6:23p 6:43p 6:53p 7:12p 7:23p 7:53p 8:23p 8:53p 9:23p 9:53p 10:23p 10:53p 11:23p 11:53p 12:33a",
"Hayward Park":       "3:55p - 4:25p - 4:55p - 5:25p - 5:55p - 6:25p - 6:55p - 7:25p 7:55p 8:25p 8:55p 9:25p 9:55p 10:25p 10:55p 11:25p 11:55p 12:35a",
"Hillsdale":          "3:57p 4:15p 4:27p 4:46p 4:57p 5:15p 5:27p 5:46p 5:57p 6:15p 6:27p 6:46p 6:57p 7:15p 7:27p 7:57p 8:27p 8:57p 9:27p 9:57p 10:27p 10:57p 11:27p 11:57p 12:37a",
"Belmont":            "4:01p - 4:31p - 5:01p - 5:31p - 6:01p - 6:31p - 7:01p - 7:31p 8:01p 8:31p 9:01p 9:31p 10:01p 10:31p 11:01p 11:31p 12:01a 12:41a",
"San Carlos":         "4:03p - 4:33p - 5:03p - 5:33p - 6:03p - 6:33p - 7:03p - 7:33p 8:03p 8:33p 9:03p 9:33p 10:03p 10:33p 11:03p 11:33p 12:03a 12:43a",
"Redwood City":       "4:07p 4:22p 4:37p 4:53p 5:07p 5:22p 5:37p 5:53p 6:07p 6:22p 6:37p 6:53p 7:07p 7:22p 7:37p 8:07p 8:37p 9:07p 9:37p 10:07p 10:37p 11:07p 11:37p 12:07a 12:47a",
"Menlo Park":         "4:11p 4:26p 4:41p - 5:11p 5:26p 5:41p - 6:11p 6:26p 6:41p - 7:11p 7:26p 7:41p 8:11p 8:41p 9:11p 9:41p 10:11p 10:41p 11:11p 11:41p 12:11a 12:51a",
"Palo Alto":          "4:14p 4:29p 4:44p 4:59p 5:14p 5:29p 5:44p 5:59p 6:14p 6:29p 6:44p 6:59p 7:14p 7:29p 7:44p 8:14p 8:44p 9:14p 9:44p 10:14p 10:44p 11:14p 11:44p 12:14a 12:54a",
"California Avenue":  "4:17p 4:32p 4:47p - 5:17p 5:32p 5:47p - 6:17p 6:32p 6:47p - 7:17p 7:32p 7:47p 8:17p 8:47p 9:17p 9:47p 10:17p 10:47p 11:17p 11:47p 12:17a 12:57a",
"San Antonio":        "4:21p 4:36p 4:51p - 5:21p 5:36p 5:51p - 6:21p 6:36p 6:51p - 7:21p 7:36p 7:51p 8:21p 8:51p 9:21p 9:51p 10:21p 10:51p 11:21p 11:51p 12:21a 1:01a",
"Mountain View":      "4:24p 4:39p 4:54p 5:06p 5:24p 5:39p 5:54p 6:06p 6:24p 6:39p 6:54p 7:06p 7:24p 7:39p 7:54p 8:24p 8:54p 9:24p 9:54p 10:24p 10:54p 11:24p 11:54p 12:24a 1:04a",
"Sunnyvale":          "4:28p 4:43p 4:58p 5:09p 5:28p 5:43p 5:58p 6:09p 6:28p 6:43p 6:58p 7:09p 7:28p 7:43p 7:58p 8:28p 8:58p 9:28p 9:58p 10:28p 10:58p 11:28p 11:58p 12:28a 1:08a",
"Lawrence":           "4:31p 4:46p 5:01p - 5:31p 5:46p 6:01p - 6:31p 6:46p 7:01p - 7:31p 7:46p 8:01p 8:31p 9:01p 9:31p 10:01p 10:31p 11:01p 11:31p 12:01a 12:31a 1:11a",
"Santa Clara":        "4:36p 4:51p 5:06p - 5:36p 5:51p 6:06p - 6:36p 6:51p 7:06p - 7:36p 7:51p 8:06p 8:36p 9:06p 9:36p 10:06p 10:36p 11:06p 11:36p 12:06a 12:36a 1:16a",
"San Jose Diridon":   "4:42p 4:58p 5:13p 5:20p 5:42p 5:58p 6:13p 6:20p 6:42p 6:58p 7:13p 7:20p 7:42p 7:58p 8:13p 8:42p 9:13p 9:42p 10:13p 10:42p 11:13p 11:42p 12:13a 12:42a 1:23a",
}
for st, row in sb2_rows.items():
    add_row("S", SB2, st, row)
for num, t in [("144","5:18p"),("148","6:18p"),("152","7:18p"),("156","8:18p"),
               ("160","9:18p"),("164","10:18p"),("168","11:18p"),("172","12:18a"),("176","1:28a")]:
    add_stop(num, "S", "Tamien", t)

# SB South County Connector shuttles (San Jose Diridon -> Gilroy)
sb_scc = {
"814": [("San Jose Diridon","4:23p"),("Tamien","4:28p"),("Capitol","4:34p"),("Blossom Hill","4:40p"),("Morgan Hill","4:53p"),("San Martin","5:00p"),("Gilroy","5:11p")],
"816": [("San Jose Diridon","5:01p"),("Tamien","5:06p"),("Capitol","5:12p"),("Blossom Hill","5:18p"),("Morgan Hill","5:31p"),("San Martin","5:38p"),("Gilroy","5:49p")],
"820": [("San Jose Diridon","6:01p"),("Tamien","6:06p"),("Capitol","6:12p"),("Blossom Hill","6:18p"),("Morgan Hill","6:31p"),("San Martin","6:38p"),("Gilroy","6:49p")],
"822": [("San Jose Diridon","6:23p"),("Tamien","6:28p"),("Capitol","6:34p"),("Blossom Hill","6:40p"),("Morgan Hill","6:53p"),("San Martin","7:00p"),("Gilroy","7:11p")],
}
for num, stops in sb_scc.items():
    for st, t in stops:
        add_stop(num, "S", st, t)

# ----------------------------------------------------------------------------
# Assemble + validate
# ----------------------------------------------------------------------------
out_trains = []
problems = []
for num, tr in trains.items():
    stops = tr["stops"]
    # order stops by physical position along the line in travel direction
    if tr["dir"] == "N":
        ordered = sorted(stops.items(), key=lambda kv: -ORDER[kv[0]])  # south->north
    else:
        ordered = sorted(stops.items(), key=lambda kv: ORDER[kv[0]])   # north->south
    # day-wrap: make minutes monotonically increasing
    mins = []
    prev = None
    for st, m in ordered:
        mm = m
        if prev is not None and mm < prev:
            mm += 24 * 60
        mins.append(mm)
        prev = mm
    # validate monotonic
    for i in range(1, len(mins)):
        if mins[i] <= mins[i - 1]:
            problems.append(f"train {num} ({tr['dir']}): non-increasing at {ordered[i][0]}")
    out_trains.append({
        "id": num,
        "direction": "NB" if tr["dir"] == "N" else "SB",
        "type": tr["type"],
        "stops": [{"station": st, "min": m} for (st, _), m in zip(ordered, mins)],
    })

out_trains.sort(key=lambda t: (t["direction"], t["stops"][0]["min"]))

schedule = {
    "source": "Caltrain printer-friendly weekday timetable, effective January 27, 2025",
    "service": "weekday",
    "stations": STATIONS,
    "transferStation": "San Jose Diridon",
    "trains": out_trains,
}

with open("schedule.json", "w") as f:
    json.dump(schedule, f, indent=1)

print(f"trains: {len(out_trains)}  (NB {sum(1 for t in out_trains if t['direction']=='NB')}, "
      f"SB {sum(1 for t in out_trains if t['direction']=='SB')})")
print("problems:", len(problems))
for p in problems:
    print("  ", p)

# quick sanity prints
def show(num):
    t = next(t for t in out_trains if t["id"] == num)
    def fmt(m):
        m %= 24*60
        h, mn = divmod(m, 60); ap = "a" if h < 12 else "p"
        h12 = h % 12 or 12
        return f"{h12}:{mn:02d}{ap}"
    print(f"\nTrain {num} [{t['type']} {t['direction']}]")
    print("  " + ", ".join(f"{s['station']} {fmt(s['min'])}" for s in t["stops"]))

for n in ["805","109","814","146","101","176"]:
    show(n)
