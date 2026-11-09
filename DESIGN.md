---
name: Super-Papagei
description: Private audiobook player for the household NAS. Audible's features, Apple Books / Apple Music's look.
colors:
  tint: "#E8590C"
  tint-text: "#C2410C"
  tint-fill: "#C2410C"
  on-tint: "#FFFFFF"
  background: "#FFFFFF"
  grouped: "#F2F2F7"
  card: "#FFFFFF"
  label: "#000000"
  secondary: "#6C6C70"
  tertiary: "#8E8E93"
  separator: "#D1D1D6"
  fill: "#EDEDF0"
  success: "#248A3D"
  danger: "#D70015"
  dark-tint: "#FF8A3D"
  dark-tint-text: "#FF9F5A"
  dark-tint-fill: "#FF8A3D"
  dark-on-tint: "#000000"
  dark-background: "#000000"
  dark-grouped: "#000000"
  dark-card: "#1C1C1E"
  dark-label: "#FFFFFF"
  dark-secondary: "#AEAEB2"
  dark-tertiary: "#8E8E93"
  dark-separator: "#38383A"
  dark-fill: "#2C2C2E"
  dark-success: "#30D158"
  dark-danger: "#FF453A"
  snackbar-light: "#1C1C1EF2"
  snackbar-dark: "#F2F2F7F2"
typography:
  large-title:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.37px"
  title-1:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.36px"
  title-2:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.26px"
  title-3:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.45px"
  headline:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.43px"
  body:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.43px"
  subhead:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.23px"
  footnote:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.08px"
  footnote-emphasis:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "13px"
    fontWeight: 600
    letterSpacing: "-0.08px"
  caption:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "12px"
    fontWeight: 500
    letterSpacing: "0px"
  tab-label:
    fontFamily: "SF Pro (iOS system), Roboto (Android system)"
    fontSize: "11px"
    fontWeight: 500
    letterSpacing: "0px"
rounded:
  cover-thumb: "5px"
  cover-row: "6px"
  cover-tile: "8px"
  cover-large: "12px"
  group: "12px"
  sheet: "14px"
  pill: "18px"
  app-icon: "19px"
spacing:
  hairline: "0.5px"
  xs: "6px"
  sm: "8px"
  md: "12px"
  shelf-gap: "14px"
  inset: "16px"
  gutter: "20px"
  grid-row: "22px"
  section: "28px"
components:
  button-filled:
    backgroundColor: "{colors.tint-fill}"
    textColor: "{colors.on-tint}"
    typography: "{typography.headline}"
    rounded: "{rounded.cover-large}"
    padding: "0 18px"
    height: "50px"
  button-filled-dark:
    backgroundColor: "{colors.dark-tint-fill}"
    textColor: "{colors.dark-on-tint}"
    typography: "{typography.headline}"
    rounded: "{rounded.cover-large}"
    padding: "0 18px"
    height: "50px"
  button-filled-secondary:
    backgroundColor: "{colors.fill}"
    textColor: "{colors.tint-text}"
    typography: "{typography.headline}"
    rounded: "{rounded.cover-large}"
    padding: "0 18px"
    height: "50px"
  link-action:
    textColor: "{colors.tint-text}"
    typography: "{typography.body}"
    padding: "0 8px"
    height: "44px"
  chip-filter:
    backgroundColor: "{colors.fill}"
    textColor: "{colors.label}"
    typography: "{typography.subhead}"
    rounded: "{rounded.pill}"
    padding: "0 16px"
  chip-filter-selected:
    backgroundColor: "{colors.label}"
    textColor: "{colors.background}"
    typography: "{typography.subhead}"
    rounded: "{rounded.pill}"
    padding: "0 16px"
  grouped-section:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.group}"
    padding: "0 16px"
  grouped-row:
    backgroundColor: "{colors.card}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    padding: "11px 16px"
    height: "48px"
  text-field:
    backgroundColor: "{colors.card}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.group}"
    padding: "14px 16px"
  mini-player:
    backgroundColor: "{colors.card}"
    textColor: "{colors.label}"
    rounded: "{rounded.sheet}"
    padding: "8px"
    height: "60px"
  tab-bar:
    backgroundColor: "{colors.background}"
    textColor: "{colors.secondary}"
    typography: "{typography.tab-label}"
    height: "54px"
  book-tile:
    textColor: "{colors.label}"
    typography: "{typography.subhead}"
    rounded: "{rounded.cover-tile}"
    width: "140px"
---

# Design System: Super-Papagei

## Overview

**Creative North Star: "The Apple Shelf"**

Super-Papagei looks like a first-party Apple app that happens to do everything Audible does. Convention is the point: the user chose "Funktionen von Audible, Optik von Apple", so the system is iOS's own grammar (white system background, grey grouped lists, Large Titles, Cupertino navigation and icons, one tint) executed at Apple's level rather than reinterpreted. The cover art is the only imagery and it is always large, square, softly shadowed and never tinted; everything around it stays quiet so the covers carry the colour.

The app runs the same Apple look on both platforms. iOS gets SF Pro with Apple's per-size tracking; Android gets Roboto at zero tracking, Cupertino page transitions and components, and keeps its system Back gesture and insets. Dark Mode is a genuine second appearance built from Apple's dark system colours, not an inverted light theme.

The signature is the full-screen player in the manner of Apple Music: a sheet whose background is a pale (light) or deep (dark) tone derived from the cover's own colour, with ink-coloured controls on it and the cover itself untouched. Density is relaxed, with 20 pt page gutters and generous section spacing; the app should never feel like a file browser or admin tool.

**Key Characteristics:**
- White system background, #F2F2F7 grouped lists, black Large Titles.
- One orange tint, split into four roles by contrast job (icon/ring, text, filled button, label on fill).
- Covers large, square, untinted, with a two-layer soft shadow; radius scales with cover size.
- Full-screen player tinted from the cover colour; controls in ink, not orange.
- Cupertino components, icons and transitions on iOS and Android alike.
- German UI copy.

## Colors

A neutral Apple system palette carrying a single warm orange; the covers supply all other colour.

### Primary
- **Ember Orange** (tint, dark: dark-tint): the brand hue for things that carry no text: selected tab icon, progress line fill, download rings, cursor and selection handles, chapter markers. In light mode it fails text contrast on white, so it never sets type.
- **Burnt Orange Text** (tint-text, dark: dark-tint-text): the text-safe tint for links ("Alle", "Mehr", "Anderen Server verwenden"), the selected tab label, "noch …" remaining-time captions on started books, and every Cupertino action (CupertinoTheme primaryColor and dialog actions).
- **Button Orange** (tint-fill with on-tint, dark: dark-tint-fill with dark-on-tint): filled buttons only. Light mode is deep orange with white label; dark mode flips to bright orange with a black label, keeping the label at 4.5:1 or better.

### Neutral
- **System White / Black** (background, dark-background): page and navigation-bar ground; nav bars use it at 86–88 % opacity.
- **Grouped Grey** (grouped, dark-grouped): the background behind Settings-style inset lists (Profil, book details).
- **Card** (card, dark-card): grouped-section rows, mini player, speed options.
- **Label / Secondary / Tertiary** (label, secondary, tertiary): primary text; captions, author lines and values; chevrons and inactive tab icons.
- **Separator** (separator): 0.5 pt hairline dividers, inset 16 pt in grouped lists and 112 pt in cover rows.
- **Fill** (fill): unselected chips, secondary buttons, progress-ring tracks, image placeholders, pressed-row highlight.
- **Success / Danger** (success, danger): Apple system green and red; danger for download errors and destructive actions.

### Named Rules
**The Four Oranges Rule.** Pick the orange by job, never by eye: tint for glyphs, rings and fills without text; tint-text for any orange text or Cupertino action; tint-fill + on-tint for filled buttons. Orange type in light mode is always #C2410C, never #E8590C.

**The Covers Bring the Colour Rule.** Chrome stays neutral; the only saturated area besides the tint is cover art and the cover-derived player background. Covers are never tinted, overlaid or recoloured.

**The Neutral Stays Neutral Rule.** playerBackground() takes the cover's dominant colour to lightness .90 (light) or .16 (dark), with saturation scaled ×.9 clamped to .12–.45 (light) or ×.7 capped at .5 (dark). Covers whose saturation is below .08 keep their own near-zero saturation, so grey and black covers get a grey sheet instead of HSL's false red. Fallback base colour #8899AA.

## Typography

**Display Font:** SF Pro (iOS system font), Roboto on Android
**Body Font:** same system face
**Label/Mono Font:** none; numbers use tabular figures

**Character:** Apple's own text styles, one family, hierarchy carried by size and weight alone. On iOS, `track()` applies SF Pro's optical tracking per point size; on Android tracking is 0.

### Hierarchy
- **Large Title** (700, 34, 1.15): page titles in the collapsing navigation bar (Start, Bibliothek, Downloads, Profil).
- **Title 1** (700, 28, 1.15): book title in the book header.
- **Title 2** (700, 22, 1.2): section headers ("Neu in der Bibliothek").
- **Title 3** (600, 20, 1.2): sub-headings in sheets.
- **Headline** (600, 17, 1.25): button labels, nav title, fact values, emphasised rows.
- **Body** (400, 17, 1.3): grouped-row titles and values, text fields, Cupertino text.
- **Subhead** (400, 15, 1.3): tile titles (at weight 500), mini-player title (600), chips.
- **Footnote** (400, 13, 1.3, secondary colour): author lines, captions, grouped headers and footers.
- **Caption** (500, 12): player timecodes, fact labels; **Tab label** (500, 11).

The player sheet sets its own title at 21/700 and author at 17/400 in ink and ink at 66 % opacity.

### Named Rules
**The Tabular Time Rule.** Every duration, timecode, speed, count and size uses tabular figures, so numbers don't jitter while playing.

**The Apple Caps Rule.** Uppercase appears only where iOS uses it natively: grouped-list section headers (footnote, +0.3 tracking) and the book's fact-strip labels (caption, +0.4 tracking) above their values. Nothing else is set in caps.

## Layout

Pages are a single scrolling column under a Cupertino large-title navigation bar with bouncing physics and pull-to-refresh, ending in 150 pt of bottom clearance for the mini player and tab bar. Page content sits on a 20 pt gutter; grouped lists are inset 16 pt with 16 pt row padding, 24 pt between groups.

The Start tab leads with the current book as a large centred cover (about 60 % of the width), then title, progress, chapter/remaining time and a full-width filled "Weiterhören" button; below it, horizontal shelves of 140 pt tiles with 14 pt gaps. Section headers open with 28 pt above and 10 pt below. The library is a cover grid with 16 pt column and 22 pt row spacing, columns derived from the width. List rows pair a 56–76 pt cover with text and inset separators at 112 pt.

The mini player floats 8 pt from the edges above a 54 pt tab bar. The fact strip on the book page grows with the system text scale so labels never clip. Tap targets are at least 44 pt.

## Elevation & Depth

Flat chrome, lifted covers. Surfaces separate by tone (white on #F2F2F7, card on black) and hairlines; shadows are reserved for covers and the few objects that float over content.

### Shadow Vocabulary
- **Cover lift** (`0 1px 3px rgba(0,0,0,.10), 0 6px 16px rgba(0,0,0,.12)`): every cover except the mini-player thumbnail and the back layers of stacked series thumbnails.
- **Floating bar** (`0 3px 12px rgba(0,0,0,.08)`): the mini player.
- **App icon** (`0 4px 12px rgba(0,0,0,.12)`): the launcher icon on the login screen.

### Named Rules
**The Only Covers Float Rule.** Lists, buttons, chips and cards carry no shadow. If it isn't a cover, the mini player or the app icon, it is flat.

## Shapes

Continuous Apple rounding throughout, with the cover radius scaled to cover size: 12 pt for large covers (Start hero, book header, player), 8 pt for grid and shelf tiles, 6 pt for the mini player thumbnail and library list rows, 5 pt for small download-list and stacked series thumbnails. Grouped sections, filled buttons, text fields and speed options share 12 pt; the mini player, player sheet top and snackbar use 14 pt; chips and player pills are full 36 pt capsules (18 pt radius). Progress lines are fully rounded. Covers are always square.

## Components

### Buttons
Calm and solid, Apple's filled style.
- **Shape:** gently rounded rectangle (12 pt), 50 pt high.
- **Filled:** tint-fill with on-tint label, headline weight, optional 20 pt leading Cupertino icon; disabled at 50 % opacity; busy state swaps the label for a spinner.
- **Secondary filled:** fill background with tint-text label.
- **Text actions:** tint-text at 17 pt, often with a trailing chevron; 44 pt minimum target. No splash; pressed highlight is fill at 60 %.

### Chips
- **Style:** 36 pt capsules on fill, label in subhead/500.
- **State:** selected inverts to label background with background-coloured text. On the player, pills are transparent with ink and gain ink at 14 % when active.

### Cards / Containers
- **Corner Style:** 12 pt grouped sections.
- **Background:** card on grouped.
- **Shadow Strategy:** none (see Elevation).
- **Border:** 0.5 pt separators between rows, inset 16 pt.
- **Internal Padding:** rows 16 × 11 pt, 48 pt minimum, optional leading icon, trailing value in secondary and chevron in tertiary.

### Inputs / Fields
- **Style:** borderless CupertinoTextField as a row inside a grouped section (card on grouped, 12 pt section radius, hairline between fields), 16 × 14 pt padding, body text, tertiary placeholder.
- **Focus:** tint cursor and selection (tint at 25 %).

### Navigation
- **Tab bar:** four tabs (Start, Bibliothek, Downloads, Profil), Cupertino outline icons at 25 pt that switch to filled when selected; selected icon in tint, label in tint-text; inactive icon tertiary, label secondary.
- **Navigation bar:** collapsing large title over translucent background, no border, back label "Zurück". Cupertino page transitions on both platforms; Android keeps system Back.
- **Dialogs:** CupertinoAlertDialog with tint-text actions and system-red destructive action.

### Cover
The system's core object. Square, clipped to its size-scaled radius, cover lift shadow, fades in over 150 ms on a placeholder of the cover's own colour. Without art it shows a title card in the cover colour (fallback #3A4A5C) with the title bottom-left in black or white by luminance.

### Book Tile and Caption
Cover (8 pt), then a 3 pt progress line if started, then title (subhead/500), author (footnote) and a status line: remaining time "noch …" in tint-text when started, total length or "Beendet" in secondary, followed by the 13 pt download glyph. The glyph is the one place download state shows: filled arrow circle (secondary) when loaded, a tint ring on fill while loading, red exclamation on failure, pause circle when paused.

### Mini Player
A 60 pt card floating 8 pt above the tab bar, 14 pt radius, floating-bar shadow, 44 pt unshadowed cover (6 pt) that hero-animates into the player, title and current chapter, play and skip-30 controls.

### Player Sheet
Full-height sheet with a 14 pt top radius and a 38 × 5 grab handle, coloured by playerBackground(). Ink is #111111 in light and white in dark, secondary text ink at 66 %. The cover (12 pt) is as large as the width allows and scales to 88 % when paused (420 ms, ease-out cubic). The scrubber, transport controls and pills are ink, not tint.

### Launcher Icon
`app/assets/icon.png` is the Super-Papagei app icon: a hand-painted-look gouache close-up of a scarlet macaw head (crimson and orange feathers, chrome-yellow face patch with dark feather strokes, ivory hooked beak, staring eye) in front of a blood-orange full moon on a midnight-blue sky. It was generated with Gemini (prompt in `app/assets/concepts/prompt-r.txt`, embedded in the PNG). Three Die-drei-???-covers from the library were used only as painting-style references for earlier rounds, never the logo or the Super-Papagei cover itself. On Android the painting is the adaptive-icon background layer (`icon_foreground.png` is empty). On the login screen it appears at 84 pt with a 19 pt radius. The icon is the one place where this saturated red/orange/blue palette appears; inside the app the orange tint stays the only accent.

## Do's and Don'ts

### Do:
- **Do** choose the orange by job: tint (#E8590C / #FF8A3D) for icons, rings and textless fills; tint-text (#C2410C / #FF9F5A) for text and Cupertino actions; tint-fill + on-tint for filled buttons.
- **Do** scale cover radius with size: 12 pt large, 8 pt tile, 6 pt row and mini player, 5 pt small thumbnails.
- **Do** keep covers square, untinted and shadowed with the two-layer cover lift.
- **Do** derive the player background from the cover colour with playerBackground(), keeping covers under .08 saturation neutral.
- **Do** use Cupertino components, icons, dialogs and page transitions on both iOS and Android, with system Back and insets intact on Android.
- **Do** apply `track()` to every text size and tabular figures to every number.
- **Do** give Dark Mode its own Apple dark system values rather than inverting light ones.

### Don't:
- **Don't** set text in #E8590C on a light background; it fails contrast.
- **Don't** tint, overlay or recolour cover art.
- **Don't** put shadows on lists, chips, buttons or cards.
- **Don't** introduce Material ripples, Material icons or a second accent colour.
- **Don't** set text in caps outside grouped-list headers and the fact-strip labels.
- **Don't** turn the app into a dark streaming dashboard; light mode is white with grey grouped lists.
