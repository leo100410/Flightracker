# SkyNear 1.1 für xtool, Windows und WSL

Update des vorhandenen nativen SwiftPM-Projekts für iOS 17+, Swift-Sprachmodus 6, mit Karte, Flugzeugdetails, fünf nächsten erfassten Flugzeugen, zwei großen Homescreen-Widgets und ActivityKit/Dynamic Island. Kein eigener Server und keine eingebetteten API-Schlüssel. Bundle-ID: `de.leola.skynear`; Produkte: `SkyNear`, `SkyNearWidgets`.

## Update und Prüfstand

**Regression auf deinem iPhone (iOS 27.0):** Build 2 zeigte Platzhalterkästen und keine sichtbare Live Activity. Der erfolgreiche Build war kein Nachweis funktionierender Widgets. Aktuell liegt die gezielte Korrektur als Build 3 vor: zwei direkt registrierte deutsche statische Widgets, sicherer Textstart und sichtbare ActivityKit-Rückmeldungen. Sie ist kompiliert und als IPA geprüft; dein erneuter Gerätetest ist noch offen. Befunde und Testkriterien: [REGRESSION_FIX.md](REGRESSION_FIX.md).

Die Quellcodeänderungen liegen im bestehenden Projekt. Einzelheiten, Sicherung, neue Dateien und Grenzen: [UPDATE.md](UPDATE.md). Die Sicherung des vorherigen App-Stands liegt unter `patch-backups/update-20261014-171402/`.

**Prüfstand vom 14.10.2026:** Statische Prüfung in Ubuntu bestanden; tatsächlicher Swift-/iOS-Build erfolgreich. Neue IPA: `xtool/SkyNear.ipa`. Alle drei IPA-Prüfer bestanden (Paketstruktur, Widget-Einstiegspunkt, Signing-Platz). Die Sprachressourcen sind in App und Extension eingebettet. XCTest, Signierung und iPhone-Laufzeit wurden nicht getestet.

WSL war in der Sandbox blockiert und wurde für den konkreten Prüf-/Buildaufruf freigegeben. Der nichtinteraktive Aufruf benötigte den vorhandenen Swift-6.4-Pfad im prozesslokalen PATH. Nichts neu installiert, keine Caches gelöscht. Zwei Compilerfehler im neuen Widget-Code wurden gezielt korrigiert: Reihenfolge des Image-Tönungsmodifikators und ausdrückliches return der Dynamic-Island-Closure.

## Funktionen

- MapKit-Karte für einen gewählten Umkreis: 50, 150, 300 oder 463 km. Entfernte Regionen lassen sich durch Kartenbewegung laden; die lokale Übersicht bleibt auf den Gerätestandort bezogen.
- Flugzeugdetails: Rufzeichen, Registrierung, tatsächlicher Modellcode, Modellbeschreibung, Airline, eingetragener Eigentümer, Höhe, Geschwindigkeit, Entfernung, Kurs, Referenzroute und Foto, soweit verfügbar.
- Primäre Positionen: ADSB.lol. Fallback: adsb.fi Open Data. Referenzdaten und Fotos weiterhin über adsbdb/airport-data.
- Aktive App: ungefähr 20 Sekunden zwischen regulären Abrufstarts; Karten-/Button-Trigger werden gebündelt. Bei entfernter Kartenregion zusätzliche lokale Suche höchstens einmal pro Minute. Quellenbezogene Sperrzeiten und Retry-After verlängern Wartezeiten; keine aggressiven Umschaltversuche.
- Sprache in der App gespeichert: Deutsch, English, Dansk; Wechsel ohne Neustart. Meter, km/h und Kilometer bleiben gleich. Rufzeichen, Airlines, Modell- und Flughafencodes werden nicht übersetzt.
- Zwei große Widgets: Fünferübersicht mit höherem Kontrast und nächstes erfasstes Flugzeug mit Apple-Kartensnapshot, Nutzer-/Flugzeugmarker und abgerundeter dunkler Materialkarte. Foto und Route nur bei vorhandenen Daten. Snapshotfehler verhindern die Flugdatenanzeige nicht.
- Live Activity behält das bisherige Grundlayout. Links in der kompakten Dynamic Island steht der echte Modellcode, sonst —; rechts die Entfernung.
- Bei Ausfall beider Positionsquellen: geradlinige geografische Prognose für bereits erfasste Flugzeuge, höchstens 15 Minuten seit der echten Position. Orange, Geschätzt/Estimated/Estimeret und ~ kennzeichnen Schätzungen. Keine Bodenflugzeuge, fehlenden Ausgangsdaten, erfundenen Kurven, Landungen oder Höhenänderungen. Eine erfolgreiche leere Antwort entfernt alte Flugzeuge aus ihrem Suchbereich.

## Build

Projektordner unter Windows:

`C:\Users\Leola\Documents\iosapp\SkyNear`

PowerShell:

```powershell
wsl -d Ubuntu
```

Danach direkt im Ubuntu-Terminal:

```bash
cd /mnt/c/Users/Leola/Documents/iosapp/SkyNear
python3 verify-update.py
bash build-ipa.sh
```

Das Script führt `xtool dev build --ipa` aus, schreibt `build.log`, akzeptiert nur eine seit Buildbeginn erzeugte IPA und prüft Paketstruktur, Widget-Linkage und Mach-O-Signing-Platz. Es nennt den tatsächlichen Ausgabepfad. Nur einen Build gleichzeitig starten; einen alten Lock erst entfernen, wenn kein Buildprozess mehr läuft.

Bei konkretem Widerspruch zur CLI gezielt `xtool dev build --help` prüfen. Kein automatischer Wechsel zu `xtool dev`, weil damit Signierung/Installation ausgelöst werden kann. Swift-/SDK-Versionen aus aktuellen Logs verwenden; SDK-Version ist nicht Deployment Target. Bestehende Overlay-, Headerpad- und Widget-Einstiegspunkt-Fixes sind in `Package.swift` erhalten.

## Signierung und Nutzung

Die neu erzeugte IPA auf das iPhone übertragen, in ESign mit deinem vorhandenen Zertifikat/Profil signieren und installieren. Die eingebettete `.appex` muss erhalten bleiben und ebenfalls gültig signiert werden. Bei geänderter App-Bundle-ID muss die Extension eine passende untergeordnete ID erhalten. Strukturprüfer prüfen nicht die tatsächlichen Signing-Capabilities.

SkyNear öffnen und Standort bei Benutzung erlauben. Für Widgets die Standortfreigabe gesondert zulassen. Homescreen gedrückt halten → Bearbeiten → Widget hinzufügen → SkyNear. Die zwei großen Widgetformen sind im Korrekturstand vorläufig auf Deutsch, ohne Sprachvarianten oder App-Intents-Konfiguration. App-Sprachwahl und ihre Speicherung bleiben erhalten; die Live Activity folgt der App-Sprache. Das deutsche Fünferwidget behält seinen bisherigen kind-Identifier; die entfernten English-/Dansk-Varianten aus Build 2 gegebenenfalls durch ein aktuelles Widget ersetzen.

Keine App Group erforderlich. Daher übernehmen die Widgets die App-Sprachwahl nicht automatisch; App und Extension besitzen getrennten Speicher und separate Abrufsteuerung. Beide Widgets teilen innerhalb der Extension Abrufdienst, Cache und Quellen-Sperrzeiten. Bestehender Radius-Key, Widget-Kind, Cache-Dateiname und Deep Links bleiben erhalten. Alte Positionscaches ohne echte Messzeit werden nicht prognostiziert.

## Grenzen und Datenschutz

ADS-B/MLAT erfasst nicht alle Flugzeuge. Die nächsten fünf beziehen sich auf erfasste Positionen im geladenen Umkreis, nicht auf alle weltweit existierenden Flugzeuge. Aktuelle Positionen älter als 90 Sekunden werden ausgeschlossen. Höhe ist keine Höhe über dem Boden; Airline ist nicht automatisch Eigentümer; Referenzrouten sind keine verifizierten aktuellen Flugpläne.

iOS bestimmt Widget-Updates und Timeline-Anzeige. Prognoseeinträge werden bei erkanntem Ausfall etwa im Fünf-Minuten-Abstand einschließlich Endzustand vorbereitet. Live Activities werden von der aktiven App aktualisiert; ohne APNs/Backend keine garantierten fortlaufenden Hintergrundabrufe oder Projektionen. Echte Daten werden nach 60 Sekunden als veraltet markiert; Schätzungen haben einen Messzeit-bezogenen Ablauf. Systemseitiges Ausblenden ist nicht sekundengenau zugesagt. Keine Dauerortung und kein missbräuchlicher Hintergrundmodus.

Umkreissuchen senden auf drei Nachkommastellen gerundete Koordinaten an ADSB.lol oder bei Ausfall adsb.fi. adsbdb erhält Hex-Kennungen/Rufzeichen. Apple erhält Kartenanfragen für den Widget-Kartenbereich. Dienste sehen technisch die IP-Adresse. Keine Analytics oder Logins. Routen und Fotos bleiben im Arbeitsspeicher; der Widget-Dateicache speichert nur echte Positionen und Suchzentrum. Bei Standortfehlern kann ein ausdrücklich veralteter Offline-Stand höchstens 30 Minuten alt angezeigt werden; dies ist keine Prognose.

ADSB.lol-Daten: ODbL 1.0. adsb.fi: nur persönliche, nichtkommerzielle Nutzung; Quellenverlinkung erforderlich, Zugang ohne Gewähr. Für kommerzielle Nutzung gesonderte Bedingungen klären: https://github.com/adsbfi/opendata/blob/main/README.md

Routendatenrechte von David Taylor und Jim Mason sowie Fotorechte beachten. Keine dauerhafte Routendatenbank oder gebündelten fremden Flugzeugfotos. Vor Veröffentlichung/Weitergabe Nutzungsbedingungen und erforderliche Genehmigungen prüfen. Das Datenschutzmanifest und die Hinweise beschreiben die Implementierung; keine rechtliche Release-Prüfung.

## Tests und Fehler melden

`python3 verify-update.py` prüft Ressourcen und Konfiguration, nicht Swift. XCTest-Fälle unter `Tests/RadarCoreTests/` prüfen Modelle, Zeitstempel, Quellenkoordination, Prognose, Cache-Kompatibilität und Übersetzungen. Dafür ist ein kompatibler Apple/iOS-Test-Runner erforderlich; reines Linux-`swift test` kann die iOS-Frameworks nicht ausführen. Gerätecheckliste: [TESTPLAN.md](TESTPLAN.md).

Bei Compilerfehlern zuerst die erste relevante Meldung und etwa 20 Zeilen Kontext aus `build.log` nennen. Bei Netzwerkfehlern Quelle, HTTP-Status und angezeigte Wartezeit nennen. Bei Widgets unterscheiden: fehlt in Auswahl, Standort verweigert, Kartenbild fehlt oder Daten veraltet. Alte `SkyNear_*_Fix`-Scripts sind für frühere Versionen und brechen auf diesem Update sicher ab.
