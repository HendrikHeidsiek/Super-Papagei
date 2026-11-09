import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state/downloads.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

void openPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true, // keeps the sheet below status bar and Dynamic Island
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .3),
    builder: (_) => const PlayerSheet(),
  );
}

/// Light (or, in dark mode, deep) tone of the cover colour for the player background.
Color playerBackground(BuildContext context, Book b) {
  final base = b.coverColor ?? const Color(0xFF8899AA);
  final hsl = HSLColor.fromColor(base);
  // Near-grey covers have no real hue (HSL reports red); keep them neutral.
  final neutral = hsl.saturation < .08;
  if (Theme.of(context).brightness == Brightness.dark) {
    return hsl.withLightness(.16).withSaturation(neutral ? hsl.saturation : (hsl.saturation * .7).clamp(0, .5)).toColor();
  }
  return hsl.withLightness(.90).withSaturation(neutral ? hsl.saturation : (hsl.saturation * .9).clamp(.12, .45)).toColor();
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final b = p.book;
    if (b == null) return const SizedBox.shrink();
    final bg = playerBackground(context, b);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF111111);
    final soft = ink.withValues(alpha: .66);
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final coverSize = (w - 64).clamp(200.0, mq.size.height * .42).toDouble();

    return Container(
      margin: const EdgeInsets.only(top: 10), // reads as a card, Apple Music style
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
      padding: EdgeInsets.only(top: 6, bottom: MediaQuery.paddingOf(context).bottom + 10),
      child: DefaultTextStyle(
        style: TextStyle(color: ink),
        child: IconTheme(
          data: IconThemeData(color: ink),
          child: Column(children: [
            Semantics(
              label: 'Player schließen',
              button: true,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 60,
                  height: 24,
                  alignment: Alignment.center,
                  child: Container(width: 38, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: .25), borderRadius: BorderRadius.circular(3))),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    openBook(context, b);
                  },
                  child: AnimatedScale(
                    scale: p.playing ? 1 : .88,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    child: Hero(tag: 'cover-player', child: Cover(b, size: coverSize, radius: 12, full: true)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: ink, letterSpacing: track(21))),
                      const SizedBox(height: 2),
                      Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: soft, letterSpacing: track(17))),
                    ]),
                  ),
                  _BarButton(
                    icon: CupertinoIcons.bookmark,
                    label: 'Lesezeichen setzen',
                    color: ink,
                    onTap: () => addBookmark(context, b, p.position),
                  ),
                ]),
                _Scrubber(ink: ink, soft: soft),
                const SizedBox(height: 10),
                _Transport(ink: ink),
                const SizedBox(height: 16),
                _BottomBar(ink: ink, soft: soft),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Chapter scrubber: Audible shows progress inside the current chapter.
class _Scrubber extends StatefulWidget {
  final Color ink;
  final Color soft;
  const _Scrubber({required this.ink, required this.soft});
  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final b = p.book!;
    return StreamBuilder(
      stream: p.positionStream,
      builder: (context, _) {
        final pos = p.position;
        final ci = b.chapterIndexAt(pos);
        final ch = b.chapters.isEmpty ? Chapter(b.title, 0, b.duration) : b.chapters[ci];
        final inCh = (_drag ?? (pos - ch.start)).clamp(0, ch.length).toDouble();
        final style = TextStyle(fontSize: 12, color: widget.soft, fontFeatures: tabular, fontWeight: FontWeight.w500, letterSpacing: track(12));
        return Column(children: [
          // The visible bar is thin; the touch area around it is finger sized (40 pt).
          // It takes over the 18 pt gap above, so the layout does not move.
          Semantics(
            slider: true,
            label: 'Position im Kapitel',
            value: '${fmtClock(inCh)} von ${fmtClock(ch.length)}',
            increasedValue: fmtClock((inCh + 30).clamp(0, ch.length).toDouble()),
            decreasedValue: fmtClock((inCh - 15).clamp(0, ch.length).toDouble()),
            onIncrease: p.fastForward,
            onDecrease: p.rewind,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              final len = ch.length <= 0 ? 1.0 : ch.length;
              double at(double dx) => (dx / w).clamp(0.0, 1.0) * len;
              final frac = (inCh / len).clamp(0.0, 1.0);
              final dragging = _drag != null;
              final h = dragging ? 9.0 : 5.0;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => p.seekTo(ch.start + at(d.localPosition.dx)),
                onHorizontalDragStart: (d) => setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragEnd: (_) async {
                  final v = _drag;
                  if (v != null) await p.seekTo(ch.start + v);
                  if (mounted) setState(() => _drag = null);
                },
                onHorizontalDragCancel: () => setState(() => _drag = null),
                child: SizedBox(
                  height: 40,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 18 + (9 - h) / 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: h,
                        decoration: BoxDecoration(
                          color: widget.ink.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(h / 2),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.ink.withValues(alpha: .85),
                              borderRadius: BorderRadius.circular(h / 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (dragging)
                      Positioned(
                        left: frac * w - 7,
                        top: 18 + 4.5 - 7,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: widget.ink, shape: BoxShape.circle),
                        ),
                      ),
                  ]),
                ),
              );
            }),
          ),
          Row(children: [
            SizedBox(width: 70, child: Text(fmtClock(inCh), style: style)),
            Expanded(
              child: GestureDetector(
                onTap: () => showChapters(context),
                child: Text(
                  ch.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: widget.ink, fontWeight: FontWeight.w600, letterSpacing: track(13)),
                ),
              ),
            ),
            SizedBox(width: 70, child: Text('−${fmtClock(ch.length - inCh)}', textAlign: TextAlign.right, style: style)),
          ]),
        ]);
      },
    );
  }
}

class _Transport extends StatelessWidget {
  final Color ink;
  const _Transport({required this.ink});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final backIcon = switch (p.skipBack) {
      10 => CupertinoIcons.gobackward_10,
      30 => CupertinoIcons.gobackward_30,
      _ => CupertinoIcons.gobackward_15,
    };
    final fwdIcon = switch (p.skipForward) {
      10 => CupertinoIcons.goforward_10,
      15 => CupertinoIcons.goforward_15,
      _ => CupertinoIcons.goforward_30,
    };
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _BarButton(icon: CupertinoIcons.backward_end_fill, label: 'Vorheriges Kapitel', color: ink, size: 24, onTap: p.previousChapter),
      _BarButton(icon: backIcon, label: '${p.skipBack} Sekunden zurück', color: ink, size: 34, onTap: p.rewind),
      Semantics(
        button: true,
        label: p.waiting ? 'Lädt, tippen zum Anhalten' : (p.playing ? 'Pause' : 'Abspielen'),
        child: InkResponse(
          onTap: p.toggle,
          radius: 44,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Center(
              child: p.loading && !p.waiting
                  ? CircularProgressIndicator(color: ink, strokeWidth: 2.5)
                  : p.waiting
                      // Waiting for audio: the pause icon stays tappable, a ring shows it is loading.
                      ? Stack(alignment: Alignment.center, children: [
                          SizedBox(
                              width: 76,
                              height: 76,
                              child: CircularProgressIndicator(color: ink.withValues(alpha: .55), strokeWidth: 2)),
                          Icon(CupertinoIcons.pause_fill, size: 40, color: ink),
                        ])
                      : Icon(p.playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 56, color: ink),
            ),
          ),
        ),
      ),
      _BarButton(icon: fwdIcon, label: '${p.skipForward} Sekunden vor', color: ink, size: 34, onTap: p.fastForward),
      _BarButton(icon: CupertinoIcons.forward_end_fill, label: 'Nächstes Kapitel', color: ink, size: 24, onTap: p.nextChapter),
    ]);
  }
}

class _BottomBar extends StatelessWidget {
  final Color ink;
  final Color soft;
  const _BottomBar({required this.ink, required this.soft});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final dl = context.watch<Downloads>();
    final b = p.book!;
    final st = dl.stateOf(b);
    String sleepLabel = 'Timer';
    if (p.sleepMode == SleepMode.endOfChapter) sleepLabel = 'Kapitelende';
    if (p.sleepMode == SleepMode.timer && p.sleepLeft != null) {
      final m = p.sleepLeft!.inSeconds;
      sleepLabel = '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
    }
    final pct = (st.progress * 100).round();
    String dlLabel = p.waiting && st.state != DlState.done
        ? (st.state == DlState.downloading ? 'Lädt diese Stelle … · Download $pct %' : 'Lädt diese Stelle …')
        : switch (st.state) {
      DlState.done => 'Offline verfügbar',
      DlState.downloading => 'Wird geladen · ${(st.progress * 100).round()} %',
      DlState.queued => dl.waitingForWifi ? 'Wartet auf WLAN' : 'Download wartet',
      DlState.failed => 'Download unterbrochen',
      DlState.paused => 'Download pausiert',
      DlState.none => 'Wird gestreamt',
    };
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _TextButton(label: fmtSpeed(p.speed), active: p.speed != 1, ink: ink, onTap: () => showSpeed(context), semantic: 'Tempo'),
        _TextButton(
          label: sleepLabel,
          icon: CupertinoIcons.moon_zzz,
          active: p.sleepMode != SleepMode.off,
          ink: ink,
          onTap: () => showSleep(context),
          semantic: 'Sleep-Timer',
        ),
        _BarButton(icon: CupertinoIcons.list_bullet, label: 'Kapitel und Lesezeichen', color: ink, onTap: () => showChapters(context)),
      ]),
      const SizedBox(height: 8),
      StreamBuilder(
        stream: p.positionStream,
        builder: (context, _) => Text(
          'noch ${fmtDuration((b.duration - p.position) / p.speed)} · $dlLabel',
          style: TextStyle(fontSize: 12, color: soft, fontFeatures: tabular, letterSpacing: track(12)),
        ),
      ),
    ]);
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _BarButton({required this.icon, required this.label, required this.color, required this.onTap, this.size = 22});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, size: size, color: color)),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final Color ink;
  final VoidCallback onTap;
  final String semantic;
  const _TextButton(
      {required this.label, this.icon, required this.active, required this.ink, required this.onTap, required this.semantic});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semantic: $label',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? ink.withValues(alpha: .14) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: ink), const SizedBox(width: 5)],
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink, fontFeatures: tabular, letterSpacing: track(15))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ sheets

Future<void> showSpeed(BuildContext context) async {
  const speeds = [0.75, 0.9, 1.0, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5, 1.75, 2.0, 2.5, 3.0];
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: context.c.grouped,
    builder: (ctx) {
      final p = ctx.watch<PlayerController>();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tempo', style: ctx.t.headlineSmall),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final s in speeds)
                _SelectTile(label: fmtSpeed(s), selected: (p.speed - s).abs() < .001, onTap: () => p.setSpeed(s)),
            ]),
          ]),
        ),
      );
    },
  );
}

Future<void> showSleep(BuildContext context) async {
  final p = context.read<PlayerController>();
  final r = await showCupertinoModalPopup<int>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('Sleep-Timer'),
      message: const Text('Die Wiedergabe wird am Ende sanft leiser und pausiert. Schütteln startet den Timer neu.'),
      actions: [
        for (final m in [5, 10, 15, 30, 45, 60, 90])
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, m), child: Text('$m Minuten')),
        CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Ende des Kapitels')),
        if (p.sleepMode != SleepMode.off)
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 0), child: const Text('Timer aus')),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
    ),
  );
  if (r == null) return;
  if (r == 0) {
    p.setSleep(SleepMode.off);
  } else if (r == -1) {
    p.setSleep(SleepMode.endOfChapter);
  } else {
    p.setSleep(SleepMode.timer, Duration(minutes: r));
  }
}

/// Chapters and bookmarks in one sheet, switched by a segmented control (Audible pattern).
Future<void> showChapters(BuildContext context, {bool bookmarks = false}) async {
  final p = context.read<PlayerController>();
  final b = p.book;
  if (b == null) return;
  final api = context.read<Session>().api;
  final current = p.chapterIndex;
  var tab = bookmarks ? 1 : 0;
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.c.background,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setTab) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        maxChildSize: .94,
        builder: (ctx, scroll) {
          final c = ctx.c;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: tab,
                  onValueChanged: (v) => setTab(() => tab = v ?? 0),
                  children: const {
                    0: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Kapitel')),
                    1: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Lesezeichen')),
                  },
                ),
              ),
            ),
            Expanded(
              child: tab == 0
                  ? ListView.builder(
                      controller: ScrollController(initialScrollOffset: (current - 3).clamp(0, 9999) * 56.0),
                      itemCount: b.chapters.length,
                      itemExtent: 56,
                      itemBuilder: (_, i) {
                        final ch = b.chapters[i];
                        final cur = i == current;
                        final done = i < current;
                        return InkWell(
                          onTap: () {
                            p.seekTo(ch.start);
                            if (!p.playing) p.play();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.separator, width: .5))),
                            child: Row(children: [
                              SizedBox(
                                width: 32,
                                child: cur
                                    ? Icon(CupertinoIcons.speaker_2_fill, size: 16, color: c.tint)
                                    : Text('${i + 1}',
                                        style: ctx.t.bodyMedium!.copyWith(color: c.secondary, fontFeatures: tabular)),
                              ),
                              Expanded(
                                child: Text(ch.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ctx.t.bodyLarge!.copyWith(
                                        color: cur ? c.tintText : (done ? c.secondary : c.label),
                                        fontWeight: cur ? FontWeight.w600 : FontWeight.w400)),
                              ),
                              Text(fmtClock(ch.length),
                                  style: ctx.t.bodyMedium!.copyWith(color: c.secondary, fontFeatures: tabular)),
                            ]),
                          ),
                        );
                      },
                    )
                  : _BookmarkList(
                      book: b,
                      api: api,
                      scroll: scroll,
                      onJump: (pos) {
                        Navigator.pop(ctx);
                        p.seekTo(pos);
                      },
                    ),
            ),
          ]);
        },
      ),
    ),
  );
}

class _BookmarkList extends StatefulWidget {
  final Book book;
  final Api api;
  final ScrollController scroll;
  final ValueChanged<double> onJump;
  const _BookmarkList({required this.book, required this.api, required this.scroll, required this.onJump});
  @override
  State<_BookmarkList> createState() => _BookmarkListState();
}

class _BookmarkListState extends State<_BookmarkList> {
  late final Future<List<Map<String, dynamic>>> _future = widget.api.bookmarks(widget.book.id);

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return FutureBuilder(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CupertinoActivityIndicator());
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Lesezeichen sind nur mit Verbindung zum Server verfügbar.',
                textAlign: TextAlign.center, style: ctx.t.bodyLarge),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            child: Text('Noch keine Lesezeichen. Setze eins mit dem Lesezeichen-Symbol neben dem Titel.',
                textAlign: TextAlign.center, style: ctx.t.bodyLarge!.copyWith(color: ctx.c.secondary)),
          );
        }
        return ListView(controller: widget.scroll, children: [
          for (final it in items)
            Dismissible(
              key: ValueKey(it['id']),
              direction: DismissDirection.endToStart,
              background: Container(
                color: ctx.c.danger,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(CupertinoIcons.delete, color: Colors.white),
              ),
              onDismissed: (_) => widget.api.deleteBookmark(it['id'] as int),
              child: Row2(
                title: (it['note'] as String?) ??
                    (b.chapters.isEmpty
                        ? 'Lesezeichen'
                        : b.chapters[b.chapterIndexAt((it['position'] as num).toDouble())].title),
                value: fmtClock((it['position'] as num).toDouble()),
                onTap: () => widget.onJump((it['position'] as num).toDouble()),
              ),
            ),
        ]);
      },
    );
  }
}

Future<void> addBookmark(BuildContext context, Book b, double pos) async {
  final ctrl = TextEditingController();
  final api = context.read<Session>().api;
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text('Lesezeichen bei ${fmtClock(pos)}'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(controller: ctrl, placeholder: 'Notiz (optional)', autofocus: true),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Sichern')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await api.addBookmark(b.id, pos, ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
    if (context.mounted) toast(context, 'Lesezeichen gesichert');
  } catch (_) {
    if (context.mounted) toast(context, 'Lesezeichen brauchen eine Verbindung zum Server.');
  }
}

class _SelectTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectTile({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? c.tintFill : c.card, borderRadius: BorderRadius.circular(12)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: selected ? c.onTint : c.label, fontFeatures: tabular, letterSpacing: track(17))),
        ),
      ),
    );
  }
}
