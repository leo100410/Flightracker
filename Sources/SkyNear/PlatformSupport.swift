import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Small shims so shared views compile for iOS and the native Mac app without behavior changes on iOS.
#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Leading navigation-bar slot on iOS; the window toolbar's navigation area on macOS.
    static var skyLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
    static var skyTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
    /// Close button of a sheet: top trailing on iOS, bottom trailing on macOS.
    static var skyDone: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .confirmationAction
        #endif
    }
}

extension View {
    @ViewBuilder func skyInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

enum PlatformSettings {
    /// Location permission lives in the iOS app settings or the macOS privacy pane.
    static let titleKey: String = {
        #if os(iOS)
        "iPhone-App-Einstellungen öffnen"
        #else
        "Ortungsdienste in den Systemeinstellungen öffnen"
        #endif
    }()
    @MainActor static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
