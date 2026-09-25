// Small shims that let one SwiftUI source tree build for both iPhone and Mac.
//
// The app is one target compiled twice — once against the iOS SDK, once against
// macOS — so a handful of APIs exist on only one side. Rather than sprinkle
// `#if os(...)` through ContentView, the differences are collected here behind
// names the views can call unconditionally. `#if` is Swift's preprocessor
// conditional, resolved at compile time exactly like `#ifdef` in C++: the
// branch that isn't taken never reaches the compiler, so referring to a UIKit
// type inside `#if os(iOS)` is fine even though macOS has no such type.

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Colors

// iOS ships semantic greys for "grouped" layouts: a tinted page behind white
// cards, which is the look this app uses. AppKit's equivalents aren't spelled
// the same, so each platform names its own pair.
extension Color {
    /// The page behind the cards.
    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    /// The card surface that sits on top of `groupedBackground`.
    ///
    /// AppKit's obvious pick, `controlBackgroundColor`, resolves to exactly the
    /// same #1E1E1E as `windowBackgroundColor` under the dark appearance — the
    /// two only differ in light mode. Since the app is dark-only that pairing
    /// would leave the cards invisible. `underPageBackgroundColor` sits one step
    /// lighter at #282828, which gives the same "card floating above the page"
    /// reading that iOS gets from its secondary grouped grey.
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }
}

// MARK: - Navigation and search

// These are `View` extensions returning `some View`, so they chain in a modifier
// list just like a built-in modifier would.
extension View {
    /// Compact, centered navigation title. The modifier that asks for it is
    /// iOS-only; a Mac window title bar is already compact, so there's nothing
    /// to do there.
    func inlineNavigationBar() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Search field for the station picker. On iOS it's pinned open beneath the
    /// title; macOS has no navigation-bar drawer, and its default placement puts
    /// the field in the toolbar, which is the native spot for it.
    func stationSearchable(text: Binding<String>) -> some View {
        #if os(macOS)
        self.searchable(text: text)
        #else
        self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always))
        #endif
    }

    /// A sheet on iOS fills the screen; on macOS it sizes to its content, which
    /// leaves a bare `List` far too small to use. This gives the Mac sheet a
    /// usable shape and leaves iPhone untouched.
    func sheetSizing(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }
}

// MARK: - Window

// `Scene` is the protocol WindowGroup conforms to — the app's windows, one level
// up from views — so its modifiers are extended separately from View's.
extension Scene {
    /// Mac window defaults. The layout is a single narrow column, so the window
    /// opens at roughly phone proportions instead of a wide expanse of empty
    /// grey. `.contentMinSize` keeps it resizable, just never smaller than the
    /// content needs. Both modifiers are macOS-only; iOS manages its own window.
    func macWindowDefaults() -> some Scene {
        #if os(macOS)
        self.defaultSize(width: 420, height: 760)
            .windowResizability(.contentMinSize)
        #else
        self
        #endif
    }
}

// MARK: - Appearance

/// Pins the app to the dark appearance regardless of the system setting.
///
/// `.preferredColorScheme(.dark)` in the scene covers SwiftUI's own views on
/// both platforms, but not the chrome around them. On macOS the title bar and
/// menu bar follow NSApplication's appearance, which is what this sets; on iOS
/// the equivalent is the Info.plist key `UIUserInterfaceStyle`, set to `Dark`
/// in the build settings so that alerts and the keyboard match too.
func forceDarkAppearance() {
    #if os(macOS)
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    #endif
}
