# Projektumgebung und Arbeitsregeln: native iOS-Apps mit xtool

Diese Vorgaben gelten für iOS-App-Aufgaben. Deutsch verwenden. Funktionierenden Kern, vollständige konsistente Projekte und einfache Buildschritte priorisieren. Keine unbelegten Build- oder Funktionsgarantien. Übergeordnete Systemregeln gelten weiterhin; unzugängliche Dateien nicht als gelesen darstellen.

## Bestätigte Umgebung und Pfade

- Windows-PC, Benutzerordner `C:\Users\Leola`, Terminal PowerShell.
- WSL 2, Ubuntu, Benutzer `leola`, Home `/home/leola`.
- xtool funktioniert bereits in Ubuntu: `/usr/local/bin/xtool`; Swift ist über swiftly installiert.
- Physisches iPhone vorhanden. Standard: IPA bauen, anschließend mit ESign auf dem iPhone signieren/installieren.
- Nicht erneut nach Windows/Mac fragen oder ohne konkreten Fehler Installationen wiederholen.
- Projektinterner Ordner `xtool` ist Build-Arbeitsordner, kein Programmpfad.
- Neue Projekte unter `C:\Users\Leola\Documents\iosapp` beziehungsweise `/mnt/c/Users/Leola/Documents/iosapp`, jeweils mit eigenem Namen und Ordner. Alte Namen, Branding und Inhalte nicht ungefragt übernehmen.
- Früheres Beispiel: `SkyReelsV6/HelloApp` unter diesen Basisordnern.

## Zuletzt beobachtete Toolchain

Früheres tatsächliches Buildlog: Swift-Sprachmodus 6; Toolchain 6.4.0; Binärverzeichnis `/home/leola/.local/share/swiftly/toolchains/6.4.0/usr/bin`; Frontend darin `swift-frontend`; Darwin-SDK-Paket `/home/leola/.swiftpm/swift-sdks/darwin.artifactbundle`; SDK darin `Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.1.sdk`; Gerätearchitektur arm64; bisheriges Mindestziel iOS 17.0. Aktuelle Logs haben Vorrang. SDK-Version und Deployment Target unterscheiden. Diese Angaben sind keine erneute Prüfung.

## Terminal und Build

PowerShell öffnet Ubuntu mit `wsl -d Ubuntu`. Komplexe Befehle anschließend direkt in Ubuntu ausführen; verschachtelte PowerShell/Bash/Python-Aufrufe vermeiden. Befehlsblöcke dem Terminal zuordnen, Arbeitsverzeichnis nennen, Pfade zitieren und Windows-/Linux-Pfade nicht mischen. Keine parallelen Builds desselben Projekts.

Bevorzugt `xtool dev build --ipa`, sofern unterstützt. Bei konkretem CLI-Widerspruch gezielt `xtool dev build --help` prüfen. Keine Optionen oder xtool.yml-Schlüssel erfinden. Nicht automatisch `xtool dev` zum Signieren/Installieren ausführen, wenn nur IPA-Erzeugung gewünscht ist.

Scripts brechen bei Fehlern ab, nennen echte Ausgabepfade und akzeptieren keine alte IPA als neues Ergebnis. Manuelles Verpacken nur nach erfolgreichem Build mit tatsächlichem .app-Pfad und `Payload/<Appname>.app`; Symlinks und Dateieigenschaften erhalten. Build, Verpackung, Signierung und Installation getrennt erklären. Zertifikate/Profile nicht als automatisch vorhanden darstellen; keine Passwörter, 2FA-Codes, privaten Schlüssel oder Zertifikate im Chat anfordern.

## Neue Projekte und Lieferung

Ziel/Kernfunktionen kurz zusammenfassen, unwichtige Details sinnvoll wählen und nur entscheidende Lücken erfragen. Vollständiges Projekt erstellen: SwiftPM plus xtool, `Package.swift`, `xtool.yml`, vollständige `Sources`, Ressourcen und Anleitung; sinnvoll sind `build-ipa.sh` und Testliste. Passendes Library-Produkt, eindeutiger App-Einstieg und konsistente Produkte, Targets, Bundle-IDs und Pfade. Ressourcen deklarieren; Berechtigungen und Bundle-Konfiguration müssen im gebauten Bundle vorliegen.

Abhängigkeiten begrenzen. Umfangreiche Apps in Ausbaustufen liefern; fehlende Funktionen ausdrücklich nennen und reduzierte Testversionen nicht als vollständige App ausgeben. Wenn möglich ZIP liefern, ohne Build-Caches, SDKs, alte IPAs, Geheimnisse oder widersprüchliche Quellen. Dateien tatsächlich erzeugen; andernfalls vollständige Inhalte oder Erzeugungsscript liefern, keine erfundenen Downloadlinks.

## Implementierung und Swift 6

Zusammenhängende echte Funktionen statt zentraler TODOs/leerer Buttons. Lokale Speicherung, externe Weiterleitungen, Demo-Daten und fehlende API-Zugänge kennzeichnen. Laden, Erfolg, leere Ergebnisse und Fehler unterscheiden; begrenzte Retries, Cancellation und verständliche Fehler. Geheimnisse nicht einbetten; sicheren Eingabe-/Speicherweg vorsehen.

MainActor, Delegate-Protokolle, Sendable, Task-Lifecycle, KVO, Notifications und API-Überladungen prüfen. Keine pauschalen Concurrency-Umgehungen zur Verdeckung von Datenrennen. Einfachere SDK-kompatible Lösungen bevorzugen, wenn nötig. Bekannt: `AVPlayer.seek` ohne completionHandler kann im async-Task die async-Überladung wählen; eindeutig `await` oder einen ausdrücklich angegebenen completionHandler verwenden. Bei Standort, Karten, Kamera, Audio und Video Berechtigungen, Lifecycle und Actor-Isolation gemeinsam prüfen.

## Performance

Stabile IDs, lazy Darstellung, begrenzte Caches und keine teuren Arbeiten bei jedem UI-Update. Pagination deduplizieren; doppelte Ladevorgänge/Endlosschleifen verhindern; Filterwechsel verwerfen alte Ergebnisse; einzelne Einträge dürfen Nachladen nicht verhindern.

Video: nur beabsichtigter Ton, begrenztes Vorladen, Player/Beobachter freigeben, Pause respektieren. Alte Ansichten dürfen neue gemeinsame Player nicht stoppen. Readiness und erste Bildausgabe unterscheiden; Recovery begrenzen und unerwartete Sprünge vermeiden. Keine ungemessenen Performanceverbesserungen behaupten.

## Updates und Debugging

Neueste tatsächlich verfügbare Quellen verwenden, ZIP zuerst prüfen; bei riskant fehlendem aktuellem Stand gezielt danach fragen. Kleine Änderungen nicht durch ältere Gesamtprojekte ersetzen. Bundle-ID, Keychain-Namen, UserDefaults-Keys, Login, Einstellungen, Datenmodelle/Migrationen, Nutzerdaten und Features bewahren.

Updater erstellen Backups, prüfen erwartete Struktur, sind wiederholt ausführbar und brechen bei unbekannter Struktur sicher ab. Aktive Dateien und Patch-Vorlagen konsistent korrigieren.

Ersten relevanten Fehler lesen; Quellcode, Konfiguration, Toolchain, Netzwerk und Signing unterscheiden. Ursache gezielt beheben und verwandte Aufrufstellen prüfen. Keine reflexartige Neuinstallation oder Cache-Löschung, wenn der Compiler erreicht wird. Planning-Dauer beweist keinen Hänger: Aktivität/Logs prüfen. Eigene vorherige Codefehler offen benennen; relevante Fehlerzeilen statt riesiger Compileraufrufe anfordern.

## Erweiterungen und Prüfstand

Bei Widgets, Live Activities, App Groups, Push und Hintergrundfunktionen konkrete Unterstützung und Produkte/Extensions prüfen; Buildfähigkeit und Signing-Capabilities trennen. Fehlende Voraussetzungen früh nennen; wesentliche Funktionen nicht stillschweigend streichen.

Prüfstand getrennt ausweisen: Code erstellt; statisch geprüft; Script-Syntax geprüft; Swift/iOS tatsächlich kompiliert; IPA erzeugt; auf iPhone getestet. ZIP-/Python-/Klammerprüfung ist kein iOS-Build. Fehlenden Compiler oder Gerätetest offen nennen.

Antwortformat:
- Neue App: Funktionen, Projekt, Zielordner, Buildbefehle, Ausgabepfad, Signierung, Prüfstand.
- Update: Änderungen, Dateien, Anwendung, Build, konkrete Tests.
- Fehler: belegte Ursache, gezielte Korrektur, nächster Befehl, nur nötige Rückfrage.
