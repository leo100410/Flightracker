import Foundation
import SwiftUI

public enum AppLanguage: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case de, en, da
    public var id: String { rawValue }
    public var title: String {
        switch self { case .de: "Deutsch"; case .en: "English"; case .da: "Dansk" }
    }
    public var locale: Locale { Locale(identifier: rawValue) }
    public func text(_ german: String) -> String {
        // German widgets can initialize before a host process resolves package bundles.
        // Real German keys need no file I/O, and missing resources must never crash a widget.
        if self == .de { return Self.germanFallbacks[german] ?? german }
        guard let translated = Self.translations[german]?[rawValue] else { return german }
        return translated
    }
    private static let translations: [String: [String: String]] = {
        guard let url = RadarResources.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return strings
    }()
    private static let germanFallbacks: [String: String] = [
        "Widget-Anleitung": "Homescreen gedrückt halten > Bearbeiten > Widget hinzufügen > SkyNear. Großes Fünferwidget, großes nächstes Flugzeug oder mittleres Glaswidget wählen. Standort für Widgets erlauben.",
        "Widget-Sprache separat wählen": "Die Homescreen-Widgets sind vorläufig auf Deutsch. Die App-Sprachwahl bleibt erhalten; die Live Activity folgt der App-Sprache.",
        "Widget-Beschreibung": "Foto und Flugdaten. iOS steuert die Aktualisierung.",
        "Prognose-Hinweis": "Geschätzt anhand der letzten gemessenen Geschwindigkeit und des Kurses. Höhe bleibt letzter Messwert. Die Prognose endet spätestens 15 Minuten nach der echten Position."
    ]
}

private final class RadarResourceMarker: NSObject {}
enum RadarResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        // Do not call the generated Bundle.module: its missing-bundle path uses fatalError.
        let owner = Bundle(for: RadarResourceMarker.self)
        let candidates = [Bundle.main.resourceURL, owner.resourceURL]
        for root in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: root.appendingPathComponent("SkyNear_RadarCore.bundle")),
               let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        // Xcode builds RadarCore as a framework that carries its resources directly.
        return owner.url(forResource: name, withExtension: ext)
    }
}

private struct SkyLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .de
}
extension EnvironmentValues {
    public var skyLanguage: AppLanguage {
        get { self[SkyLanguageKey.self] }
        set { self[SkyLanguageKey.self] = newValue }
    }
}
