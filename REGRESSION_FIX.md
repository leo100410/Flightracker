# SkyNear 1.1 Build 4: gezielte WidgetKit-Korrektur

## Aktueller Befund und Änderung

Build 3 blieb auf dem iPhone fehlerhaft. Die 25 SkyNearWidgets-Absturzberichte in `logfiles/` betreffen Build 2 (20 Berichte) und Build 3 (5 Berichte). Alle zeigen EXC_BREAKPOINT in WidgetKit ausgehend von `NearbyWidget.body`. Der Rücksprungoffset des Build-3-Berichts `SkyNearWidgets-2026-10-14-185655.ips` wurde mit der Extension-Binärdatei abgeglichen: Der unmittelbar vorherige Aufruf ist `configurationDisplayName(LocalizedStringKey)`. Ein genauer Assertion-Text ist im Bericht nicht enthalten.

Die vom Nutzer signierte IPA enthält dieselbe Extension-UUID und denselben Code-Section-Hash wie unsere Build-3-IPA. Eine alte Extension-Version erklärt den Fehler daher nicht.

Build 4 ersetzt in beiden Widgets interpolierte Galerietitel und dynamische Beschreibungen durch feste deutsche Texte. Beide Widget-Designs, kind-Identifier, Live Activity, Haupt-App und Datenpfade bleiben erhalten. App und Extension tragen Buildnummer 4. Weitere spekulative Änderungen wurden nicht vorgenommen.

Der gemeinsame Extension-Absturz erklärt die fehlerhafte Widget-Galerie und die Platzhalterdarstellung. Dass er auch das Verschwinden der Live Activity verursacht, ist plausibel, aber noch nicht abschließend durch einen Gerätetest belegt.

## Tatsächliche Prüfung von Build 4

- `python3 verify-update.py` in Ubuntu: bestanden.
- `bash build-ipa.sh` in Ubuntu: tatsächliche Swift/iOS-Kompilierung erfolgreich; neue `xtool/SkyNear.ipa` erzeugt.
- IPA-Struktur, arm64-Code, Widget-Einstiegspunkt, Platz für Signierung, Ressourcen, beide Widget-Identifier und Live-Activity-Konfiguration: Paketprüfungen bestanden.
- Keine XCTest-Ausführung, Signierung, Installation oder iPhone-/Widget-Laufzeitprüfung durch diese Sitzung.

Gerätetest: Build 4 mit erhaltener und mit signierter Extension als Update installieren. Beide großen Widgets müssen in der Auswahl erscheinen; das Fünferwidget muss Daten oder einen verständlichen Hinweis zeigen; das Einzelwidget muss genau ein Flugzeug mit Karten-/Glass-Ansicht zeigen. Live Activity starten und beenden; Dynamic Island links auf tatsächlichen Modellcode prüfen. Bei weiterem Fehler nur neue, zu Build 4 gehörende SkyNearWidgets-Absturzberichte und den angezeigten App-Fehler auswerten.

## Historischer Bericht zu Build 3

Die folgenden Angaben dokumentieren den vorherigen Reparaturversuch; dessen Erfolg auf dem iPhone wurde nicht bestätigt.

## Status und Gerätebefund

Build 2 war kompiliert und strukturell geprüft, ist aber auf deinem iPhone **nicht erfolgreich**: iOS 27.0 zeigte Platzhalterkästen im Fünferwidget; das Kartenwidget war nicht nutzbar; Activity.request änderte den Button auf Beenden, ohne sichtbare Live Activity. Diese Gerätebefunde haben Vorrang vor dem früheren Buildbericht.

Build 3 enthält gezielte Korrekturen. Die Erfolgskriterien bleiben bis zu deinem neuen Gerätetest offen. Kein iPhone-Test wurde in dieser Sitzung durchgeführt.

## Belegte Befunde und Grenzen der Ursachenanalyse

- Die alte IPA enthielt genau eine WidgetKit-Extension mit Code, Standortkonfiguration, Ressourcen und passendem Swift-Einstiegspunkt. Ein fehlendes .appex war damit nicht die belegte Ursache.
- Bereits Build 2 verwendete StaticConfiguration/TimelineProvider, keine AppIntentConfiguration. Keine App-Intents-Metadaten im Paket; für diese statischen Widgets werden sie nicht benötigt.
- Die alte Registrierung bestand aus verschachtelten Sprach-Widgetgruppen plus Live Activity. Ob genau diese Gruppierung iOS 27.0 am Darstellen hinderte, ist ohne Extension-/Gerätelog nicht bewiesen.
- Der Textstart griff auf Bundle.module zu. Dessen erzeugter Zugriff enthält fatalError bei fehlender Bundle-Auflösung; der äußere guard fängt das nicht ab. Das ist ein belegter Absturzpfad, aber kein bestätigter Crash auf deinem iPhone.
- getSnapshot lieferte immer ein leeres Datenmodell. Timeline-Abschlüsse warteten ohne Gesamtfrist auf Standort, Primär-/Fallbackabruf, Metadaten und Fotos; das Kartenwidget zusätzlich auf den Snapshot. Diese Verzögerungspfade sind im Code belegt.
- Der Startbutton konnte beim gemeinsamen liveOperationInProgress still zurückkehren. Initialisierung übernahm die erste Activity-ID ohne Prüfung auf beendet/verworfen. Dass dein Button tatsächlich zu Beenden wechselte, spricht im gemeldeten Fall jedoch für einen angenommenen Start und ein anschließendes Darstellungsproblem.

## Änderungen

- Direkt im WidgetBundle stehen ausschließlich NearbyWidget, NearestAircraftWidget und NearbyLiveActivity. Keine verschachtelten Sprachgruppen. Unverändertes Fünfer-kind: SkyNear.Nearby.v1; neues Einzel-kind: SkyNear.Nearest.v1. Beide Designs bleiben große statische Widgets.
- Widgets vorläufig nur Deutsch. Haupt-App-Sprachwahl, ihr gespeicherter Key und die Live-Activity-Sprache bleiben erhalten. Diese Einschränkung wird in der App erklärt.
- Deutsche Widgets benötigen zum Initialisieren ihrer normalen Texte keine Ressourcendatei. Andere Texte und Quellenhinweise verwenden eine optionale Bundle-Auflösung statt eines potentiell fatalen Module-Zugriffs.
- Echte getSnapshot-Aufrufe laden Daten; Galerie-Vorschauen zeigen Hinweise. Platzhalter-/Fehlertexte sind ausdrücklich unredacted, Flugzeugdaten werden dadurch nicht pauschal von Datenschutzdarstellung ausgenommen.
- Datenservice: Gesamtfrist 12 Sekunden, Standortfrist 4 Sekunden, kurze einzelne Netzwerkfristen. Die Karte erhält zusätzlich ihre bisherige 4-Sekunden-Frist. Die Uhrfristen erfordern laufende Systemausführung; iOS kann Extension-Prozesse unabhängig beenden.
- Bereits geladene Positionen werden vor optionalen Fotos/Referenzdaten verfügbar und gecacht. Bei Zeitüberschreitung erscheinen Positionen mit Hinweis oder ein Fehlertext. Die Extension hält für ihre Anzeige fünf Flugzeuge statt eines ganzen Regionalfeeds. Haupt-App-Datenpfade und gespeicherte App-Daten werden nicht zurückgesetzt.
- Live Activity: getrennte Startsperre und Updatesperre; aktive/veraltete IDs werden mit ActivityKit abgeglichen, abgeschlossene/verworfenene IDs entfernt. Zu beendende IDs werden während einer laufenden Endoperation nicht erneut übernommen. Aktionen haben Fortschritt, Timeout und sichtbare Rückmeldung; spätere Updates können keinen neuen Start überschreiben.
- Permission, Gerätestandort, nichtleere Flugdaten und 4-KB-Nutzdatenlimit werden geprüft. Request-Fehler zeigen NSError-Domain, Code, Beschreibung und gegebenenfalls Fehlergrund. Systemannahme wird als Annahme bezeichnet, nicht als bestätigte Sichtbarkeit.

## Prüfung

Tatsächlich ausgeführt: statische Prüfung in Ubuntu erfolgreich; Swift-6.4-/iPhoneOS27.1-Build (arm64, Mindestziel iOS 17) erfolgreich; neue IPA erzeugt; alle drei IPA-Prüfer und die erweiterte Paketprüfung bestanden. Buildnummer 3 ist in App und Extension vorhanden. Keine XCTest-Ausführung, Signierung oder Installation auf dem iPhone durch diese Sitzung.

Aktueller Ubuntu-Workflow: python3 verify-update.py, danach bash build-ipa.sh. Das Script baut nur eine Instanz, akzeptiert nur frisch erzeugte IPAs und führt die vorhandenen drei IPA-Prüfer sowie die erweiterte tatsächliche Paketprüfung aus.

Die Paketprüfung kontrolliert aktuelle Buildnummer 3, unveränderte App-/Extension-IDs, beide kind-Strings, alle drei Widget-Code-Typen, Standort-/Live-Activity-Konfiguration und identische Ressourcen in App und Extension. Der Mach-O-Prüfer kontrolliert zusätzlich, dass __swift5_entry tatsächlich auf das definierte _main zeigt. Das ist weiterhin kein iOS-Widget-Registrierungs- oder Darstellungstest.

Keine alten Reparaturscripts angewendet, keine Installation oder Cache-Löschung. Sicherung vor der Korrektur: patch-backups/regression-20261014-183614/.

## Dein Gerätetest

Die neu erzeugte xtool/SkyNear.ipa mit unveränderten Bundle-IDs als Update signieren/installieren; die Extension muss erhalten und mit signiert werden. In der Galerie die zwei großen deutschen Designs wählen. Alte English-/Dansk-Sprachvarianten aus Build 2 sind in Build 3 nicht mehr registriert.

- [ ] Beide Homescreen-Widgets erscheinen in der Auswahl.
- [ ] Fünferwidget zeigt Daten oder einen lesbaren konkreten Hinweis.
- [ ] Einzelwidget zeigt genau ein Flugzeug mit Karten-/Materialansicht; Kartenfehler lassen die Informationskarte sichtbar.
- [ ] Start zeigt Live Activity auf Sperrbildschirm/Dynamic Island; Beenden entfernt sie. App-Neustart, vom System verworfene Activity und erneuter Start testen.
- [ ] Dynamic Island links zeigt den tatsächlichen Modellcode, rechts die Entfernung.

Wenn erneut Kästen oder eine unsichtbare, vom System angenommene Live Activity auftreten, ist die gemeinsame Extension-Darstellung weiterhin fehlerhaft. Dann sind der genaue neue App-Status und ein Extension-Crash-/Gerätelog die nächsten Belege; erfolgreicher Build ersetzt sie nicht.
