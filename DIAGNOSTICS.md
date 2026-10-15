# Aktualisierung und Diagnose ? Build 7

Build 7 setzt auf Build 6 auf. Es ?bernimmt neuere passende Messdaten zwischen App und Widget, wenn die tats?chliche Signierung gemeinsamen Speicher erlaubt. Die Ablehnung `BGTaskSchedulerErrorDomain:3` ist belegt; ihre Ursache auf dem Ger?t ist weiterhin zu ?berpr?fen.

## Installation und Ger?tetest

1. `xtool/SkyNear.ipa` neu signieren und als Update installieren. Bestehende Widget-Identifier bleiben erhalten.
2. App ?ffnen, Standort erlauben und Messdaten laden. Hintergrundaktualisierung aktivieren, Stromsparmodus f?r diesen Vergleich ausschalten.
3. Unter Einstellungen ? Diagnose ? Aktualisierung und Logdatei die installierte Konfiguration und gemeinsamen Speicher ansehen. `writable` best?tigt lokalen Lese-/Schreibzugriff. Erst ein `peerLastSeen` des anderen Prozesses belegt, dass beide denselben Container erreicht haben. `unavailable` erh?lt unabh?ngige Widget-Abrufe.
4. App verlassen, anschlie?end Widgets 30?60 Minuten auf dem Homescreen beobachten. Zus?tzlich mit gesperrtem Ger?t und gestarteter Live Activity pr?fen. App nicht aus dem App-Umschalter wegwischen. Echte Messzeitpunkte vergleichen; Prognosebewegung ist kein neuer Abruf.
5. Danach in betroffenen Widgets auf **Diagnose** tippen und in der App **Logdatei erstellen / aktualisieren**, danach **SkyNear-Diagnose.log teilen** verwenden.

Bei verf?gbarem gemeinsamen Speicher liest der Export aktuelle Widget-Ereignisse direkt. Andernfalls ?bertr?gt der Widget-Link h?chstens 160 Ereignisse vom Zeitpunkt der Timeline-Erstellung. Ein alter Link kann sp?tere Fehler oder Ausf?hrungen nicht zeigen. Der Bericht nennt den letzten verf?gbaren Widget-Zeitpunkt; fehlende Eintr?ge beweisen keine ausgebliebene Ausf?hrung.

## ?nderungen

- Installierte Bundle-ID, Task-ID, erlaubte Task-IDs und Hintergrundmodi werden protokolliert. Nach Umbenennung durch ein Signierungswerkzeug verwenden SwiftUI-Handler und Antrag dieselbe eindeutig passende installierte ID.
- Nach erfolgreicher Einreichung wird gepr?ft, ob der Antrag aussteht. Handler-Aufruf, kurzer Abruf beim Verlassen der App und sp?terer geplanter Abruf erscheinen getrennt im Log. Ausstehende Antr?ge werden nicht verschoben.
- Ein optionaler App-Group-Container wird durch einen Schreib-/Lesetest gepr?ft. `SkyNearAppGroup` in beiden Info.plists nennt den Kandidaten. Dieser Eintrag ersetzt keine g?ltigen App-Group-Entitlements. Beide Prozesse m?ssen tats?chlich denselben Container erreichen.
- Gemeinsame Messdaten werden atomar gespeichert, auf 20 nahe Flugzeuge begrenzt und enthalten keine Fotos. ?ltere Messzeiten ?berschreiben keine neueren; erfolgreiche leere Antworten ersetzen alte Flugzeuge. Fremde Regionen, Prognosen und abgelaufene Cache-Werte werden nicht als aktuelle gemeinsame Daten verwendet.
- Die App fordert nach gespeicherten Umgebungsdaten h?chstens einmal pro Minute einen Widget-Reload an, vor optionaler Anreicherung. Reload-Anforderung und tats?chlicher Provider-Aufruf sind unterschiedliche Ereignisse.
- Unabh?ngige Widget-Abrufe behalten 60 Sekunden Erfolgscache, Quellen-Backoff, begrenzte Netzlaufzeit und die Anforderung einer neuen Timeline nach f?nf Minuten.
- Live Activities verwenden sp?testens Messzeit + 60 Sekunden als `staleDate`; das Prognoseende bleibt separat erhalten. Das Alter wird zus?tzlich relativ angezeigt. Sp?te Antworten und beendete Activities bleiben abgesichert.
- Das kompakte Widget f?llt seine Fl?che. Flugzeugmarker haben eine gerundete Nase, verj?ngtes Heck und schlankere Fl?gel ohne schwarzen Kreis f?r gemessene Positionen. Prognosen behalten dieselbe Farbe und die gestrichelte Umrandung. Visuelle Ger?tepr?fung steht aus.

## Signierte IPA vergleichen

`python3 inspect-install-ipa.py path/to/signed-SkyNear.ipa`

Das Werkzeug zeigt ausschlie?lich ausgew?hlte Konfigurationseintr?ge und Abweichungen vom Quellstand. Es liest keine Zertifikate, Profile oder Schl?ssel aus. Im aktuellen `logfiles`-Ordner liegt keine signierte IPA; der Vergleich mit der tats?chlich installierten Datei steht aus.

## Auswertung

- **Planung:** `submitted` und `submission verification pending=true` belegen eine angenommene Planung. `SwiftUI handler invoked` belegt den sp?teren tats?chlichen Einstieg.
- **Widget:** Ein Provider-Aufruf mit erfolgreicher Positionsantwort bzw. neuerem gemeinsamem Messstand belegt neue Daten. `timeline ready` belegt die Bereitstellung, keine garantierte Anzeigezeit durch iOS.
- **Live Activity:** `live update begin/returned` dokumentiert die ?bergabe. Die Systemdarstellung wird auf dem Ger?t gepr?ft.

Dateizeiten sind UTC, Anzeigen in der App verwenden Ortszeit. `real` bezeichnet die Quellenzeit, `display` den Prognosezeitpunkt. Je Journal werden h?chstens 512 KiB gespeichert; alte Ereignisse rotieren heraus, zusammengef?hrte Ereignisse werden anhand ihrer ID dedupliziert. Koordinaten, Flugzeugkennungen, URLs, Zugangsdaten und Zertifikate werden nicht protokolliert. Reale Positionen im privaten Cache werden f?r die Anzeige gespeichert.

## Pr?fgrenzen

Portable Swift-Tests pr?fen echte Modell-, Prognose-, Cache- und Dateilogik mit Ersatzdeklarationen f?r nicht verf?gbare iOS-Typen. XCTest, App-Group-Zugriff, Signierung, Hintergrundstarts, Widget-Anzeige und Teilen-Interaktion ben?tigen einen Apple-Test-Runner beziehungsweise das Ger?t. Ein Server wurde nicht eingerichtet; die sp?tere Server-/Push-Entscheidung h?ngt vom Ger?tebefund ab.


## Ausgef?hrt am 15.10.2026

- Finaler WSL-/Ubuntu-Build mit Swift 6.4 und installiertem darwin-SDK: `bash build-ipa.sh`, erfolgreich (App und Extension Build 7).
- `verify-ipa.py`, `verify-widget-ipa.py`, `verify-signing-space.py`, `verify-update.py --ipa`: erfolgreich.
- `Tests/run-portable-checks.py`: erfolgreich, einschlie?lich gemeinsamem Positionscache, leerer neuer Antwort, Messzeit-Reihenfolge, Region, Ablauf, Prognose-Ablehnung, nicht blockierender Sperre und Activity-Frischegrenze.
- `Tests/run-diagnostic-checks.py`: erfolgreich f?r Persistenz, Zusammenf?hrung, Deduplizierung, Rotation, Bereinigung und nicht blockierende Sperren.
- `inspect-install-ipa.py xtool/SkyNear.ipa`: beide Build-Versionen und die verpackten Hintergrund-/Gruppenkonfigurationen entsprechen den Quelldateien.
- Artefakt: `xtool/SkyNear.ipa`, 6.309.023 Byte. IPA ist noch zu signieren.
- Nicht ausgef?hrt: Apple-XCTest-Runner, Pr?fung einer signierten Installationsdatei, App-Group-/Hintergrundlaufzeit und visuelle Tests auf dem Ger?t.
