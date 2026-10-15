# SkyNear 1.1 Build 5: Aktualisierung ohne Server

## Änderungen

- App-Positionen werden zwischen echten Abrufen alle fünf Sekunden aus der letzten echten Koordinate, Positionszeit, Geschwindigkeit und dem Kurs vorwärts projiziert. Netzabrufe bleiben auf ungefähr 20 Sekunden begrenzt. Ein Fehler der Positionsquelle ist nicht mehr Voraussetzung für die Prognose.
- Alle drei Homescreen-Widgets haben eigene Netzwerkabrufe. Der Dienst führt parallele Anfragen zusammen, respektiert Quellenwartezeiten und fragt nach fünf Minuten eine neue Timeline an. Fehlende aktuelle Standortmessungen verwenden die letzte gespeicherte Widget-Messung mit sichtbarem Zeitstempel.
- Widgets erhalten vorausberechnete Prognosen in Minutenschritten und zusätzliche Einträge an jeder Ablaufgrenze. iOS bestimmt, wann Einträge dargestellt und neue Daten angefordert werden. Keine zugesagten sekündlichen oder garantierten minutengenauen Updates.
- Ohne gültigen Kurs, Geschwindigkeit oder Positionszeit wird nicht prognostiziert. Flugzeuge am Boden werden nicht bewegt. Solche echten Werte werden nach 90 Sekunden ausgeblendet; bewegliche Flugzeuge spätestens 15 Minuten nach ihrer echten Position. Erfolgreiche leere Antworten ersetzen den Cache mit einem leeren Ergebnis.
- Höhe und Geschwindigkeit bleiben letzte Messwerte. Prognosen tragen „Geschätzt“, gleichfarbige Marker mit gestrichelter Kontur und `~` vor Entfernungen. Richtung und „nähert sich / entfernt sich“ folgen dem gemessenen Kurs, nicht einer bekannten Flugroute.
- Das zusätzliche mittlere Widget „Flugzeug kompakt“ verwendet einen eigenen Provider ohne Kartenabruf sowie Glaskarte, Foto, Rufzeichen, Airline, Modell und metrische Werte. Die zwei großen Widgets und ihre bisherigen kind-Identifier bleiben erhalten. Alle Galerietexte bleiben feste Zeichenketten wegen des behobenen WidgetKit-Absturzes.
- Fehlt das individuelle Foto, sind lokale Modellbilder für A319, A320, A321, A320neo (A20N), A321neo (A21N) und Boeing 737-800 (B738) vorhanden. Für andere Modelle bleibt ein neutraler Platzhalter. Modellbilder sind als solche gekennzeichnet; Lackierung und Kennzeichen zeigen ein anderes Flugzeug. Quellen, Fotografen und Lizenzen sind in den App-Details und `Sources/RadarCore/Resources/ModelPhotoCredits.txt` dokumentiert. Modellbilder stehen offline zur Verfügung.
- Live Activity: ein begrenzter Aktualisierungsversuch beim Wechsel in den Hintergrund und geplante BGAppRefresh-Aufgaben. Keine Push-Berechtigung, kein Server und kein Apple-Abo hinzugefügt. Die App-Konfiguration enthält den passenden Hintergrund-Identifier und `fetch`-Modus. Bestehende ActivityKit-Isolationshelfer bleiben im Einsatz.

## Hintergrundgrenzen

iOS kann App-Refresh-Aufgaben verspätet oder gar nicht ausführen, etwa bei deaktivierter Hintergrundaktualisierung, Energiesparmodus oder nach erzwungenem Beenden der App. Eine Live Activity führt keine eigenen Netzwerkabrufe durch und besitzt keine Widget-Timeline. Zwischen tatsächlichen ActivityKit-Updates bleibt ihre Entfernung ein gespeicherter Wert. Ihr Datenzeitpunkt und abgelaufener Zustand werden angezeigt. Häufige kontinuierliche Hintergrund-Positionsupdates sind ohne zusätzliche Infrastruktur nicht garantiert.

App und Widget speichern ihren letzten Standort getrennt in ihren eigenen Sandboxes. Ein App Group wird nicht vorausgesetzt. Ein Widget muss deshalb wenigstens einmal selbst einen gültigen Standort erhalten; das Öffnen der App überträgt keinen Standort in die Extension. Ein alter Standort ist kein aktueller Nutzerstandort und wird bei Verwendung gekennzeichnet. Der Widget-Positionscache bleibt unter dem bisherigen Dateinamen lesbar; neue Modellfelder sind optional. Bundle-IDs und vorhandene Einstellungen bleiben erhalten.

## Build und Prüfung

Ubuntu, Arbeitsverzeichnis `/mnt/c/Users/Leola/Documents/iosapp/SkyNear`:

```bash
python3 verify-update.py
python3 Tests/run-portable-checks.py
bash build-ipa.sh
```

`run-portable-checks.py` kompiliert den tatsächlichen Swift-Modell-, Positionsquellen- und Prognosecode für Linux; ausschließlich nicht verfügbare iOS-Typdeklarationen und die Sprachoberfläche werden ersetzt. Es prüft Bewegung zwischen Messungen, unveränderte echte Daten, Ablauf pro Flugzeug, Minuteneinträge, Datumsgrenze, Pole, Bodendaten, fehlenden Kurs und leere Antworten. Es ersetzt keine XCTest-, WidgetKit-, ActivityKit- oder Gerätetests.

Tatsächlich ausgeführt: statische Prüfung bestanden; portable Swift-Prognosetests bestanden; Swift-6.4-/iPhoneOS27.1-Kompilierung für arm64 erfolgreich; neue IPA erzeugt; IPA-, Widget-Einstiegs-, Signierungsplatz- und Ressourcenprüfungen bestanden. Kein XCTest auf Apple-Testlaufzeit, keine Signierung, Installation oder iPhone-Laufzeitprüfung durch diese Sitzung.

Die neue IPA liegt unter `xtool/SkyNear.ipa`. Als Update signieren und installieren, einschließlich Widget-Extension. App und Extension tragen Buildnummer 5.

## Gerätetest

- Drei Widget-Designs in der Auswahl: großes Fünferwidget, großes Einzelwidget, mittleres Glaswidget.
- App geöffnet: sich bewegende Flugzeuge, veränderte Entfernungen und korrekte Schätzkennzeichnung; Höhe/Tempo bleiben bis zur nächsten Messung erhalten.
- App im Hintergrund: Widget-Datenzeit beobachten; iOS entscheidet über Netzabrufe. Vorausberechnete Positionen sollten über die Timeline wechseln, soweit iOS die Einträge ausführt.
- Temporärer Standortausfall: weiter Daten vom letzten gemessenen Standort; Zeitstempel sichtbar. Noch nie gültiger Standort: verständlicher Hinweis.
- Flugmodus: Schätzungen höchstens 15 Minuten, danach Hinweis statt alter Flugzeuge. Nach Wiederherstellung echte Daten sofort übernehmen.
- Flugzeug ohne individuelles Foto: korrektes Modellbild oder neutraler Platzhalter; Quellen in den Details prüfen.
- Live Activity starten, App verlassen, Datenzeitpunkt beobachten, App erneut öffnen und Activity beenden; Modellcode links in der Dynamic Island prüfen.
- Dunkler/heller und getönter Homescreen; kleine Schrift und Marker im mittleren Widget prüfen. Deutsch, English und Dansk in der App prüfen.


## Aktualisierung vom 14.10.2026

Widget-Erfolgscache: maximal 60 Sekunden, einschliesslich leerer Antworten. Fehler erhalten keinen eigenen Fuenf-Minuten-Cache; Quellen-Backoff und Retry-After bleiben wirksam. Netzwerkfristen betragen 4 Sekunden pro Anfrage und 5 Sekunden pro Ressource. Der Positionspfad endet nach maximal 16 Sekunden; das grosse Kartenwidget erlaubt danach bis zu 4 Sekunden fuer den optionalen Snapshot. Positionsdaten werden zuerst gespeichert und zurueckgegeben. Netzwerk-Zusatzdaten werden separat gespeichert und bei einem folgenden Aufruf wiederverwendet; lokale Modellbilder stehen sofort zur Verfuegung.

Gemeinsame Vektormarker fuer App, Detailkarte und grosses Kartenwidget: Airbus A220/A300/A310/A318/A319/A320/A321/A330/A340/A350/A380; Boeing 707/717/727/737/747/757/767/777/787; ERJ, E-Jets, CRJ, Dash 8, ATR 42/72. Hersteller- und generische Formen bleiben fuer unbekannte Typen erhalten. Die Zuordnung verwendet keine Rufzeichen.

BG-Anforderungen werden vor Einreichung auf bestehende Termine geprueft. Live-Activity-Updates und Beenden laufen in einer gemeinsamen Warteschlange; alte Datenzeiten und bereits beendete Activities werden abgewiesen. Abgebrochene wartende Updates werden verworfen.

Pruefung: Ubuntu/WSL, Swift 6.4, installiertes Apple-SDK `darwin`, iOS-Mindestversion 17. App und Extension gebaut; IPA-Struktur, Widget-Linkage, Signierungsplatz und Ressourcenpruefung erfolgreich. Portable Swift-Regressionstests erfolgreich (echte Modell-/Cache-/Prognoselogik, Plattformtypen ersetzt). Neue XCTest-Faelle liegen vor, wurden mangels Apple-Testlaufzeit nicht ausgefuehrt. iPhone-Timing, Homescreen-Toenung und Screenshots stehen gemaess TESTPLAN.md aus. Die IPA ist nicht signiert.
