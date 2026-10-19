#if os(macOS)
import SwiftUI
import AppKit
import RadarCore

/// Mac layout: the local five-aircraft overview in the sidebar, the radar map as the main content.
struct MacHomeView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Plane?
    @State private var pendingHex: String?
    var body: some View {
        NavigationSplitView {
            NearbyScreen(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
        } detail: {
            MapScreen(store: store, selection: $selection, settings: .constant(false))
        }
        .sheet(item: $selection) { plane in
            NavigationStack { DetailView(initial: plane, store: store) }
                .frame(minWidth: 520, idealWidth: 580, minHeight: 600, idealHeight: 760)
        }
        .onAppear { AppDiagnostics.capture("window appeared"); store.activate() }
        .onDisappear { AppDiagnostics.capture("window closed"); store.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            AppDiagnostics.capture("scene \(String(describing: phase))")
            // A visible but inactive Mac window keeps updating; minimized windows stop the loop.
            if phase == .background { store.deactivate() } else { store.activate() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            AppDiagnostics.capture("system sleep")
            store.deactivate()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            AppDiagnostics.capture("system wake")
            if scenePhase != .background { store.activate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            AppDiagnostics.capture("power state changed")
        }
        .onOpenURL { url in
            // The diagnostics host only transfers widget logs; the Mac app has no widgets.
            guard url.scheme == "skynear", url.host == "aircraft",
                  let hex = url.path.split(separator: "/").first else { return }
            pendingHex = String(hex)
            resolvePendingLink()
        }
        .onChange(of: store.nearby?.fetchedAt) { _, _ in resolvePendingLink() }
        .onChange(of: store.snapshot?.fetchedAt) { _, _ in resolvePendingLink() }
    }
    private func resolvePendingLink() {
        guard let hex = pendingHex else { return }
        if let plane = store.nearby?.planes.first(where: { $0.id == hex })
                    ?? store.snapshot?.planes.first(where: { $0.id == hex }) {
            selection = plane; pendingHex = nil
        }
    }
}
#endif
