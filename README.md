# XFinder

XFinder ist ein nativer Dateimanager für macOS mit eigener SwiftUI-Oberfläche.

## Stand 0.4

- Navigation durch Ordner, inklusive Zurück, Vor und übergeordnetem Ordner
- Seitenleiste mit Favoriten und eingehängten Laufwerken
- kompakte, mehrspaltige Dateiliste mit Mehrfachauswahl wie im Finder
- halbierte vertikale Abstände in der Dateiliste
- Öffnen von Dateien mit der Standard-App
- Neuer Ordner, Umbenennen und Verschieben in den Papierkorb
- Ein-/Ausblenden versteckter Dateien
- Suche im aktuell geöffneten Ordner
- rekursive Namenssuche in allen Unterordnern mit Abbruch bei neuer Eingabe
- zusätzlicher Fundort in der Ergebnisliste
- erweiterte Standardfavoriten und dauerhaft speicherbare eigene Favoriten
- Erkennung lokaler, USB- und eingebundener Netzlaufwerke
- Schaltfläche zum Öffnen des aktuellen Pfads im originalen Finder
- vollständiges macOS-App-Icon
- eigener Einstellungsdialog (`⌘,`)
- Englisch als Standardsprache, zur Laufzeit auf Deutsch umschaltbar
- versteckte Dateien dauerhaft ein- oder ausblendbar

## Start

1. `XFinder.xcodeproj` in Xcode öffnen.
2. Als Ziel `My Mac` auswählen.
3. Mit `⌘R` starten.

Die App ist absichtlich nicht sandboxed, damit sie wie ein Dateimanager auf die
vom Benutzer erreichbaren Ordner zugreifen kann. macOS kann für geschützte
Bereiche trotzdem eine Freigabe unter „Datenschutz & Sicherheit“ verlangen.
Über `XFinder > Vollzugriff auf Festplatte konfigurieren …` lässt sich einmalig
Vollzugriff erteilen; `XFinder > XFinder-App im Finder zeigen` findet dafür die
aus Xcode gestartete App. Nach dem Aktivieren XFinder einmal neu starten.
