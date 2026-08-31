import SwiftUI
import Combine   // provides Timer.publish (the 30-second ticker below)

// A SwiftUI View is a *description* of UI, not the UI itself. You don't mutate
// widgets imperatively (no `label.setText(...)`). Instead you declare what the
// screen should look like *given the current state*, and when state changes
// SwiftUI re-runs `body` and diffs the result against what's on screen. Views
// are structs (cheap value types) created and thrown away constantly.
struct ContentView: View {
    // `@EnvironmentObject` pulls a shared object that an ancestor injected via
    // `.environmentObject(...)` (see CaltrainUpcomingApp). No need to pass it
    // through every initializer — it's looked up from the environment.
    @EnvironmentObject var store: ScheduleStore

    // persisted across launches
    // `@AppStorage("key")` is a property wrapper backed by UserDefaults (a tiny
    // built-in key/value store, like a registry/plist). Reading gives the saved
    // value; assigning persists it automatically AND re-renders the view. The
    // string is the storage key; the right-hand side is the default if unset.
    @AppStorage("originStation") private var origin = "Blossom Hill"
    @AppStorage("destStation")   private var dest   = "Sunnyvale"
    @AppStorage("lookAheadMinutes") private var window: Double = 45

    // `@State` is view-local mutable state owned by SwiftUI. When you assign to
    // it, SwiftUI re-renders. Use it for transient UI state (not persisted).
    // `picking` is an Optional enum: nil = no sheet shown, non-nil = which field.
    @State private var nowMin = TimeFmt.nowMinutes()
    @State private var picking: StationField?

    // departure time: search from "now" or from a saved time-of-day
    @AppStorage("departMode") private var departMode: DepartMode = .now
    @AppStorage("pickedMinutes") private var pickedMinutes = 8 * 60

    // which timetable to search. Not persisted: on launch it should follow
    // today's date rather than whatever the rider last browsed, so the default
    // is computed here and only overridden for the current session.
    @State private var service = ServiceDay.forDate(Date())
    // Whether the rider has overridden the service day this session. Until they do,
    // the default keeps following the calendar — so an app left open across
    // midnight into the weekend switches instead of showing stale weekday service.
    @State private var userChoseService = false

    // refresh the relative times every 30s
    // A Combine publisher that fires every 30s on the main thread. `.autoconnect()`
    // starts it automatically. We subscribe to it with `.onReceive` in `body`.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // Computed property returning a fresh finder each access. Cheap because
    // TripFinder is a small struct that just holds a reference to the store.
    private var finder: TripFinder { TripFinder(store: store) }
    /// minute-of-day the search starts from
    private var baseMin: Int {
        departMode == .now ? nowMin : pickedMinutes
    }
    /// bridges the stored minutes-of-day to the DatePicker's Date binding
    // A `Binding<Date>` is a two-way reference: a getter + setter pair that lets
    // a child control (DatePicker) read and write our state. Here we synthesize
    // one that converts between our Int "minutes since midnight" and a Date.
    private var pickedTimeBinding: Binding<Date> {
        Binding(
            get: {
                // Snap on the way out too: a value stored by an older build (or
                // restored from @AppStorage) may not sit on a step boundary, and
                // the wheel can't display a position it has no row for.
                let snapped = TimeStep.snap(pickedMinutes)
                // Build a Date for today at the stored hour/minute, interpreted in
                // Caltrain's timezone to match how `minutes(from:)` reads it back.
                // The call returns Date?; `?? Date()` falls back to now if it's nil.
                return CaltrainClock.calendar.date(bySettingHour: snapped / 60,
                                                   minute: snapped % 60, second: 0, of: Date()) ?? Date()
            },
            // $0 = the new Date the picker wrote. We snap here rather than trust
            // the UIDatePicker appearance proxy — it's a global default that a
            // future iOS could stop honoring, and this keeps the stored value
            // correct either way.
            set: { pickedMinutes = TimeStep.snap(TimeFmt.minutes(from: $0)) }
        )
    }
    // Re-runs the search whenever any input it reads (origin, dest, baseMin,
    // window) changes — because those are @State/@AppStorage, SwiftUI knows to
    // recompute `trips` and rebuild the views that use it.
    private var trips: [Trip] {
        finder.find(origin: origin, dest: dest, nowMin: baseMin,
                    windowMin: Int(window), service: service)
    }

    /// True when the chosen route can't work on this timetable at all — as
    /// opposed to simply having no departure in the look-ahead window. The
    /// Gilroy branch (Blossom Hill, Gilroy, …) is weekday-only, so this is
    /// reachable with the app's own default route.
    private var unservedOnThisDay: [String] {
        let served = Set(store.stations(for: service))
        return [origin, dest].filter { !served.contains($0) }
    }

    /// "Schedule updated 2 hr ago", or a note that the built-in copy is in use.
    private var scheduleStatusText: String {
        guard let d = store.lastUpdated else { return "Using built-in schedule" }
        let f = DateFormatter()
        // Absolute "updated at" time of the last reload: just the clock time when
        // it happened today, with the date prepended otherwise.
        f.dateFormat = Calendar.current.isDateInToday(d)
            ? "'Downloaded local schedule at' h:mm a"          // e.g. "Updated at 6:01 PM"
            : "'Downloaded local schedule at' MMM d 'at' h:mm a"  // e.g. "Updated Aug 29 at 5:30 PM"
        return f.string(from: d)
    }

    /// The author's "schedule last updated" date, from the file's `generatedAt`
    /// stamp, formatted for display. nil if the file predates the field.
    private var scheduleDataDateText: String? {
        guard let iso = store.schedule.generatedAt else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = CaltrainClock.timeZone
        guard let date = parser.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateStyle = .medium   // e.g. "Aug 30, 2026"
        return out.string(from: date)
    }

    /// Footer at the bottom of the screen: any update error, the schedule status,
    /// and the app version.
    @ViewBuilder private var scheduleFooter: some View {
        VStack(spacing: 2) {
            if let error = store.updateError {
                Text(error).foregroundStyle(.orange)
            }
            if let dataDate = scheduleDataDateText {
                Text("Schedule built by author on \(dataDate)")
            }
            Text(scheduleStatusText)
            Text("v\(AppInfo.version)")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// Nav-bar button that pulls the latest schedule; shows a spinner while it runs.
    @ViewBuilder private var refreshButton: some View {
        Button {
            Task { await store.reload() }
        } label: {
            if store.isUpdating {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.isUpdating)
        .accessibilityLabel("Update schedule")
    }

    // `body` describes the whole screen. It's recomputed on every state change.
    var body: some View {
        // NavigationStack provides the title bar and lets us present sheets/pushes.
        NavigationStack {
            // ScrollView makes its content scrollable when it overflows.
            ScrollView {
                // VStack = vertical stack (children top-to-bottom). HStack/ZStack
                // are the horizontal/overlay equivalents. `spacing:` sets the gap.
                // Inside a stack's `{ }` you just list child views — this is a
                // "view builder", a special closure where each line is a subview.
                VStack(spacing: 16) {
                    routeCard
                    serviceCard
                    departCard
                    windowCard
                    resultsSection
                    linksCard
                    scheduleFooter
                }
                .padding()   // a "modifier": returns a new view wrapping this one
                             // with padding. Modifiers chain, applying outward.
            }
            .background(Color(.systemGroupedBackground))
            // Pull down anywhere on the list to fetch the latest schedule.
            .refreshable { await store.reload() }
            .navigationBarTitleDisplayMode(.inline)
            // A visible refresh control too, for discoverability.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { refreshButton }
            }
            // `.sheet(item:)` presents a modal when `picking` becomes non-nil.
            // `$picking` passes a *Binding* (the `$` projects the wrapped value's
            // binding) so the sheet can set it back to nil on dismiss. The closure
            // receives the unwrapped value as `field`.
            .sheet(item: $picking) { field in
                StationPicker(
                    title: field == .origin ? "From" : "To",
                    // Only offer stations with service on the chosen timetable, so
                    // the picker never lists a station that can't return a result
                    // (e.g. the weekday-only Gilroy branch while on Weekend).
                    stations: store.stations(for: service),
                    selected: field == .origin ? origin : dest
                ) { chosen in   // trailing closure = the onPick callback
                    if field == .origin { origin = chosen } else { dest = chosen }
                    picking = nil
                }
            }
        }
        // Subscribe to the ticker; each tick updates nowMin, refreshing countdowns,
        // and re-follows the calendar's service day unless the rider overrode it.
        .onReceive(ticker) { _ in
            nowMin = TimeFmt.nowMinutes()
            if !userChoseService {
                let today = ServiceDay.forDate(Date())
                if service != today { service = today }
            }
        }
        .onAppear { nowMin = TimeFmt.nowMinutes() }                 // runs when the view appears
    }

    // MARK: route selector

    // Breaking `body` into smaller computed view properties keeps it readable.
    // Each returns `some View`. They're not cached — recomputed when used.
    private var routeCard: some View {
        HStack(spacing: 12) {
            // Calls the helper below. The trailing `{ picking = .origin }` is the
            // button's action closure.
            stationButton(label: "From", value: origin) { picking = .origin }
            Button {
                // swap origin and dest via a temporary
                let o = origin; origin = dest; dest = o
            } label: {
                // SF Symbols: Apple's built-in icon set, referenced by name.
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Swap start and destination")  // for VoiceOver
            stationButton(label: "To", value: dest) { picking = .destination }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // A function that returns a view. `@escaping () -> Void` is the action: a
    // closure taking no args, returning nothing (like std::function<void()>).
    // "@escaping" means the closure is stored and called later (after this
    // function returns), so Swift needs to know it outlives the call.
    private func stationButton(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    // fixedSize(vertical) lets the text grow tall enough to wrap
                    // instead of being truncated.
                    .fixedSize(horizontal: false, vertical: true)
            }
            // `maxWidth: .infinity` makes each button expand to share the row width.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: departure time

    // MARK: service day

    private var serviceCard: some View {
        HStack(spacing: 10) {
            Text("Service").font(.subheadline.weight(.medium))
            // Custom binding so a manual pick sets `userChoseService`, which stops
            // the ticker from auto-following the date over the top of their choice.
            Picker("Service", selection: Binding(
                get: { service },
                set: { service = $0; userChoseService = true }
            )) {
                // Build one segment per case instead of listing them by hand, so
                // adding a mode later (holiday service) needs no change here.
                ForEach(ServiceDay.allCases) { day in
                    Text(day.label).tag(day)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var departCard: some View {
        HStack(spacing: 10) {
            Text("Depart").font(.subheadline.weight(.medium))
            // A Picker bound to `departMode`. `$departMode` is the two-way binding.
            // Each option's `.tag(...)` is the value selected when that row is chosen.
            Picker("Depart", selection: $departMode) {
                Text("Now").tag(DepartMode.now)
                Text("At time").tag(DepartMode.at)
            }
            .pickerStyle(.segmented)   // render as a segmented control
            .fixedSize()               // size to content rather than stretching
            // Conditional view: the DatePicker only exists when mode is `.at`.
            // `if` inside a view builder includes/excludes subtrees.
            if departMode == .at {
                DatePicker("Departure time", selection: pickedTimeBinding,
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Spacer(minLength: 0)   // pushes everything to the left
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: window slider

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Look ahead").font(.subheadline.weight(.medium))
                Spacer()   // flexible gap, pushing the label to the trailing edge
                // Chained ternary chooses the label text for negative/zero/positive.
                Text(window == 0 ? "now"
                     : window > 0 ? "next \(Int(window)) min"
                     : "last \(Int(-window)) min")
                    .font(.subheadline.monospacedDigit())  // digits don't shift width
                    .foregroundStyle(.secondary)
            }
            // Slider bound to `window`. `in:` is the range; `step:` the increment.
            // Editing the slider writes `window`, which re-runs `trips`.
            Slider(value: $window, in: -90...90, step: 5)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: results

    // `@ViewBuilder` lets this property contain branching (if/else) that each
    // returns a *different* view type. Without it, a computed `some View` would
    // have to return one concrete type. The builder wraps the branches for you.
    @ViewBuilder private var resultsSection: some View {
        if trips.isEmpty {
            emptyState
        } else {
            // `let` bindings are allowed inside a ViewBuilder. `.map` transforms
            // each trip into its duration; `.min()`/`.max()` return Optionals
            // (empty array → nil), so `?? 0` provides a fallback.
            let durations = trips.map { finder.minutesUntil($0.arriveMin, from: $0.departMin) }
            let fastest = durations.min() ?? 0
            let slowest = durations.max() ?? 0
            VStack(spacing: 12) {
                // `ForEach` builds one view per element. It needs each element to
                // be Identifiable (Trip has an `id`) so SwiftUI can track rows.
                // This is a SwiftUI view, distinct from the plain `for` loop.
                ForEach(trips) { trip in
                    // Pass fastest/slowest so each card can color itself relative
                    // to the whole set.
                    TripCard(trip: trip, nowMin: baseMin, showCountdown: departMode == .now,
                             finder: finder, origin: origin, dest: dest,
                             fastestMin: fastest, slowestMin: slowest)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram").font(.largeTitle).foregroundStyle(.secondary)
            // Distinguish "nothing in this window" from "this station has no
            // service at all today" — widening the window can't fix the latter,
            // so suggesting it would send the rider in circles.
            if !unservedOnThisDay.isEmpty {
                // ListFormatter-free join: at most two stations, so this reads fine.
                let names = unservedOnThisDay.joined(separator: " and ")
                Text("\(names) has no \(service.label.lowercased()) service")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("The Gilroy branch runs weekdays only. Switch to \(ServiceDay.weekday.label) or pick another station.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                // String interpolation pulls live values into the message.
                Text("No trains from \(origin) to \(dest) in the next \(Int(window)) min")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Try widening the time window or swapping stations.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: caltrain.com links

    // Two buttons that open caltrain.com in the browser.
    private var linksCard: some View {
        HStack(spacing: 12) {
            linkButton(title: "Schedules",
                       systemImage: "tablecells",
                       url: "https://www.caltrain.com/schedules/pdfs?active_tab=route_explorer_tab")
            linkButton(title: "Service Alerts",
                       systemImage: "exclamationmark.triangle",
                       url: "https://www.caltrain.com/schedules/pdfs?active_tab=service_alerts_tab")
        }
    }

    // `Link` is a built-in view that opens a URL in the default browser when
    // tapped — no manual UIApplication.open needed. `URL(string:)` returns an
    // Optional (the string could be malformed); we force-unwrap with `!` because
    // these literals are known-good. The trailing closure is the button's label.
    private func linkButton(title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).font(.subheadline.weight(.semibold))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                // small "opens externally" hint icon
                Image(systemName: "arrow.up.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)   // each button shares the row width evenly
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .tint(.primary)   // use normal text color instead of the default link blue
    }

    // Nested enums, scoped to ContentView. `: Int` gives raw integer values;
    // `Identifiable` requires `id`, which we derive from `rawValue`. This enum is
    // what `picking` holds to remember which field's picker to show.
    enum StationField: Int, Identifiable { case origin, destination; var id: Int { rawValue } }
    // `: String` makes each case's raw value its own name ("now"/"at"), which is
    // what @AppStorage persists.
    enum DepartMode: String { case now, at }
}

// MARK: - Trip card

// A reusable child view. It receives its data through stored properties; SwiftUI
// re-initializes it (cheap) whenever the parent re-renders with new values.
struct TripCard: View {
    // `let` properties with no default are required init parameters. Swift
    // auto-generates the memberwise initializer for structs — no constructor to
    // write by hand. Callers pass them by label: TripCard(trip:, nowMin:, ...).
    let trip: Trip
    let nowMin: Int
    var showCountdown: Bool = true   // `var` + default value = optional argument
    let finder: TripFinder
    let origin: String
    let dest: String
    /// fastest / slowest ride length across all shown trips, for color-coding
    var fastestMin: Int = 0
    var slowestMin: Int = 0
    // Per-card local state: whether the stop list is expanded. @State persists
    // across re-renders of this card (SwiftUI keeps it tied to the card's identity).
    @State private var expanded = false

    // Signed minutes until departure: negative means the train already left.
    private var minsAway: Int {
        var d = finder.minutesUntil(trip.departMin, from: nowMin)
        if d > 720 { d -= 1440 }   // negative = already departed
        return d
    }
    private var rideMin: Int { finder.minutesUntil(trip.arriveMin, from: trip.departMin) }
    /// The countdown split into three stacked lines: a small word above the
    /// number and the unit below it ("In" / "8" / "mins"). For a train that
    /// already left, the word moves underneath ("3" / "mins" / "ago"), so the
    /// number stays on the middle line in both cases and cards line up.
    /// A tuple return — Swift's built-in way to hand back several values.
    private var countdownParts: (above: String?, value: String, below: String?) {
        if minsAway == 0 { return (nil, "Now", nil) }
        let m = abs(minsAway)
        let unit = m == 1 ? "min" : "mins"
        return minsAway < 0 ? (nil, "\(m)", "\(unit) ago") : ("In", "\(m)", unit)
    }
    /// green for the fastest trip, red for the slowest, blended in between
    private var durationColor: Color {
        // If all trips are the same length (no spread), just show green.
        guard slowestMin > fastestMin else {
            return Color(hue: 0.33, saturation: 0.85, brightness: 0.75)
        }
        // `t` is 0 for the fastest trip, 1 for the slowest. We then interpolate
        // hue from 0.33 (green) down to 0.0 (red) — passing through yellow/orange.
        let t = Double(rideMin - fastestMin) / Double(slowestMin - fastestMin)
        return Color(hue: 0.33 * (1 - t), saturation: 0.85, brightness: 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tapping the header toggles `expanded`. `withAnimation` animates any
            // view changes caused by the state change inside its closure.
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                header
            }
            // Only build the detail section when expanded.
            if expanded {
                Divider().padding(.vertical, 10)
                // `.enumerated()` gives (index, leg); `Array(...)` makes it indexable
                // for ForEach. `id: \.offset` is a key path telling ForEach to use
                // the tuple's `offset` (the index) as the identity.
                ForEach(Array(trip.legs.enumerated()), id: \.offset) { idx, leg in
                    if idx > 0 { transferRow(before: trip.legs[idx-1], after: leg) }
                    LegStopsView(leg: leg, origin: origin, dest: dest)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // The collapsed row: countdown/clock on the left, times + train badges right.
    private var header: some View {
        HStack(spacing: 12) {
            // departure: live countdown, or clock time when searching a set time
            VStack(alignment: .leading, spacing: 1) {
                if showCountdown {
                    // Three stacked lines; the optional ones are omitted when nil.
                    // `if let` unwraps an Optional — the body runs only when it
                    // has a value, and `word` is the unwrapped String inside.
                    if let word = countdownParts.above {
                        Text(word).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(countdownParts.value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        // grey out trips that already departed (minsAway < 0)
                        .foregroundStyle(minsAway < 0 ? Color.secondary : Color.accentColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let word = countdownParts.below {
                        Text(word).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    // "At time" mode has no countdown to show, and the departure
                    // clock time is already in the depart → arrive row beside
                    // this column — so show ride length here instead of
                    // repeating it. Colored like the badge it replaces: green
                    // for the fastest trip on screen, red for the slowest.
                    Text(TimeFmt.duration(rideMin))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(durationColor)
                        .lineLimit(1)                                   // never wrap the duration...
                        .fixedSize(horizontal: true, vertical: false)   // ...size to fit it on one line
                    Text("ride").font(.caption2).foregroundStyle(.secondary)
                }
            }
            // Fixed column so cards align. The countdown stacks vertically now,
            // so this only has to fit "mins ago" and the "51 min" duration.
            .frame(width: 68, alignment: .leading)

            // A thin vertical divider line drawn as a 1pt-wide rectangle.
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    // depart → arrive clock times. `.monospacedDigit()` keeps digit
                    // widths equal; lineLimit+fixedSize keep each time on one line.
                    Text(TimeFmt.clock(trip.departMin))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(TimeFmt.clock(trip.arriveMin))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    // The color-coded duration badge (green=fast … red=slow).
                    // Only in countdown mode: otherwise the left column is
                    // already showing the duration and this would duplicate it.
                    if showCountdown {
                        Text(TimeFmt.duration(rideMin))
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(durationColor)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(durationColor.opacity(0.15), in: Capsule())  // pill behind the text
                    }
                }
                // train badges; an arrow between them denotes the transfer
                HStack(spacing: 6) {
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { i, leg in
                        if i > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        TypeBadge(type: leg.type, id: leg.trainID)
                    }
                }
            }
            Spacer(minLength: 4)
            // Chevron rotates 180° when expanded — `.rotationEffect` animates
            // because the toggle happened inside `withAnimation`.
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        // Makes the whole row (including empty areas) tappable, not just the text.
        .contentShape(Rectangle())
    }

    // A helper returning the "Transfer at X · N min wait" row between two legs.
    // Note it's a function (takes params) rather than a computed property.
    private func transferRow(before: TripLeg, after: TripLeg) -> some View {
        // Positive-modulo wait time across midnight.
        let wait = ((after.depart.min - before.arrive.min) % 1440 + 1440) % 1440
        // `return` is required here because the body has a statement (the `let`)
        // before the view — so it's not a single-expression body.
        return HStack(spacing: 8) {
            Image(systemName: "figure.walk").font(.caption)
            Text("Transfer at \(before.arrive.station) · \(wait) min wait")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.vertical, 6)
    }
}

// A small reusable badge showing a train's type (color + 3-letter code) and number.
struct TypeBadge: View {
    let type: String
    let id: String

    // Computed property mapping the type string to a color. `switch` in Swift
    // must be exhaustive; `default` covers the rest (here, "Local").
    private var color: Color {
        switch type {
        case "Express": return .red
        case "Limited": return .indigo
        case "South County Connector": return .teal
        default: return .blue            // Local
        }
    }
    /// fixed-width 3-letter code so every badge is the same size
    private var code: String {
        switch type {
        case "Express": return "EXP"
        case "Limited": return "LTD"
        case "South County Connector": return "SCC"
        default: return "LOC"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(code)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(color, in: RoundedRectangle(cornerRadius: 4))
            Text("#\(id)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.leading, 3).padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
        // `.overlay` draws another view on top; here a faint outline stroke.
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
        .fixedSize()
    }
}

// MARK: - All stops for a leg

// The expanded detail: lists each stop on one leg with a dot + time.
struct LegStopsView: View {
    let leg: TripLeg
    let origin: String
    let dest: String

    // Index of the boarding stop within the train's full stop list. `firstIndex`
    // returns Int?; `?? 0` falls back to the start if not found.
    private var fromIdx: Int { leg.allStops.firstIndex { $0.station == leg.depart.station } ?? 0 }
    private var toIdx: Int { leg.allStops.firstIndex { $0.station == leg.arrive.station } ?? leg.allStops.count - 1 }
    /// only the stops actually travelled on this leg (boarding → alighting)
    private var routeStops: [Stop] {
        // Validate the range before slicing to avoid an out-of-bounds crash.
        guard fromIdx <= toIdx, toIdx < leg.allStops.count else { return leg.allStops }
        // `a[x...y]` is a range subscript (inclusive). It yields an ArraySlice,
        // so we wrap it in `Array(...)` to get a fresh [Stop].
        return Array(leg.allStops[fromIdx...toIdx])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TypeBadge(type: leg.type, id: leg.trainID)
                Text(leg.direction == "NB" ? "Northbound" : "Southbound")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(Array(routeStops.enumerated()), id: \.offset) { idx, stop in
                // First and last stops are emphasized (bigger dot, bold text).
                let isEnd = idx == 0 || idx == routeStops.count - 1
                HStack(spacing: 10) {
                    Circle()
                        .fill(isEnd ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(width: isEnd ? 10 : 7, height: isEnd ? 10 : 7)
                        .frame(width: 14)   // outer fixed width keeps dots aligned
                    Text(stop.station)
                        .font(.subheadline)
                        .fontWeight(isEnd ? .semibold : .regular)
                    Spacer()
                    Text(TimeFmt.clock(stop.min))
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(isEnd ? .semibold : .regular)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Station picker

// The modal sheet for choosing a station, with a search field.
struct StationPicker: View {
    let title: String
    let stations: [String]
    let selected: String
    // `(String) -> Void` is a callback the parent passes in: "call me with the
    // chosen station". This is how a child communicates results upward.
    let onPick: (String) -> Void
    @State private var query = ""
    // `@Environment(\.dismiss)` reads a built-in action from the environment that
    // closes the sheet. `\.dismiss` is a key path into the environment values.
    @Environment(\.dismiss) private var dismiss

    // Starred stations, persisted across launches and shared by both pickers
    // (From and To) because they read the same @AppStorage key. @AppStorage only
    // stores plain values, not a Set, so we keep one newline-joined string and
    // convert at the edges — station names never contain newlines.
    @AppStorage("favoriteStations") private var favoritesRaw = ""

    private var favorites: Set<String> {
        Set(favoritesRaw.split(separator: "\n").map(String.init))
    }
    private func toggleFavorite(_ s: String) {
        var f = favorites
        // `insert`/`remove` on a Set are the same idea as std::set's.
        if f.contains(s) { f.remove(s) } else { f.insert(s) }
        // Writing favoritesRaw republishes it, so the list re-sorts immediately.
        favoritesRaw = f.sorted().joined(separator: "\n")
    }

    // Filter the list by the search text. `localizedCaseInsensitiveContains`
    // does a user-friendly substring match.
    private var filtered: [String] {
        query.isEmpty ? stations
            : stations.filter { $0.localizedCaseInsensitiveContains(query) }
    }
    // Split the matches into the two sections. Each `filter` keeps the original
    // station order, so within a section the list stays in line order.
    private var favoriteMatches: [String] { filtered.filter { favorites.contains($0) } }
    private var otherMatches: [String] { filtered.filter { !favorites.contains($0) } }

    var body: some View {
        NavigationStack {
            // `List` is a scrollable, styled list (like UITableView). Here it
            // builds a row per filtered station; `id: \.self` uses the string
            // itself as the identity (fine because station names are unique).
            List {
                // Starred stations float to their own section at the top. The
                // section only exists when something matches, so an empty header
                // never shows up.
                if !favoriteMatches.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteMatches, id: \.self) { row($0) }
                    }
                }
                if !otherMatches.isEmpty {
                    // Unlabeled section when there are no favorites, so the
                    // plain list looks exactly as it did before.
                    Section(favoriteMatches.isEmpty ? "" : "All stations") {
                        ForEach(otherMatches, id: \.self) { row($0) }
                    }
                }
            }
            // Adds the search bar bound to `query`; editing it refilters the list.
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Toolbar with a Done button that dismisses the sheet.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // One station row: tapping the name picks the station, tapping the star
    // toggles the favorite. Two buttons in a single List row need an explicit
    // button style — the default makes the whole row one tap target, so the
    // star would also trigger the pick.
    private func row(_ s: String) -> some View {
        let isFavorite = favorites.contains(s)
        return HStack(spacing: 12) {
            Button {
                onPick(s)
            } label: {
                HStack {
                    Text(s).foregroundStyle(.primary)
                    Spacer()
                    // Checkmark next to the currently selected station.
                    if s == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
                .contentShape(Rectangle())   // whole width stays tappable
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(s)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Remove \(s) from favorites" : "Add \(s) to favorites")
        }
    }
}

// `#Preview` renders this view live in Xcode's canvas without running the full
// app. We hand it a fresh ScheduleStore via environmentObject, matching what the
// real app injects. Great for iterating on UI quickly.
#Preview {
    ContentView().environmentObject(ScheduleStore())
}
