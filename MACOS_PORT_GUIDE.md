# SkyNear: Projektbeschreibung und Übergabe für einen macOS-Port

> **Umgesetzt am 17.10.2026:** Native SwiftUI-Mac-App (macOS 14+, Universal) im Xcode-Projekt `SkyNear.xcodeproj`, Target `SkyNear macOS`. Widgets und Menüleiste auf dem Mac sind weiterhin offen. Überblick in der README unter „Xcode-Projekt und macOS-App“.

Stand: 15.10.2026. Diese Datei beschreibt den lokal gelesenen Quellcode, keine bereits vorhandene macOS-App. Bei Abweichungen ist der aktuelle Code maßgeblich; ältere Statusangaben in README und Reparaturdokumenten können überholt sein.

Repository: https://github.com/leo100410/Flightracker

## Ziel und Ausgangslage

SkyNear ist ein natives Flugzeugradar mit SwiftUI und MapKit. Es zeigt erfasste Flugzeuge auf einer Karte, eine Übersicht der fünf nächsten Flugzeuge am Gerätestandort sowie Detailinformationen und Bilder. Es gibt keinen eigenen Server, kein Benutzerkonto und keine eingebetteten API-Schlüssel. Die App ruft externe Dienste direkt ab.

Der vorhandene Stand ist ein Swift-6-Paket für iOS 17+. Er enthält keine Xcode-Projektdatei und kein macOS-Target. Die iOS-Paketierung erfolgt mit xtool unter Windows/WSL. Ein bloßer zusätzlicher macOS-Eintrag in `Package.swift` reicht für den Port nicht aus.

Gewünscht ist ein macOS-Port. Native macOS-App oder Mac Catalyst, Mindestversion, Widgets und eine mögliche Menüleistenansicht sind noch nicht vom Nutzer festgelegt. Als Ausgangspunkt bietet sich eine native SwiftUI-App mit gemeinsamem Datenkern an. Diese Architekturentscheidung ist ein Vorschlag und keine bereits umgesetzte Anforderung.

## Dateien und Zuständigkeiten

| Bereich | Dateien | Aufgabe |
| --- | --- | --- |
| Paket und iOS-Verpackung | `Package.swift`, `xtool.yml`, `App-Info.plist`, `Widget-Info.plist` | Targets, Ressourcen, Bundle-Konfiguration und Extension |
| App-Einstieg | `Sources/SkyNear/App.swift` | Erzeugt den gemeinsamen `RadarStore`, setzt Sprache, dunkle Darstellung und iOS-Hintergrundhandler |
| App-Zustand | `Sources/SkyNear/RadarStore.swift` | Standort, Abrufschleife, getrennte Karten-/Umgebungsdaten, Anreicherung, Widget-Reload und Live Activities |
| Oberfläche | `HomeView.swift`, `DetailView.swift` in `Sources/SkyNear/` | Karte, Umgebungsliste, Details, Einstellungen und Deep Links |
| Hintergrund und Diagnose | `BackgroundRefresh.swift`, `LiveActivityOperations.swift`, `DiagnosticsView.swift` | iOS-Hintergrundfenster, serialisierte ActivityKit-Aktionen, Diagnoseanzeige und Export |
| Modelle | `Sources/RadarCore/Models.swift` | Koordinaten, Flugzeuge, Metadaten, Snapshots, API-Decoding und Activity-Datentypen |
| Positionsquellen | `PositionSource.swift`, `PositionCoordinator.swift`, `RadarAPI.swift` in `Sources/RadarCore/` | URLs, Quellenwechsel, Wartezeiten, HTTP, Decoding und Anreicherung |
| Darstellung und Projektion | `Prediction.swift`, `AircraftMarker.swift`, `AircraftFamily.swift` | Geografische Fortschreibung und richtungs-/modellabhängige Marker |
| Standort und Speicher | `Location.swift`, `LocationMemory.swift`, `SharedPositions.swift`, `WidgetRefreshPolicy.swift` | Standortfreigabe, letzte Messung, atomarer Positionsspeicher, Wiederverwendung |
| Sprache und Bilder | `Localization.swift`, `ModelPhotos.swift`, `Sources/RadarCore/Resources/` | Deutsch, Englisch, Dänisch; Modellbilder, Übersetzungen, Quellen und Bildrechte |
| Diagnosekern | `RadarDiagnostics.swift`, `DiagnosticJournal.swift` | Betriebsereignisse, Dateijournal, Export/Import |
| Widgets | `Sources/SkyNearWidgets/` | Timeline-Provider, eigene Datenkoordination, Karten-Snapshots und Live-Activity-Ansicht |
| Tests | `Tests/RadarCoreTests/`, `Tests/run-portable-checks.py`, `Tests/run-diagnostic-checks.py` | XCTest sowie begrenzte portable Prüfungen |

`SkyNear_*_Fix/`, `patch-backups/` und `.bak`-Dateien sind historische Reparaturen/Sicherungen. Änderungen am aktuellen Produkt gehören in `Sources/`. Diese historischen Ordner und lokale Buildprodukte sind beim GitHub-Upload ausgeschlossen.

## Fachliche Funktionen

- Kartenradar mit Radius 50, 150, 300 oder 463 km. Verschieben der Karte lädt eine andere Region.
- Die lokale Fünferübersicht bleibt am Gerätestandort orientiert, auch wenn die Karte eine entfernte Region zeigt.
- Details enthalten je nach Datenlage Rufzeichen, Hex-ID, Registrierung, Modellcode, Modellbeschreibung, Airline, Eigentümer, Höhe, Geschwindigkeit, Kurs, Entfernung, Referenzroute und Foto.
- Fehlende Informationen bleiben unbekannt. Modellcode, Airline oder aktuelle Route dürfen nicht aus einem Rufzeichen geraten werden. Referenzrouten sind kein Nachweis des tatsächlich geflogenen Flugplans.
- Einheiten in der Oberfläche sind Meter, km/h und Kilometer. Rohdaten enthalten unter anderem Fuß und Knoten; die bestehenden Umrechnungen beibehalten.
- Quellenfehler, veraltete Daten und geschätzte Positionen werden sichtbar ausgewiesen.
- Die App speichert die Sprachwahl Deutsch/Englisch/Dänisch und wechselt ohne Neustart. Fachcodes und Eigennamen werden nicht übersetzt.
- Deep Links verwenden `skynear://aircraft/<hex>`; Diagnoseübernahme verwendet den Host `diagnostics`. Siehe `HomeView.onOpenURL` und `RadarDiagnostics` für das genaue Format.

## Datenfluss und Aktualisierung

1. `AppLocation` liefert per CoreLocation den Gerätestandort. Die letzte Messung wird mit Messzeit in `LocationMemory` gespeichert.
2. `HomeView` aktiviert/deaktiviert den Store entsprechend der Szene. Kartenbewegungen werden um etwa 700 ms verzögert gebündelt; `setCenter` ignoriert kleine Verschiebungen unter 3 km.
3. `RadarStore` hält `realMap` und `realNearby` als echte Ausgangsdaten sowie `snapshot` und `nearby` für die aktuelle Anzeige. Eine Revisionsnummer verhindert, dass verspätete Antworten einen inzwischen geänderten Kartenbereich ersetzen.
4. Die aktive Schleife läuft etwa alle fünf Sekunden. Das bedeutet keinen Netzwerkabruf alle fünf Sekunden: `refresh()` erlaubt reguläre Abrufstarts frühestens nach 20 Sekunden.
5. In der Nähe des Gerätestandorts wird ein 463-km-Suchbereich geladen und für den gewählten Kartenradius gefiltert. Bei entfernter Karte erfolgt eine zusätzliche lokale Suche höchstens einmal pro Minute.
6. `PositionCoordinator` bündelt identische laufende Anfragen, serialisiert unterschiedliche Suchbereiche und hält kurzzeitig erfolgreiche Antworten vor. Die Standard-Mindestdistanz zwischen Quellenanfragen beträgt 1,1 Sekunden.
7. Zuerst wird ADSB.lol abgefragt, bei Ausfall adsb.fi Open Data. Jede Quelle hat eigene persistierte Sperrzeiten; Fehler-Backoff, Jitter und `Retry-After` respektieren. Eine erfolgreiche leere Antwort ist verbindlich und kein Anlass, alte Flugzeuge wieder einzusetzen.
8. Echte Positionen werden sofort übernommen. Danach ergänzt `RadarAPI` Metadaten für die nächsten Flugzeuge beziehungsweise bei Detailaufrufen. Optionale Metadaten/Fotos dürfen Positionsanzeigen nicht blockieren.
9. Anzeigepositionen werden aus echten Messungen für den jeweiligen Zeitpunkt erzeugt. Echte neue Daten ersetzen Schätzungen. Widget-/Activity-Aktualisierung folgt den akzeptierten Daten.

`RadarAPI` ist ein Actor mit einer kurzlebigen URLSession-Konfiguration, Zeitlimits, Antwortgrößenlimits und Bildverkleinerung über ImageIO. Metadaten kommen über `api.adsbdb.com`; die tatsächlich benutzten Foto-URLs ergeben sich aus Metadaten und Code. Es gibt zusätzlich gebündelte Modellbilder mit eigenem Katalog und Quellenangaben.

## Zeitstempel und Schätzungen: unbedingt erhalten

Die ältere README beschreibt Projektion hauptsächlich als Ausfallfunktion. Der aktuelle `Prediction.swift`-Code projiziert geeignete echte Flugzeuge auch zwischen erfolgreichen Abrufen, sobald das Positionsalter über fünf Sekunden liegt. Das ist für einen verhaltensgleichen Port entscheidend.

- `fetchedAt` ist die Abrufzeit, `positionAt` die echte Positionsmesszeit, `estimatedAt` die Projektionszeit. Diese Bedeutungen nicht vermischen.
- `RadarSnapshot.dataDate` verwendet die Quellenzeit, falls vorhanden, sonst die Abrufzeit.
- Eingelesene echte Positionen werden unter anderem anhand `seen_pos`, Quellenzeit, Wertebereichen und einer 90-Sekunden-Grenze geprüft. Details stehen in `Models.swift` und `PositionSource.swift`.
- Fortschreibung nutzt Geschwindigkeit und Kurs entlang einer geografischen Bahn. Sie verändert keine Höhe und erfindet keine Kurven oder Landungen.
- Bodenflugzeuge, fehlende Messzeit/Geschwindigkeit/Kurs und ungültige Werte werden nicht projiziert. Nicht projizierbare Daten verschwinden nach dem kurzen Gültigkeitsfenster.
- Eine Projektion läuft höchstens 15 Minuten ab echter Messung. Bereits geschätzte Positionen werden nicht erneut als Ausgangsmessung verwendet.
- Schätzungen erkennbar darstellen; ursprüngliche Messzeit behalten. Für Zeitgrenzen den Code und die Regressionstests übernehmen, keine pauschalen Timer erfinden.
- Timeline-Daten berücksichtigen einzelne Ablaufzeiten, damit das Ende eines Flugzeugs andere gültige Flugzeuge nicht entfernt.

## Speicherung, Widgets und Datenschutz

`UserDefaults` speichert unter anderem Radius, Sprache, Quellen-Sperrzeiten und die letzte Standortmessung. App und Extension haben grundsätzlich getrennte Container. Gleiche Defaults-Schlüssel bedeuten keinen automatisch gemeinsamen Speicher.

`SharedPositionStore` schreibt echte Snapshots atomar und mit Dateisperre; ältere Daten überschreiben keine neueren. Es werden höchstens die nächsten 20 Flugzeuge gespeichert, ohne Fotodaten. Beim Laden gelten Alters- und Plausibilitätsprüfungen. `WidgetData.swift` enthält zusätzlich den Extension-Cache und dessen Wiederverwendungsregeln.

Der aktuelle Stand enthält optionalen gemeinsamen App-Group-Speicher mit dem konfigurierbaren Schlüssel `SkyNearAppGroup` und Standardwert `group.de.leola.skynear`. Ein Plist-Eintrag allein erteilt keine Berechtigung. `SharedWidgetStorage.directory` ist derzeit nur für `os(iOS)` implementiert und liefert auf anderen Plattformen `nil`. Für den Mac separat umsetzen, falls gemeinsame Widgets gewünscht sind.

Aktuell registriert `SkyNearWidgetBundle` vier Komponenten: `NearbyWidget`, `NearestAircraftWidget`, `MediumAircraftWidget` und `NearbyLiveActivity`. Die README-Angabe von nur zwei Widgets ist älter. WidgetKit kontrolliert die Ausführung; die App kann Timeline-Reloads anfordern, aber keine sekundengenauen Aktualisierungen zusagen. Widgetabrufe laufen in einem eigenen Prozess mit eigener Koordination.

Umkreissuchen übertragen gerundete Koordinaten an die Positionsquellen. Kartenanfragen gehen an Apple; Metadatenabfragen enthalten Flugzeugkennungen/Rufzeichen. Standorttexte, `PrivacyInfo.xcprivacy`, Quellenangaben und Bildlizenzen erhalten und an den Mac anpassen. Diagnoseprotokolle sind für Betriebsereignisse vorgesehen, nicht für Koordinaten, Flugzeugkennungen oder Zugangsdaten. Lizenzdetails stehen in den Ressourcen; deren Gültigkeit für eine Veröffentlichung gesondert prüfen.

## Konkrete Portierungsstellen

| Stelle | Im vorhandenen Code | Aufgabe für den Port |
| --- | --- | --- |
| `Package.swift` | Nur iOS 17; App/Widget als Library-Produkte; iOS-Linkerflags | macOS-Ziel und lauffähiges App-Bundle planen; iOS-Konfiguration erhalten; Flags gezielt je Plattform prüfen |
| `Models.swift` | Unbedingtes `import ActivityKit`, gemeinsame Activity-Typen | Plattformneutrale Flugmodelle von iOS-Activity-Typen trennen oder sauber bedingt kompilieren |
| `Prediction.swift` | Extension auf Activity-ContentState neben allgemeiner Projektion | Activity-spezifische Frischeberechnung abtrennen, allgemeine Projektionslogik gemeinsam halten |
| `RadarStore.swift` | ActivityKit und WidgetKit mit Kernabruflogik vermischt | Plattformdienste auslagern; Datenfluss und Abrufbudgets gemeinsam verwenden |
| `Location.swift` | App-Standort plus `WidgetLocationRequest` mit Widget-Berechtigungsprüfung | Verfügbarkeit einzelner APIs im Mac-SDK prüfen; Berechtigungs- und Fehlermeldungen anpassen |
| `HomeView.swift` | UIKit-Symbole, iOS-Notifications, Tab-/Sheet-Layout, Top-Bar-Toolbar | Mac-Lebenszyklus und Navigation umsetzen; Karten-/Listen-/Detaildarstellung an Fenstergrößen anpassen |
| `DetailView.swift` | UIKit-Import, `UIApplication.openSettingsURLString`, iOS-Toolbar | Plattformgerechten Einstellungsweg und Navigation einsetzen; Bilddarstellung auf weitere Plattformbezüge prüfen |
| Widget-Views und Karten-Snapshots | `UIImage`, UIKit, iOS-Darstellung | Bildkonvertierung und Rendering abstrahieren; Mac-Widget separat paketieren und testen |
| `BackgroundRefresh.swift`, `App.swift` | BackgroundTasks, `UIApplication`-Hintergrundfenster, SwiftUI-App-Refresh | iOS-Mechanik isolieren; Mac-Laufzeitverhalten bei Fensterwechsel, Schlafen und Beenden definieren |
| `LiveActivityOperations.swift`, Widget-`LiveActivity.swift` | ActivityKit und Dynamic-Island-Darstellung | Aus dem nativen Mac-Target ausschließen; Ersatz wie Menüleiste nur bei gewünschtem Umfang |
| `DiagnosticsView.swift` | UIKit-/BackgroundTasks-Diagnose, iOS-App-Zustand | Allgemeines Journal erhalten, plattformspezifische Statusfelder ersetzen |
| `SharedPositions.swift` | Plattformbedingter App-Group-Zugriff und Dateischutz | Mac-Container-/Sandbox-Konzept umsetzen; atomare Speicherung erhalten |
| Ressourcen und Plists | iOS-Icons, iOS-Plist-Schlüssel, SwiftPM-Ressourcen | Mac-App-Icon, Plist, Standortfreigabe, Netzwerkzugriff und gegebenenfalls App-Group-Entitlements konfigurieren |

`RadarCore` ist heute also noch kein vollständig plattformneutraler Kern. Neben Foundation verwendet es CoreLocation, SwiftUI, ActivityKit, ImageIO, UniformTypeIdentifiers, os und Compression. Frameworks und einzelne Symbole am gewählten macOS-Deployment-Target prüfen. Ressourcenauflösung über `RadarResources`/`Bundle.module` auch im neuen App-Bundle testen.

Der macOS-Port ist noch nicht gebaut oder getestet. Konkrete API-Verfügbarkeit und erforderliche Entitlements anhand des eingesetzten Apple-SDKs und aktueller Apple-Dokumentation bestätigen, bevor die Umsetzung darauf aufbaut.

## Empfohlene Umsetzung und Abnahme

1. Repository klonen, `AGENTS.md`, diese Datei und die aktuellen Quellen lesen. Eigenen Branch für macOS anlegen und die funktionierende iOS-App erhalten.
2. Native macOS-App versus Catalyst sowie Mac-Mindestversion festlegen. Vorhandene iOS-IPA-Buildskripte sind kein Mac-Buildsystem.
3. ActivityKit, UIKit und iOS-Hintergrunddienste aus den gemeinsamen Buildpfaden lösen. Modelle, Quellenkoordination, Projektion und Tests gemeinsam halten.
4. Einen startbaren Mac-App-Build mit Standortfreigabe, Ressourcen und Karte herstellen. Sandbox/Signierung und reale Standortfreigabe auf dem Mac prüfen.
5. Umgebungsliste, Details, Sprache, Fehlerzustände, Navigation und Deep Links ergänzen. Mehrere Fenster dürfen keine zusätzlichen unkontrollierten Abrufschleifen auslösen.
6. Erst danach optional Widgets oder Menüleistenmodus ergänzen. Dafür Lebenszyklus, Datenaustausch und Abrufbudgets ausdrücklich festlegen.
7. XCTest auf einem passenden Apple-Runner ausführen; nach Plattformtrennung gegebenenfalls `swift test` für den Mac ermöglichen. Bestehende iOS-Prüfungen weiterhin durchführen.

Abnahmefälle: Standort erlauben/ablehnen; Karte ohne Standort bedienen, soweit vorgesehen; lokale Liste bleibt beim Kartenverschieben lokal; Radius und Sprache wechseln; Details ohne Metadaten/Foto; erfolgreicher leerer Suchbereich; Timeout/HTTP-Fehler/Rate-Limit beider Quellen; Rückkehr echter Daten nach Projektion; Ablauf alter Positionen; Datumsgrenze/Polnähe; Schlafen/Aufwachen; Fenster schließen/wieder öffnen; Ressourcen und Bildrechte sichtbar; Diagnoseexport ohne sensible Inhalte.

`Tests/run-portable-checks.py` verwendet echte Logik mit Ersatzdeklarationen für nicht verfügbare Plattformtypen. Das ist kein Nachweis eines echten Apple-Framework-Builds. IPA-Prüfer validieren iOS-Pakete, keine macOS-App. Ein erfolgreicher Build belegt außerdem keine funktionierenden Standortrechte, Widgets oder Hintergrundausführung.

## Übergabe an eine KI im neuen Chat

Am besten das Repository in die Arbeitsumgebung des neuen Chats klonen/öffnen und den Link sowie diese Datei nennen. Ein GitHub-Link allein gewährt dem Agenten keinen lokalen Schreibzugriff und garantiert keinen Zugriff auf private Inhalte oder Werkzeuge. Ohne Repository-Werkzeuge den aktuellen Quellstand als ZIP bereitstellen; Tokens und Buildverzeichnisse nicht mitgeben.

Vorschlag für die erste Nachricht:

> Erstelle einen macOS-Port von SkyNear aus https://github.com/leo100410/Flightracker. Lies zuerst AGENTS.md und MACOS_PORT_GUIDE.md und prüfe danach die aktuellen Quellen. Behalte die iOS-App funktionsfähig und verwende gemeinsame Modelle, Netzwerkkoordination und Prognoselogik. Arbeite in einem eigenen Branch. Beginne mit einer nativen SwiftUI-Mac-App mit Karte, lokaler Fünferliste, Details, Einstellungen und den vorhandenen Sprachen. Widgets und Menüleistenmodus zunächst nur als optionale Erweiterungen behandeln. Prüfe das verfügbare Mac-Buildsystem, die Mindestversion und Plattformabhängigkeiten und setze den Port anschließend um. Berichte, was tatsächlich gebaut und auf einem Mac getestet wurde.

Dieser Vorschlag legt einen sinnvollen anfänglichen Umfang fest; der Nutzer kann ihn vor Übergabe ändern.
