import Foundation

// MARK: - Time zone

/// Caltrain runs on Pacific time, and the schedule's minute-of-day values are
/// Pacific wall-clock. Do every wall-clock calculation against this fixed zone
/// rather than the device's, so countdowns and the weekday/weekend default stay
/// correct even when the phone is set to another timezone.
enum CaltrainClock {
    static let timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
}

// MARK: - Data model (decoded from schedule.json)
// `// MARK:` is just a structured comment. Xcode shows MARK lines in its
// jump bar / minimap, like section headers. The leading "-" draws a divider.

// `Codable` is a protocol meaning "this type can be encoded to / decoded from"
// an external format such as JSON. The compiler auto-generates the conversion
// code as long as every stored property is itself Codable — no manual
// serialization boilerplate (contrast with hand-written to/from JSON in C++).
//
// Because this is a `struct`, it's a value type: copying a Schedule copies all
// its fields. `let` means immutable (like `const`); `var` means mutable.
struct Schedule: Codable {
    let source: String
    let services: [String]          // service modes present in the data
    let stations: [String]          // [String] is an array of String (std::vector<std::string>)
    let transferStation: String
    let trains: [Train]
}

/// Which timetable a rider is looking at. Caltrain publishes one weekday and
/// one weekend calendar (Saturday and Sunday service are identical), so these
/// two cases mirror the source data rather than being a simplification.
// `String` raw values match the strings in schedule.json, which is what lets
// Codable decode Train.service straight into this enum. `CaseIterable` gives
// us `.allCases` for building the picker.
enum ServiceDay: String, Codable, CaseIterable, Identifiable {
    case weekday, weekend

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekday: return "Weekday"
        case .weekend: return "Weekend"
        }
    }

    /// The mode matching a given date, used to pick a sensible initial value.
    static func forDate(_ date: Date) -> ServiceDay {
        // Caltrain's timetable is Sat/Sun, so read the Gregorian weekday number in
        // Caltrain's own timezone (not the device's locale/zone), which also keeps
        // the choice right for a phone set to a different timezone near midnight.
        let weekday = CaltrainClock.calendar.component(.weekday, from: date)
        return (weekday == 1 || weekday == 7) ? .weekend : .weekday   // 1 = Sun, 7 = Sat
    }
}

// `Identifiable` requires an `id` property. SwiftUI uses it to tell list items
// apart efficiently (so it knows which row changed). Here `id` doubles as the
// JSON-decoded train number, so we get Identifiable for free.
struct Train: Codable, Identifiable {
    let id: String            // train number, e.g. "805"
    let service: ServiceDay   // which timetable this train belongs to
    let direction: String     // "NB" or "SB"
    let type: String          // Local / Limited / Express / South County
    let stops: [Stop]
}

struct Stop: Codable {
    let station: String
    let min: Int            // minutes since midnight (may exceed 1440 for post-midnight)
}

// MARK: - Store

// `final class` — here we DO want a class (a reference type, shared not copied),
// because the store is a single shared source of truth. `final` means it can't
// be subclassed (helps the optimizer; similar intent to a non-virtual C++ class).
//
// `ObservableObject` lets SwiftUI watch this object. Combined with `@Published`
// below, any change to the schedule automatically notifies and re-renders the UI.
final class ScheduleStore: ObservableObject {
    // `@Published` broadcasts a change notification whenever this value is set.
    // `private(set)` means: readable everywhere, but only settable inside this
    // class (public getter, private setter — a common C++ pattern done in one word).
    @Published private(set) var schedule: Schedule

    /// position of each station along the line, 0 = San Francisco … N = Gilroy
    /// `[String: Int]` is a dictionary (std::unordered_map<std::string,int>).
    /// `= [:]` is an empty-dictionary literal.
    /// Triple-slash `///` is a documentation comment (shows in Xcode's Quick Help).
    private(set) var order: [String: Int] = [:]

    /// trains bucketed by timetable, so a search scans only the relevant ones
    private var trainsByService: [ServiceDay: [Train]] = [:]

    // `init` is the constructor. Stored properties must all be initialized by the
    // time init finishes (the compiler enforces this).
    init() {
        // `Self` (capital S) means "this type" — calls the static method below.
        self.schedule = Self.loadFromBundle()
        var o: [String: Int] = [:]
        // `.enumerated()` yields (index, element) pairs; we destructure into (i, s).
        // This is the idiomatic Swift "for index, value" loop.
        for (i, s) in schedule.stations.enumerated() { o[s] = i }
        self.order = o
        // Group once at load rather than filtering on every keystroke — the
        // trip finder walks the train list three times per search.
        self.trainsByService = Dictionary(grouping: schedule.trains, by: \.service)
    }

    // Computed properties: these run their getter on each access; they expose
    // bits of `schedule` read-only. No parentheses because they take no args.
    var stations: [String] { schedule.stations }
    var transferStation: String { schedule.transferStation }

    /// Trains running on the given timetable.
    func trains(for service: ServiceDay) -> [Train] { trainsByService[service] ?? [] }

    /// Stations any train calls at on the given timetable. The Gilroy branch is
    /// weekday-only, so the weekend station list is genuinely shorter.
    func stations(for service: ServiceDay) -> [String] {
        let served = Set(trains(for: service).flatMap { $0.stops.map(\.station) })
        return schedule.stations.filter(served.contains)
    }

    // `static` = belongs to the type, not an instance (like a C++ static method).
    private static func loadFromBundle() -> Schedule {
        // `guard ... else { }` is "verify or bail". If any binding fails, the
        // else block runs and must exit scope. It's like an early-return guard
        // clause, but the unwrapped values (url, data, decoded) stay in scope
        // *after* the guard — that's the key difference from `if let`.
        guard
            // Bundle.main is the app's read-only resource folder (its files).
            let url = Bundle.main.url(forResource: "schedule", withExtension: "json"),
            // `try?` turns a throwing call into an Optional: nil on error instead
            // of propagating an exception. (Swift uses typed error handling, not
            // C++ exceptions; `try?` is the "I just want nil on failure" shortcut.)
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Schedule.self, from: data)
        else { fatalError("schedule.json missing or unreadable in app bundle") }  // hard crash; like assert+abort
        return decoded
    }
}

// MARK: - Trip results

struct TripLeg: Identifiable {
    // Identity must be derived from the leg's *content*, not a fresh `UUID()`.
    // `trips` is recomputed on every `body` pass (the 30s countdown ticker forces
    // one), so a per-instance UUID changed each tick — SwiftUI then saw every card
    // as brand new and reset its expanded/collapsed state. A train serves a given
    // origin→dest once per run, so trainID + times is a stable, unique key.
    var id: String { "\(trainID)|\(depart.min)|\(arrive.min)" }
    let trainID: String
    let type: String
    let direction: String
    let depart: Stop
    let arrive: Stop
    let allStops: [Stop]    // every stop this train makes, in travel order
}

struct Trip: Identifiable {
    // Stable, content-derived id for the same reason as TripLeg (see above): the
    // legs' ids uniquely identify the whole itinerary within a result set.
    var id: String { legs.map(\.id).joined(separator: ">") }
    let legs: [TripLeg]
    // More computed properties. `legs.first!` returns the first element; the `!`
    // force-unwraps the Optional (we're certain a trip has >=1 leg). A force
    // unwrap crashes if it's actually nil — use only when you're sure, like
    // dereferencing a pointer you know is non-null.
    var departMin: Int { legs.first!.depart.min }
    var arriveMin: Int { legs.last!.arrive.min }
    var isTransfer: Bool { legs.count > 1 }
}

// MARK: - Trip finder

// A small value-type struct that bundles the search logic with the store it
// reads from. Stored `let` properties below act like compile-time constants.
struct TripFinder {
    let store: ScheduleStore
    let minTransfer = 3      // minutes; Caltrain advertises timed transfers at Diridon
    let maxTransferWait = 90 // minutes

    /// Find upcoming trips from `origin` to `dest`, departing within `windowMin`
    /// of `nowMin` (minutes since midnight). Falls back to one transfer at the
    /// transfer station when there is no direct service.
    // Note Swift's argument labels: callers write find(origin:dest:nowMin:windowMin:).
    // These labels are part of the function's name and improve call-site readability.
    func find(origin: String, dest: String, nowMin: Int, windowMin: Int,
              service: ServiceDay) -> [Trip] {
        // Multi-condition guard: bail out early if origin == dest, or if either
        // station isn't in the `order` map. Dictionary lookup returns an Optional
        // (the key might be absent), and `let oi = ...` unwraps it.
        guard origin != dest,
              let oi = store.order[origin], let di = store.order[dest] else { return [] }
        let goingSouth = di > oi
        // Ternary, same as C++: condition ? a : b
        let wantDir = goingSouth ? "SB" : "NB"
        // Every leg below searches only this timetable's trains, so a weekday
        // train can never be spliced onto a weekend one at the transfer.
        let candidateTrains = store.trains(for: service)

        // ---- direct trains ----
        var direct: [Trip] = []
        // `for t in ... where <cond>` filters inline — only iterations where the
        // condition holds run the body. Cleaner than an `if` at the top of a loop.
        for t in candidateTrains where t.direction == wantDir {
            // Guard that this train actually serves both stations, in the right
            // order. `stop(t, origin)` returns Stop? (Optional); we unwrap dep/arr.
            // `indexOf(...)!` force-unwraps because, having passed `stop()`, we
            // know the index exists.
            guard let dep = stop(t, origin), let arr = stop(t, dest),
                  indexOf(origin, in: t)! < indexOf(dest, in: t)! else { continue }
            // Construct a Trip with one leg and append it. `direct` is `var` so
            // it's mutable; mutating a struct array in place is fine here.
            direct.append(Trip(legs: [TripLeg(trainID: t.id, type: t.type,
                direction: t.direction, depart: dep, arrive: arr, allStops: t.stops)]))
        }
        let directWindowed = withinWindow(direct, nowMin: nowMin, windowMin: windowMin)
        // If this route has direct service at all, only ever show direct trips: an
        // empty window means "nothing soon", not "go build a transfer". Falling back
        // on an empty *window* (rather than genuinely no direct service) is what
        // produced wrong-way trips for station pairs on the same side of Diridon.
        if !direct.isEmpty { return directWindowed }

        // ---- one transfer via the transfer station (San Jose Diridon) ----
        // Only worthwhile when the transfer station actually lies *between* origin
        // and dest; otherwise the two-seat ride would backtrack past one of them.
        let xfer = store.transferStation
        guard origin != xfer, dest != xfer,
              let xi = store.order[xfer],
              (oi < xi && xi < di) || (di < xi && xi < oi)
        else { return directWindowed }

        // leg 1: origin -> transfer
        let leg1Dir = (xi > oi) ? "SB" : "NB"
        var leg1s: [TripLeg] = []
        for t in candidateTrains where t.direction == leg1Dir {
            guard let dep = stop(t, origin), let arr = stop(t, xfer),
                  indexOf(origin, in: t)! < indexOf(xfer, in: t)! else { continue }
            leg1s.append(TripLeg(trainID: t.id, type: t.type, direction: t.direction,
                depart: dep, arrive: arr, allStops: t.stops))
        }
        // leg 2: transfer -> dest
        let leg2Dir = (di > xi) ? "SB" : "NB"
        var leg2s: [TripLeg] = []
        for t in candidateTrains where t.direction == leg2Dir {
            guard let dep = stop(t, xfer), let arr = stop(t, dest),
                  indexOf(xfer, in: t)! < indexOf(dest, in: t)! else { continue }
            leg2s.append(TripLeg(trainID: t.id, type: t.type, direction: t.direction,
                depart: dep, arrive: arr, allStops: t.stops))
        }

        var trips: [Trip] = []
        for l1 in leg1s {
            // earliest feasible connection
            // `.compactMap` maps each element AND drops the nils in one pass
            // (a transform + filter). The closure returns `(Int, TripLeg)?` —
            // an Optional tuple — so returning nil discards that candidate.
            // `$0` is the closure's first (here only) argument; we name it `l2`
            // explicitly via `l2 ->` for clarity.
            let candidates = leg2s.compactMap { l2 -> (Int, TripLeg)? in
                var wait = l2.depart.min - l1.arrive.min
                if wait < 0 { wait += 1440 }   // wrap past midnight (1440 min/day)
                return (wait >= minTransfer && wait <= maxTransferWait) ? (wait, l2) : nil
            }.sorted { $0.0 < $1.0 }            // sort by wait (tuple's .0 element), ascending
            // `if let best = candidates.first` runs the body only if there's a
            // first element (i.e. the array isn't empty); `best` is non-Optional inside.
            if let best = candidates.first {
                trips.append(Trip(legs: [l1, best.1]))  // best.1 = the TripLeg in the tuple
            }
        }
        return withinWindow(trips, nowMin: nowMin, windowMin: windowMin)
    }

    // keep trips whose first departure falls within the window, nearest-to-now first.
    // window may be negative, which includes trains that already departed.
    private func withinWindow(_ trips: [Trip], nowMin: Int, windowMin: Int) -> [Trip] {
        // The leading `_` in the parameter list means "no argument label" — callers
        // pass this argument positionally (withinWindow(trips, ...)).
        let lo = min(0, windowMin)
        let hi = max(0, windowMin)
        return trips.compactMap { trip -> (Int, Trip)? in
            // signed minutes from now: negative = already departed
            var d = minutesUntil(trip.departMin, from: nowMin)
            if d > 720 { d -= 1440 }
            // `(lo...hi)` is a ClosedRange; `.contains(d)` checks lo <= d <= hi.
            return (lo...hi).contains(d) ? (d, trip) : nil
        }
        // ascending signed offset: soonest-first when positive,
        // longest-ago-first when the window is negative
        .sorted { $0.0 < $1.0 }   // sort by the Int (offset); `$0`/`$1` are the two items being compared
        .map { $0.1 }             // keep only the Trip, dropping the offset we sorted by
    }

    // MARK: helpers
    // `.first { predicate }` returns the first element matching the closure, or
    // nil — hence the Optional return type `Stop?`. Like std::find_if but it
    // returns the value (Optional), not an iterator.
    private func stop(_ t: Train, _ station: String) -> Stop? {
        t.stops.first { $0.station == station }
    }
    private func indexOf(_ station: String, in t: Train) -> Int? {
        t.stops.firstIndex { $0.station == station }
    }
    /// minutes from `now` until `target`, treating the schedule as repeating daily
    func minutesUntil(_ target: Int, from now: Int) -> Int {
        // Positive modulo trick: Swift's % can return negative results for
        // negative operands (like C++), so we add 1440 and mod again to force
        // the answer into 0...1439.
        ((target % 1440) - (now % 1440) + 1440) % 1440
    }
}

// MARK: - Time formatting

// `enum` with only static functions used as a namespace — a common Swift idiom.
// Unlike a struct, an enum with no cases can't be instantiated, so it's a clean
// "bag of related functions" (similar to a C++ namespace or a class of statics).
/// Granularity of the "At time" departure picker.
// A caseless enum used purely as a namespace for statics — the same trick
// TimeFmt below uses. Because it has no cases it can never be instantiated.
enum TimeStep {
    static let minutes = 15

    /// Rounds a minute-of-day to the nearest step, wrapping across midnight.
    static func snap(_ minute: Int) -> Int {
        let m = ((minute % 1440) + 1440) % 1440
        // Integer division truncates, so add half a step first to round to
        // nearest rather than always down. 23:53 rounds up to 1440, which the
        // final modulo wraps back to 00:00.
        let rounded = ((m + minutes / 2) / minutes) * minutes
        return rounded % 1440
    }
}

enum TimeFmt {
    static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        let h = m / 60, mm = m % 60
        let ap = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        // String(format:) works like printf. %@ is the placeholder for an
        // Objective-C/Swift object (here the "AM"/"PM" String).
        return String(format: "%d:%02d %@", h12, mm, ap)
    }
    static func duration(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        // "\(m)" is string interpolation — embeds the value of `m` in the literal
        // (like std::format("{} min", m)).
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }
    static func nowMinutes() -> Int {
        minutes(from: Date())   // Date() is "now" (like std::chrono::system_clock::now()).
    }
    static func minutes(from date: Date) -> Int {
        // Read the hour/minute in Caltrain's timezone so "now" is comparable to the
        // schedule's Pacific times regardless of the device's own timezone.
        let c = CaltrainClock.calendar.dateComponents([.hour, .minute], from: date)
        // `c.hour` is Optional (the component might be absent); `?? 0` is the
        // nil-coalescing operator: "use c.hour, or 0 if it's nil" (like value_or).
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
