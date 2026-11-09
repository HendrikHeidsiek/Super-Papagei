# Product

<!-- impeccable:product-schema 1 -->

## Platform

android, ios — eine Flutter-App mit Apple-Optik auf beiden Systemen (Cupertino-Komponenten und -Navigation, SF auf iOS, Roboto auf Android). Android behält System-Back und Insets; auf dem iPhone gelten Safe Area, Edge-Swipe-Back, Reduce Motion und Dynamic Type.

## Stack

- App: Flutter (Dart), Verteilung als APK über den eigenen Server. Kein App Store.
- Server: Python (FastAPI) im Docker-Container auf dem NAS, hinter einem Reverse Proxy mit HTTPS.
- Bibliothek: ein Ordner pro Buch auf dem NAS.

## Product

Super-Papagei ist ein Hörbuch-Player für die eigene Sammlung auf dem NAS, als schlichtere Alternative zu Audiobookshelf.

Der Kern-Mechanismus: Wer auf Abspielen tippt, bekommt das Buch sofort aufs Gerät geladen, und die Position wird lokal ständig gesichert und mit dem Server abgeglichen. Die App soll ein verlässlicher Begleiter sein: man öffnet sie und hört genau dort weiter, wo man war, auch offline.

## Users

- Ein Admin pro Haushalt, der Konten anlegt.
- Weitere Erwachsene im Haushalt mit eigenem Konto, eigenem Fortschritt und eigenen Downloads.
- Hörsituationen: unterwegs mit Kopfhörern, im Auto (Android Auto), offline; abends zum Einschlafen mit Sleep-Timer; zu Hause nebenbei.

## Content

- Hunderte Bücher, deutsch und englisch, Belletristik, Krimis, Sachbücher, Kinderklassiker.
- Pro Buch meist eine große Datei (MP3 oder M4B, 100 MB bis 1,6 GB), Cover fast immer vorhanden, Kapitel aus Tags oder `.cue`.
- Tags liefern Autor, Sprecher, Serie mit Teilnummer, Beschreibung, Genre, Jahr, Sprache.

## Brand commitments

- UI-Sprache Deutsch.
- Hell und freundlich, modern, Cover-Art groß.
- Funktionen wie Audible, Optik wie Apple (Books/Music). Konvention ist hier gewollt, auf Apple-Niveau ausgeführt.

## Must not

- Hörposition verlieren oder ungefragt überschreiben.
- Downloads abbrechen lassen, ohne dass sie von selbst weiterlaufen.
- Sich wie ein Datei-Browser oder Admin-Tool anfühlen.
