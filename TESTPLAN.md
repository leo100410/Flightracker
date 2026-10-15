# SkyNear: Prüfplan auf deinem iPhone

Checkliste für SkyNear 1.1. Am 14.10.2026 wurden statische Prüfung, Swift-/iOS-Build, IPA-Erzeugung und alle drei IPA-Prüfer in der Codex-Sitzung erfolgreich ausgeführt. XCTest und Gerätetests stehen aus. Frühere erfolgreiche Gerätetests der bisherigen App gelten nicht automatisch für dieses Update.

**Gerätebefund Build 2 auf iOS 27.0: Regressionen bestätigt durch Nutzerbericht.** Platzhalterkästen statt Widgettext, Kartenwidget nicht nutzbar, Live Activity unsichtbar trotz Buttonwechsel auf Beenden. Build 3 enthält gezielte Korrekturen; untenstehende Gerätechecks und [REGRESSION_FIX.md](REGRESSION_FIX.md) bleiben offen.

## Build und Installation

- [x] Swift 6 baut App und Extension mit dem tatsächlich installierten SDK.
- [x] build-ipa.sh zeigt eine neue IPA und verify-ipa.py ist erfolgreich.
- [ ] ESign erhält und signiert die eingebettete Widget-Extension.
- [ ] App startet auf iOS 17 oder neuer.
- [ ] SkyNear erscheint in der Widget-Auswahl.

## Standort

- [ ] Erststart fragt nach Standort mit verständlicher Zweckbeschreibung.
- [ ] Erlauben lädt die lokale Karte und den Bereich In deiner Nähe.
- [ ] Verweigern zeigt einen echten Hinweis, keine Demo-Flugzeuge.
- [ ] Standort ungefähr freigeben; Entfernung bleibt ausdrücklich standortabhängig.
- [ ] Nach Freigabe über iPhone-Einstellungen funktioniert ein erneuter Abruf.
- [ ] Beim Sperren wird keine heimliche Dauerortung gestartet.

## Netzwerk und Flugzeuge

- [ ] Flugzeugmarker auswählen; Referenzdaten werden geladen.
- [ ] Unbekanntes Flugzeug, fehlende Route und fehlendes Foto bleiben als unbekannt markiert.
- [ ] Airline und eingetragener Eigentümer werden nicht verwechselt.
- [ ] Flughäfen, Modell und Foto anhand derselben Registrierung/Rufzeichen manuell gegenchecken.
- [ ] 10000 Fuß entsprechen 3048 m; 100 Knoten entsprechen rund 185 km/h.
- [ ] Flugmodus: Fehler sichtbar, alter Kartenstand nicht als frisch bezeichnet.
- [ ] HTTP 429 erzeugt Hinweis, keine Endlosschleife mit sofortigen Retries.
- [ ] Kartenregion in ein anderes Land verschieben: neue Region lädt; die fünf nächsten beziehen sich weiter auf dein iPhone.
- [ ] Kartenradius ändern: Anzahl der Kartenmarker ändert sich, Umgebungsübersicht sucht weiter bis 463 km.
- [ ] Weniger als fünf erfasste Flugzeuge werden nicht durch erfundene Flugzeuge ergänzt.

## Widget

- [ ] Großes Widget zeigt alle verfügbaren Reihen bis maximal fünf ohne abgeschnittene letzte Reihe.
- [ ] Je Reihe: Foto oder Kein Foto, Rufzeichen, Airline, Route, Modell, Höhe, Tempo, Entfernung.
- [ ] Lange Airline-/Modellnamen werden gekürzt; vollständige Werte stehen in der Detailansicht.
- [ ] Standortfreigabe ausdrücklich auch für Widget erteilen.
- [ ] Aktualisierungszeitpunkt ist sichtbar und wird nicht mit einer Animation simuliert.
- [ ] Fehler: höchstens 30 Minuten alter Offline-Positionsstand wird als VERALTET angezeigt.
- [ ] Erster Widgetaufruf ohne Daten zeigt Standort-/Fehlerhinweis, keine erfundenen Flüge.
- [ ] Antippen öffnet App im Bereich In deiner Nähe; bei noch vorhandenem Flug Detailansicht.
- [ ] Standortruf schlägt nach begrenzter Wartezeit fehl, statt unbegrenzt hängen zu bleiben.

## Live Activity

- [ ] Start mit geladenen Flugzeugen zeigt Sperrbildschirmansicht.
- [ ] Maximum fünf Reihen bleiben innerhalb der systemseitigen Darstellungsgrenzen lesbar.
- [ ] Dynamic Island kompakt zeigt echten kurzen Modellcode links, Entfernung rechts; aufgeklappt fünf kurze Flugzeilen.
- [ ] Aktive App aktualisiert den Datenstand.
- [ ] Suspendierte App: alter Stand ist nach 60 Sekunden sichtbar als veraltet, kein behauptetes Dauer-Live.
- [ ] Live Activities deaktiviert: verständliche Fehlermeldung.
- [ ] Beenden entfernt die Activity.
- [ ] App-Neustart kann die vorhandene Activity wieder beenden.

## Quellen, Abrufbudget und Fehler

- [ ] Anfragen anhand Netzwerkprotokoll oder kontrollierter HTTP-Testantworten prüfen: keine Positionsabrufe jede Sekunde, regulär ungefähr 20 Sekunden Abstand.
- [ ] Mehrfach aktualisieren, Karte schnell bewegen, Radius ändern und App wechseln: keine parallelen Positionsrequests, kein Rücksetzen des Budgets, nur die letzte gewünschte Region wird übernommen.
- [ ] Bei entfernter Karte bleibt die Umgebung am Geräteort; höchstens ein zusätzlicher Umgebungsabruf pro Minute, auch wenn der Kartenabruf scheitert.
- [ ] Primärquelle liefert 429 mit Retry-After: adsb.fi-Fallback einmalig, ADSB.lol bleibt bis zur angegebenen Zeit gesperrt.
- [ ] 403/400 lösen keine Endlosschleife aus; Zugriffsfehler haben längere Sperrzeit. Keine umgehenden Wiederholungen nach Kartenbewegung.
- [ ] Timeout/5xx beider Quellen: Fehler beider Quellen und nächste erlaubte Zeiten sichtbar; Backoff wächst bis fünf Minuten, länger bei Retry-After.
- [ ] Wiederkehr echter Daten ersetzt Prognosen ohne Warten auf ADSBDB-/Foto-Anreicherung.
- [ ] Erfolgreiche leere Antwort bleibt leer; kein Fallback allein wegen fehlender Flugzeuge und keine Wiederbelebung alter Positionen.
- [ ] ADSBDB-/Fotofehler verändern nicht die erfolgreiche Positionsquelle.
- [ ] Datenquelle und echte Datenzeit in Karte, Übersicht, Widgets und Live Activity nachvollziehbar.

## Sprachen

- [ ] Deutsch → English → Dansk in offener App wechseln: Tabs, Einstellungen, Details, Fehler und unbekannte Werte sofort passend.
- [ ] App beenden/öffnen: Sprachwahl und bisheriger Kartenradius bleiben gespeichert.
- [ ] Einheiten bleiben m, km/h und km; Rufzeichen, Modell-/Flughafencodes und Airline-Namen bleiben identisch.
- [ ] Beide direkt registrierten deutschen Widgetformen hinzufügen; nach Reload und Neustart bleiben sie nutzbar. Haupt-App weiterhin Deutsch/English/Dansk, Live Activity folgt App-Sprache.
- [ ] Laufende Live Activity folgt geänderter App-Sprache, ohne eine zweite Activity zu erzeugen.
- [ ] Lange englische/dänische Texte, große Schrift und VoiceOver auf Lesbarkeit prüfen.

## Einzel-Flugzeug-Widget und Tönung

- [ ] Beide großen deutschen Widgetformen erscheinen in der Auswahl; bestehende deutsche Fünfer-Platzierung bleibt ohne Konfigurationsmigration nutzbar. Entfernte English-/Dansk-Varianten aus Build 2 durch aktuelle Widgets ersetzen.
- [ ] Neues Widget zeigt genau das nächste erfasste Flugzeug: Rufzeichen, Airline, Modell, optionales Foto, Höhe, Geschwindigkeit, Entfernung und bekannte Route.
- [ ] Karte enthält tatsächlichen Nutzer- und Flugzeugmarker; Informationskarte verdeckt die Marker nicht. Kartenattribution sichtbar.
- [ ] Snapshot-Timeout oder fehlendes Netz: Informationskarte bleibt sichtbar; kein erfundenes Kartenbild.
- [ ] iOS 17 sowie neuere iOS-Versionen: heller/dunkler Homescreen, Tönung/klare Darstellung; dunkle Materialkarte und Texte bleiben lesbar.
- [ ] Beide Widgets gleichzeitig aktiv: gemeinsamer Dienst innerhalb der Extension statt doppelter gleichzeitiger Abrufe. Getrennte App-/Extension-Budgets berücksichtigen.

## Prognose und Ablauf

- [ ] Nach echten Flugdaten beide Quellen ausfallen lassen: nur geeignete bereits erfasste Flugzeuge werden projiziert; Geschätzt/Estimated/Estimeret, gleichfarbige Marker mit gestrichelter Umrandung und ~ an Entfernungen.
- [ ] Letzte echte Position einschließlich Messzeit bleibt nachvollziehbar. Höhe und Kurs werden nicht als neue Messungen ausgegeben.
- [ ] Fehlende Zeit, fehlender Kurs/Fart, ungültige Werte oder Bodenstatus verhindern Prognose. Alter v1-Cache ohne Messzeit wird nicht projiziert.
- [ ] App-Messung plus seen_pos: Ende exakt höchstens 15 Minuten nach echter Position, nicht 15 Minuten nach Fehler oder Abruf. Bei App-Aktivität danach keine Prognosemarker mehr.
- [ ] Lange Ausfälle, Neustart, wiederholtes Aktualisieren und neue Widget-Timeline verlängern die Prognosefrist nicht.
- [ ] Geöffnete Details erhalten neue echte/geschätzte Koordinaten über Flugzeug-ID; abgelaufene Position wird nicht weiter als aktuell auf der Detailkarte gezeigt.
- [ ] Widget-Prognoseeinträge werden vom ursprünglichen Messpunkt neu berechnet; Endzustand enthält keine prognostizierten Flugzeuge. Systembedingte Verzögerungen dokumentieren.
- [ ] Suspendierte App: Live Activity projiziert nicht selbständig weiter. Prognose bleibt sichtbar gekennzeichnet und wird am staleDate als abgelaufen behandelt; keine sekundengenaue Hintergrundgarantie.
- [ ] Dynamic Island mit A320/B737 und fehlendem typeCode testen: kein aus Rufzeichen geratener Code; bei Ablauf der Prognose keine geschätzte Entfernung mehr als gültig darstellen.

## Automatisierte Prüfungen

- [x] `python3 verify-update.py`: statische Ressourcen-/Konfigurationsprüfung erfolgreich.
- [x] `bash build-ipa.sh`: tatsächlicher Swift-/iOS-Build und alle drei IPA-Prüfer erfolgreich; ausschließlich neue IPA verwenden.
- [ ] `RadarCoreTests` auf kompatiblem Apple/iOS-Test-Runner: ModelTests, PredictionTests, PositionSourceTests und PositionCoordinatorTests ausführen; Ergebnis dokumentieren.
- [ ] ESign erhält die eingebettete Extension und signiert sie gültig; beide Widgets und Live Activity laufen auf dem iPhone.


## Marker- und Aktualisierungsupdate (14.10.2026)

- [ ] Mittleres Widget bleibt nach Update platziert; zeigt Glasflaeche, Foto/Modellbild und Flugdaten ohne Karte.
- [ ] A319/A320/A321, 737/MAX, 747 und Turboprops auf Hauptkarte und grossem Widget vergleichen; Kurs 0/90/180/270 Grad und Antippflaechen pruefen.
- [ ] Gemessene und geschaetzte Marker behalten ihre Farbe; Prognose hat gestrichelte Kontur und ~ bei Entfernung.
- [ ] Alle drei Widgets platzieren. Datenzeit vor/nach von iOS gestarteten Provider-Aufrufen vergleichen, auch bei geschlossener App.
- [ ] Quelle nach Fehler wieder erreichbar: nach Quellen-Backoff erneuter Abruf, keine pauschale Fuenf-Minuten-Fehlersperre.
- [ ] Voruebergehender Standortausfall zeigt letzten Standort samt Messzeit, auch neben Quellenfehlern.
- [ ] App mehrfach verlassen: geplanter BG-Termin wird nicht nach hinten verschoben. Activity beenden waehrend Abruf laeuft; keine Wiederbelebung oder Rueckschritte der Datenzeit.
- [ ] iOS 17 und getoenter Homescreen: Textkontrast, Glasflaeche und Symbole visuell pruefen und Screenshots aufnehmen.

Diagnose: Unified Logging, Subsystem `de.leola.skynear`, Kategorie `Refresh`. Provider-Aufruf, Zusammenfassung paralleler Abrufe, Erfolgscache, Quellenantwort/Fehler, Timeout und Timeline werden protokolliert. `real` ist die echte Datenzeit; `display` ist der Anzeigezeitpunkt. Keine Koordinaten oder Flugzeugkennungen im Log.


## Build 7: Hintergrundplanung und gemeinsamer Messstand

- [ ] Installierte Bundle-ID, Task-ID, erlaubte IDs und fetch-Modus im Diagnosebericht pr?fen. Signierte IPA mit `inspect-install-ipa.py` vergleichen.
- [ ] Bei Annahme: `submission verification pending=true`; sp?terer geplanter Start muss `background SwiftUI handler invoked` zeigen. Ablehnung Code 3 nicht als behoben werten, solange Ger?tebeleg fehlt.
- [ ] Gemeinsamer Speicher: `writable` in beiden Prozessen und jeweils `peerLastSeen` vorhanden. Ohne Zugriff weiterhin unabh?ngige Widget-Abrufe und Diagnose-Link nutzbar.
- [ ] Neue App-Messung bei anschlie?endem Widget-Aufruf ?bernommen; erfolgreiche leere Antwort l?scht vorherige Flugzeuge. Nach Neustart keine ?ltere Messung aus Cache ?bernehmen.
- [ ] 30?60 Minuten ohne ge?ffnete App testen, ?ber mehrere angeforderte F?nf-Minuten-Termine hinaus. Anschlie?end aktuelle Logdatei exportieren und tats?chliche Widget-Abdeckung pr?fen.
- [ ] Live Activity: Alter sichtbar, nach 60 Sekunden veraltet; Prognoseende separat. Beenden w?hrend laufendem Abruf bleibt wirksam.
- [ ] Kompaktes Widget f?llt Fl?che; keine innere schwarze Randfl?che. Marker auf heller/dunkler Karte und get?ntem Homescreen pr?fen; Drehung 0/90/180/270 Grad, ausreichende Antippfl?che, gleiche Farbe bei Prognosen.
- [ ] Neue XCTest-Klasse SharedPositionsTests auf Apple-Testsystem ausf?hren. Portable Ersatztests ersetzen diese Ger?tepr?fung nicht.
