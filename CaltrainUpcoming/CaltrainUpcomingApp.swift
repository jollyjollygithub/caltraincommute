import SwiftUI

// `@main` marks the program's entry point — like `int main()` in C++, except
// instead of writing the run loop yourself you hand SwiftUI a description of
// your app and it drives everything. There must be exactly one `@main` per app.
//
// `struct ... : App` means CaltrainUpcomingApp conforms to the `App` protocol.
// A "protocol" is Swift's version of a C++ abstract base class / interface:
// it lists requirements (here, a `body` property) that the type must provide.
// Note we use a `struct`, not a `class`. In Swift structs are value types
// (copied on assignment, like a C++ `struct`/value object), and SwiftUI builds
// almost everything out of them.
@main
struct CaltrainUpcomingApp: App {
    // `@StateObject` is a "property wrapper". Think of it as a smart member
    // variable: it owns the ScheduleStore for the whole life of the app and
    // makes sure SwiftUI rebuilds the UI when the store publishes a change.
    // Use @StateObject at the place that *creates and owns* the object (once);
    // other views receive it rather than re-creating it.
    // `private` is the same access keyword you know from C++.
    @StateObject private var store = ScheduleStore()

    // SwiftUI's DatePicker exposes no minute-interval knob, so we reach through
    // to the UIKit control it's built on. `.appearance()` sets a default for
    // every UIDatePicker the app creates — the same proxy pattern UIKit has
    // always used for global styling. This is why the departure-time wheel
    // steps 00/15/30/45 instead of every minute.
    init() {
        UIDatePicker.appearance().minuteInterval = TimeStep.minutes
    }

    // `body` is a computed property (no stored value — it runs code each time
    // it's read; the `{ }` is its getter, not a stored initializer).
    // `some Scene` is an "opaque return type": the caller just needs to know it
    // gets *some* concrete Scene; the exact type is inferred by the compiler.
    // Roughly comparable to returning `auto` with a concept constraint in C++20.
    var body: some Scene {
        // A WindowGroup is the app's main window(s). The trailing `{ ... }` is a
        // closure (a lambda) passed as WindowGroup's content argument; Swift lets
        // you write the final closure argument outside the parentheses.
        WindowGroup {
            ContentView()
                // `.environmentObject` injects `store` into the view hierarchy so
                // any descendant view can pull it out with @EnvironmentObject —
                // a form of dependency injection, avoiding passing it down by hand.
                .environmentObject(store)
        }
    }
}
