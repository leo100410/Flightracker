# SkyNear 1.1: Update und Prüfstand

**Aktueller Stand: Korrektur Build 3, erneuter Gerätetest offen.** Build 2 war trotz erfolgreicher Kompilierung auf deinem iPhone mit iOS 27.0 regressionsbehaftet. Ausführliche belegte Befunde, Änderungen und Erfolgskriterien stehen in [REGRESSION_FIX.md](REGRESSION_FIX.md). Die beiden Homescreen-Widgets sind jetzt direkt registriert und vorläufig Deutsch; die Haupt-App-Sprachwahl bleibt erhalten.

## Änderungen im vorhandenen Projekt

- ADSB.lol bleibt primär; adsb.fi Open Data ist die zweite Positionsquelle für persönliche, nichtkommerzielle Nutzung.
- Aktive App: ungefähr 20 Sekunden zwischen Abrufstarts, zusätzliche lokale Suche beim entfernten Kartenbrowsen höchstens einmal pro Minute. Kartenbewegungen und Buttons umgehen dieses Budget nicht. Quellenbezogene Sperrzeiten, Retry-After, exponentieller Backoff und serialisierte Requests verhindern aggressive Wiederholungen.
- Gespeicherte App-Sprache: Deutsch, English, Dansk. Wechsel ohne Neustart; die Live Activity folgt der Auswahl.
- Zwei große Widgets: bestehende Fünferübersicht mit stärkerem Kontrast und neues Einzel-Flugzeug-Kartenwidget mit dunkler Materialkarte, Foto und Flugdaten.
- Dynamic Island links kompakt: tatsächlicher kurzer Modellcode aus dem Positionsdatensatz, sonst —. Rechts bleibt die Entfernung.
- Ausfall beider Quellen: geografische Prognose aus echten Ausgangsdaten, höchstens 15 Minuten ab echter Positionszeit. Orange, Geschätzt/Estimated/Estimeret und ~ markieren Schätzungen. Bodenflugzeuge und unvollständige Ausgangsdaten werden ausgeschlossen. Eine erfolgreiche leere Antwort bleibt leer.

Bundle-ID, Radius-Key `skynear.radius.v1`, Widget-Kind `SkyNear.Nearby.v1`, Cache-Dateiname und Deep Links wurden bewahrt. Neue optionale Codable-Felder erlauben das Lesen alter Positionscaches; ohne echte Zeitangabe gibt es keine Prognose. SwiftPM-/MapKit-/Linker-Fixes und `LiveActivityOperations.swift` bleiben erhalten.

## Anwendung

Die Änderungen liegen bereits in den aktiven Dateien. Sicherung des Ausgangsstands: `patch-backups/update-20261014-171402/`. Die alten `SkyNear_*_Fix/apply_fix.py` brechen bei diesem Update vor jeder Änderung ab, damit sie den neuen Stand nicht überschreiben. Nicht erneut auf das Update anwenden.

`RadarCore` enthält neue Komponenten für Quellen, Koordination, Lokalisierung und Vorwärtsprojektion. App-Ansichten und `RadarStore` sind angepasst; `WidgetData.swift` und `NearestAircraftWidget.swift` ergänzen die Extension. Übersetzungen und Quellenhinweise liegen unter `Sources/RadarCore/Resources/` und werden vom bestehenden SwiftPM-Ressourceneintrag verarbeitet. Beide Info-Plists nennen den Fallback und Kartenanfragen an Apple.

## Build in deiner Umgebung

PowerShell:

```powershell
wsl -d Ubuntu
```

Anschließend direkt in Ubuntu:

```bash
cd /mnt/c/Users/Leola/Documents/iosapp/SkyNear
python3 verify-update.py
bash build-ipa.sh
```

Das Buildscript akzeptiert nur eine nach Buildbeginn erzeugte IPA, führt alle drei vorhandenen IPA-Prüfer aus und nennt den tatsächlichen Pfad. Danach diese neue IPA mit ESign auf dem iPhone signieren und installieren; die Widget-Extension muss eingebettet bleiben und mit signiert werden. Keine zweite parallele Buildinstanz starten. Bei einem Fehler die erste relevante Meldung mit etwa 20 Zeilen Kontext aus `build.log` verwenden.

## Sprachen und Systemgrenzen

App: Einstellungen → Sprache, unverändert gespeichert. Widgets: zwei große deutsche statische Designs direkt im WidgetBundle, ohne verschachtelte Sprachgruppen. Das bestehende deutsche Fünferwidget behält seinen Identifier. Die Live Activity folgt der App-Sprache. Ohne gemeinsam provisionierte App Group übernimmt das Widget die App-Sprache nicht automatisch. App und Extension besitzen getrennte Abrufbudgets; beide Widgets teilen den Dienst innerhalb der Extension. Systemdialoge folgen den iOS-Einstellungen.

Abweichung vom ursprünglichen Plan: keine AppIntentConfiguration für „Widget bearbeiten“. Der xtool-Maintainer beschreibt die erforderliche proprietäre App-Intents-Metadatenverarbeitung als offene Funktion ([Issue 145](https://github.com/xtool-org/xtool/issues/145)). Die im ersten Update ersatzweise eingeführten Sprachgruppen wurden im Korrekturstand entfernt. Zwei direkt registrierte statische deutsche Widgets vermeiden beide zusätzlichen Registrierungspfade. App-Intents-Metadaten werden nicht benötigt.

Kartensnapshots laden Apple-Karten und haben eine begrenzte Wartezeit. Glasoptik ist eine kompatible Materialdarstellung ab iOS 17; Tönung kann Farben ersetzen. Daher werden Schätzungen zusätzlich mit Text/~ gekennzeichnet. Snapshotfehler lassen die Informationskarte sichtbar.

Widget-Prognosen werden nur bei einem bereits festgestellten Ausfall beider Quellen vorbereitet, ungefähr im Fünf-Minuten-Abstand mit abschließendem Ablaufzustand. Bei unterschiedlichen Messzeiten endet die vorbereitete Widget-Prognose vorsichtshalber am frühesten Ablauf der gültigen Ausgangsdaten; so bleibt zwischen Timeline-Einträgen keine bereits abgelaufene Einzelposition stehen. Frische Antworten werden nicht vorsorglich als Prognosen ausgegeben. iOS bestimmt Timeline-Anzeige und Nachladen; keine sekündlichen Hintergrundupdates. Die Live Activity erhält berechnete Zustände von der aktiven App. Beim Suspendieren wird nichts selbständig weiterprojiziert; staleDate markiert den Ablauf, dessen systemseitige Anzeige nicht sekundengenau garantiert ist. Bei gemischten Messzeiten wird die ganze angezeigte Prognose spätestens am frühesten Ablauf als veraltet behandelt.

## Tatsächlicher Prüfstand

Quellen erstellt und statisch überprüft. `python verify-update.py` prüft Ressourcen, Übersetzungs-Keys, Plists, Bundle-ID, erhaltene Build-Fixes und Sperren alter Reparaturscripts. Diese Prüfung ist kein Swift-Test und kein iOS-Build.

Aktualisierter Prüfstand vom 14.10.2026:

- Statische Prüfung: `python3 verify-update.py` in Ubuntu bestanden.
- Tatsächliche Kompilierung: `bash build-ipa.sh` erfolgreich, Swift 6.4, iPhoneOS27.1-SDK, arm64, Deployment Target iOS 17.0.
- IPA-Erzeugung: neue `xtool/SkyNear.ipa`, bestätigt durch Zeitmarker des Buildscripts und aktuellen Buildlog.
- Paket-/Widget-Prüfungen: alle drei Prüfer erfolgreich; arm64-App und -Extension, Widget-Code und Swift-Einstiegspunkt vorhanden. Signing-Headerplatz 26800 Byte (App), 26848 Byte (Extension).
- Ressourcen: Übersetzungen und deutsche/englische/dänische Quellenhinweise sowohl in App als auch Extension eingebettet.
- Nicht ausgeführt: XCTest, kryptografische Signaturprüfung, ESign-Installation, API-Erreichbarkeit auf dem iPhone und Gerätetests.

Build 3 wurde anschließend ebenfalls erfolgreich kompiliert und neu verpackt. Die erweiterte Paketprüfung kontrolliert beide kind-Identifier, alle drei Widget-Code-Typen, aktuelle Buildnummer, Ressourcen und Konfiguration. Der Widget-Prüfer bestätigt zusätzlich den tatsächlichen Verweis von __swift5_entry auf _main. Diese Ergebnisse bestätigen keinen iPhone-Darstellungserfolg; die gemeldete Regression gilt bis zum neuen Gerätetest als nicht abschließend behoben.

WSL wurde nach anfänglichem `E_ACCESSDENIED` für die konkreten Aufrufe außerhalb der Sandbox freigegeben. Swift war vorhanden, fehlte aber im PATH des nichtinteraktiven Aufrufs; der bestätigte Toolchain-Pfad wurde nur für den Prozess gesetzt. Danach wurden zwei Fehler meines neuen Widget-Codes korrigiert: `widgetAccentedRenderingMode` vor `scaledToFill`, sowie ein ausdrückliches `return` in der Dynamic-Island-Closure. Keine Neuinstallation und keine Cache-Löschung. Nur ein Build gleichzeitig. Aktuelles `build.log` enthält den erfolgreichen Lauf.

Neue XCTest-Fälle stehen in `PredictionTests.swift` und `PositionSourceTests.swift`; sie benötigen einen kompatiblen Apple/iOS-Test-Runner. Gerätetests und manuelle Fehlerszenarien stehen in `TESTPLAN.md`.
# Aktuelles Update: Build 5

Der aktuelle Stand und die Grenzen der Aktualisierung ohne Server stehen in [SERVERLESS_UPDATE.md](SERVERLESS_UPDATE.md). Die folgenden Abschnitte beschreiben das frühere Update.
