---
version: 1
slug: "app-lib"
primary_target: "app/lib"
related_targets: []
---

# Super-Papagei App (alle Screens)

Scope: die ganze Flutter-App unter app/lib. Mode: Operate.

Audience/Job: Haushaltsmitglieder hören ihre NAS-Hörbücher; Job: weiterhören wo man war, stöbern, Bücher offline haben.
Constraints: hell und freundlich, modern, Cover groß. Nutzer wählte den Branchenstandard: "Funktionen von Audible, Optik von Apple" (Apple Books / Apple Music).

## Direction contract

THESIS: Ein Hörbuchplayer, der aussieht wie eine Apple-App und so viel kann wie Audible. Er verweigert das dunkle Streaming-Dashboard und das Bastel-Bibliotheksgefühl von Audiobookshelf.

OWN-WORLD: Weißer Grund (iOS systemBackground), gruppierte hellgraue Listen (#F2F2F7), Systemschrift, Large Titles, eine Tint-Farbe Orange (#E8590C, Text-Variante #C2410C), Cupertino-Icons, weiche Cover-Schatten mit Versatz, 10–12 pt Coverradius. Dark Mode als echtes zweites Erscheinungsbild.

STORY: Öffnen, sofort das laufende Buch groß sehen, ein Tipp spielt weiter. Bibliothek ist eine Cover-Wand, die man filtert und durchsucht. Jedes Buch zeigt klar, ob es geladen ist.

FIRST VIEWPORT: Start-Tab: Large Title "Start", darunter das zuletzt gehörte Buch als großes Cover (ca. 60 % Breite) mit Titel, Kapitel, Restzeit und einem gefüllten Weiterhören-Knopf. Darunter horizontale Reihen "Weiterhören", "Als Nächstes in deinen Serien", "Neu in der Bibliothek". Mini-Player über der Tab-Leiste (Start, Bibliothek, Downloads, Profil).

FORM: Branchenstandard (canon), auf Apple-Niveau ausgeführt; Signatur: Vollbild-Player wie Apple Music, Hintergrund in hellem Ton der Cover-Farbe, Cover nie getönt. seed: dca72b5c65892159

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
