#if os(iOS)
import SwiftUI
import RadarCore

@main
struct SkyNearApp: App {
    @StateObject private var store = RadarStore()
    var body: some Scene {
        WindowGroup {
            HomeView(store: store)
                .environment(\.skyLanguage, store.language)
                .environment(\.locale, store.language.locale)
                .preferredColorScheme(.dark)
                .tint(.cyan)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            RadarDiagnostics.record("background SwiftUI handler invoked")
            await BackgroundRefresh.perform()
        }
    }
}
#endif
