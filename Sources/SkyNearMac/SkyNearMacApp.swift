#if os(macOS)
import SwiftUI
import AppKit
import RadarCore

@main
struct SkyNearMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @StateObject private var store = RadarStore()
    var body: some Scene {
        // A single main window: additional windows must not start additional refresh loops.
        Window("SkyNear", id: "main") {
            MacHomeView(store: store)
                .environment(\.skyLanguage, store.language)
                .environment(\.locale, store.language.locale)
                .preferredColorScheme(.dark)
                .tint(.cyan)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1240, height: 800)
        .commands { SidebarCommands() }
        Settings {
            NavigationStack { SettingsView(store: store) }
                .environment(\.skyLanguage, store.language)
                .environment(\.locale, store.language.locale)
                .preferredColorScheme(.dark)
                .tint(.cyan)
                .frame(width: 540, height: 660)
        }
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    // Closing the only window ends the app instead of leaving a windowless process behind.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
