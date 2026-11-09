import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/downloads.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'library_screen.dart';
import 'player_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class BookScreen extends StatefulWidget {
  final String bookId;
  const BookScreen({super.key, required this.bookId});
  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  bool _descOpen = false;
  bool _allChapters = false;

  /// Same light cover tone as the player, so the two screens feel like one place.
  Color _headerColor(BuildContext context, Book b) => playerBackground(context, b);

  Future<void> _menu(Book b) async {
    final lib = context.read<Library>();
    final dl = context.read<Downloads>();
    final finished = lib.isFinished(b.id);
    final hasFiles = dl.stateOf(b).state != DlState.none;
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(b.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'finished'),
            child: Text(finished ? 'Als ungehört markieren' : 'Als beendet markieren'),
          ),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'history'), child: const Text('Positionsverlauf')),
          if (lib.isStarted(b.id))
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Fortschritt zurücksetzen')),
          if (hasFiles)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Vom Gerät entfernen'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'finished':
        await lib.markFinished(b.id, !finished);
      case 'reset':
        if (await confirm(context, 'Fortschritt zurücksetzen?', 'Das Buch beginnt danach wieder am Anfang.', 'Zurücksetzen')) {
          await lib.resetProgress(b.id);
        }
      case 'history':
        if (mounted) await showHistory(context, b);
      case 'delete':
        if (!mounted) return;
        if (await confirm(context, 'Vom Gerät entfernen?',
            '${fmtBytes(b.totalSize)} werden frei. Dein Fortschritt bleibt erhalten.', 'Entfernen')) {
          await dl.remove(b);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.watch<PlayerController>();
    final dl = context.watch<Downloads>();
    final b = lib.byId[widget.bookId];
    final c = context.c;
    if (b == null) {
      return Scaffold(
        appBar: const CupertinoNavigationBar(previousPageTitle: 'Zurück'),
        body: Center(child: Text('Dieses Buch gibt es nicht mehr.', style: context.t.bodyLarge)),
      );
    }
    final isCurrent = player.book?.id == b.id;
    final pos = isCurrent ? player.position : lib.positionOf(b.id);
    final started = lib.isStarted(b.id) || (isCurrent && pos > 5);
    final finished = lib.isFinished(b.id);
    final dlState = dl.stateOf(b);
    final header = _headerColor(context, b);
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = (width * 0.58).clamp(180.0, 320.0);
    final playing = isCurrent && player.playing;
    final more = (lib.authors[b.author] ?? []).where((x) => x.id != b.id).toList();
    final chapters = _allChapters ? b.chapters : b.chapters.take(6).toList();
    final curChapter = (started || isCurrent) ? b.chapterIndexAt(pos) : -1;

    final unavailable = !playing && player.unavailable(b);
    String playLabel;
    if (playing) {
      playLabel = 'Pause';
    } else if (finished) {
      playLabel = 'Nochmal hören';
    } else if (started) {
      playLabel = 'Weiterhören';
    } else {
      playLabel = 'Abspielen';
    }

    return Scaffold(
      backgroundColor: c.background,
      extendBodyBehindAppBar: true,
      appBar: CupertinoNavigationBar(
        previousPageTitle: 'Zurück',
        backgroundColor: header.withValues(alpha: .9),
        border: null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () => _menu(b),
          child: Icon(CupertinoIcons.ellipsis_circle, size: 26, color: c.tint, semanticLabel: 'Mehr'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
            color: header,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 60, 24, 24),
            child: Column(children: [
              Cover(b, size: coverSize, radius: 12, full: true),
              const SizedBox(height: 22),
              Text(b.title, textAlign: TextAlign.center, style: context.t.headlineSmall),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => Navigator.of(context).push(CupertinoPageRoute(
                    builder: (_) => BookListScreen(title: b.author, books: lib.authors[b.author], seriesOrder: true))),
                child: Text(b.author, textAlign: TextAlign.center, style: context.t.bodyLarge!.copyWith(color: c.tintText)),
              ),
              if (b.narrator != null) ...[
                const SizedBox(height: 2),
                Text('Gelesen von ${b.narrator}',
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall!.copyWith(color: c.label.withValues(alpha: .7))),
              ],
              if (b.seriesName != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute(
                      builder: (_) => BookListScreen(
                          title: b.seriesName!, books: lib.series[b.seriesName!], seriesOrder: true))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: c.background.withValues(alpha: .6), borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(b.seriesLabel!, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall!.copyWith(color: c.label, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 4),
                      Icon(CupertinoIcons.chevron_right, size: 12, color: c.secondary),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: unavailable
                      ? FilledPill(
                          'Offline nicht verfügbar',
                          icon: CupertinoIcons.wifi_slash,
                          secondary: true,
                          onPressed: () => player.playBook(b), // explains and marks it for download
                        )
                      : FilledPill(
                          playLabel,
                          icon: playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                          busy: isCurrent && player.loading,
                          onPressed: () async {
                            if (playing) {
                              await player.pause();
                            } else {
                              await player.playBook(b);
                              // Only open the player when playback really started.
                              if (context.mounted && player.book?.id == b.id && !player.unavailable(b)) {
                                openPlayer(context);
                              }
                            }
                          },
                        ),
                ),
                const SizedBox(width: 10),
                _DownloadButton(book: b, state: dlState),
              ]),
              if (started && !finished) ...[
                const SizedBox(height: 14),
                ProgressLine(b.duration > 0 ? pos / b.duration : 0),
                const SizedBox(height: 6),
                Row(children: [
                  Text('${(pos / b.duration * 100).clamp(0, 100).round()} % gehört',
                      style: context.t.bodySmall!.copyWith(color: c.label.withValues(alpha: .7), fontFeatures: tabular)),
                  const Spacer(),
                  Text('noch ${fmtDuration(b.duration - pos)}',
                      style: context.t.bodySmall!.copyWith(color: c.label.withValues(alpha: .7), fontFeatures: tabular)),
                ]),
              ],
              if (unavailable) ...[
                const SizedBox(height: 10),
                Text(
                    context.watch<Downloads>().isWanted(b.id)
                        ? 'Noch nicht auf diesem Gerät. Es lädt automatisch, sobald du wieder online bist.'
                        : 'Noch nicht auf diesem Gerät. Tippe auf Laden, dann kommt es, sobald du wieder online bist.',
                    textAlign: TextAlign.center,
                    style: context.t.bodySmall!.copyWith(color: c.label.withValues(alpha: .7))),
              ] else if (dlState.state == DlState.failed) ...[
                const SizedBox(height: 10),
                Text(dlState.error ?? 'Download unterbrochen. Er wird automatisch erneut versucht.',
                    textAlign: TextAlign.center, style: context.t.bodySmall!.copyWith(color: c.danger)),
              ],
            ]),
          ),
          _Facts(book: b),
          if (b.description != null && b.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: GestureDetector(
                onTap: () => setState(() => _descOpen = !_descOpen),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(b.description!,
                        maxLines: _descOpen ? null : 5,
                        overflow: _descOpen ? null : TextOverflow.fade,
                        style: context.t.bodyLarge!.copyWith(height: 1.4)),
                  ),
                  const SizedBox(height: 4),
                  Text(_descOpen ? 'Weniger' : 'Mehr', style: TextStyle(color: c.tintText, fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: track(15))),
                ]),
              ),
            ),
          SectionHeader('Kapitel', onMore: null),
          for (var i = 0; i < chapters.length; i++)
            _ChapterRow(
              book: b,
              index: i,
              current: i == curChapter,
              onTap: () async {
                await player.playBook(b, at: b.chapters[i].start);
              },
            ),
          if (b.chapters.length > 6)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CupertinoButton(
                onPressed: () => setState(() => _allChapters = !_allChapters),
                child: Text(_allChapters ? 'Weniger anzeigen' : 'Alle ${b.chapters.length} Kapitel anzeigen',
                    style: TextStyle(color: c.tintText, fontSize: 17, letterSpacing: track(17))),
              ),
            ),
          if (more.isNotEmpty) ...[
            SectionHeader('Mehr von ${b.author}'),
            Shelf(more.take(15).toList(), itemWidth: 120),
          ],
          const SizedBox(height: 160),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final Book book;
  final BookDownload state;
  const _DownloadButton({required this.book, required this.state});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dl = context.read<Downloads>();
    Widget icon;
    String label;
    VoidCallback onTap;
    switch (state.state) {
      case DlState.done:
        icon = Icon(CupertinoIcons.checkmark_alt, color: c.success, size: 24);
        label = 'Auf dem Gerät';
        onTap = () => toast(context, 'Liegt auf diesem Gerät (${fmtBytes(book.totalSize)}). Entfernen über das Menü oben rechts.');
      case DlState.downloading:
      case DlState.queued:
        icon = SizedBox(
          width: 24,
          height: 24,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: state.state == DlState.queued ? null : state.progress.clamp(.03, 1),
              strokeWidth: 2.4,
              color: c.tint,
              backgroundColor: c.separator,
            ),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(1.5))),
          ]),
        );
        label = 'Download pausieren, ${(state.progress * 100).round()} Prozent';
        onTap = () => dl.pause(book);
      case DlState.failed:
        icon = Icon(CupertinoIcons.arrow_clockwise, color: c.danger, size: 22);
        label = 'Download erneut versuchen';
        onTap = () => dl.ensure(book);
      case DlState.paused:
        icon = SizedBox(
          width: 24,
          height: 24,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: state.progress.clamp(.03, 1),
              strokeWidth: 2.4,
              color: c.tint,
              backgroundColor: c.separator,
            ),
            Icon(CupertinoIcons.play_fill, size: 10, color: c.tint),
          ]),
        );
        label = 'Download fortsetzen, ${(state.progress * 100).round()} Prozent';
        onTap = () => dl.ensure(book);
      case DlState.none:
        icon = Icon(CupertinoIcons.arrow_down, color: c.tintText, size: 22);
        label = 'Auf das Gerät laden, ${fmtBytes(book.totalSize)}';
        onTap = () => dl.ensure(book);
    }
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.separator, width: .5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 50, height: 50, child: Center(child: icon)),
        ),
      ),
    );
  }
}

/// Apple Books style fact strip.
class _Facts extends StatelessWidget {
  final Book book;
  const _Facts({required this.book});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final facts = <(String, String)>[
      ('Länge', fmtDuration(book.duration)),
      ('Kapitel', '${book.chapters.length}'),
      if (book.year != null) ('Jahr', book.year!),
      if (book.language != null) ('Sprache', _lang(book.language!)),
      ('Größe', fmtBytes(book.totalSize)),
    ];
    // Grows with the system font size so labels never clip.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 28 + 48 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        itemCount: facts.length,
        separatorBuilder: (_, __) => VerticalDivider(color: c.separator, width: 32),
        itemBuilder: (_, i) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(facts[i].$1.toUpperCase(), style: context.t.labelSmall!.copyWith(letterSpacing: .4)),
            const SizedBox(height: 3),
            Text(facts[i].$2, style: context.t.titleMedium!.copyWith(fontFeatures: tabular)),
          ],
        ),
      ),
    );
  }

  static String _lang(String l) => switch (l.toLowerCase()) {
        'english' || 'en' || 'englisch' => 'Englisch',
        'german' || 'de' || 'deutsch' => 'Deutsch',
        _ => l,
      };
}

class _ChapterRow extends StatelessWidget {
  final Book book;
  final int index;
  final bool current;
  final VoidCallback onTap;
  const _ChapterRow({required this.book, required this.index, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ch = book.chapters[index];
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.separator, width: .5))),
        child: Row(children: [
          SizedBox(
            width: 32,
            child: current
                ? Icon(CupertinoIcons.speaker_2_fill, size: 16, color: c.tint)
                : Text('${index + 1}', style: context.t.bodyMedium!.copyWith(color: c.secondary, fontFeatures: tabular)),
          ),
          Expanded(
            child: Text(ch.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodyLarge!.copyWith(
                    color: current ? c.tintText : c.label, fontWeight: current ? FontWeight.w600 : FontWeight.w400)),
          ),
          const SizedBox(width: 12),
          Text(fmtClock(ch.length), style: context.t.bodyMedium!.copyWith(color: c.secondary, fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

/// Server-side position history: a safety net to jump back to an earlier spot.
Future<void> showHistory(BuildContext context, Book b) async {
  final api = context.read<Session>().api;
  final player = context.read<PlayerController>();
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.c.grouped,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .92,
      builder: (ctx, scroll) => FutureBuilder(
        future: api.progressHistory(b.id),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Verlauf ist nur mit Verbindung zum Server verfügbar.',
                  textAlign: TextAlign.center, style: ctx.t.bodyLarge),
            );
          }
          final items = snap.data!;
          return ListView(controller: scroll, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Positionsverlauf', style: ctx.t.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('Hier landet jede größere Positionsänderung. Tippe auf einen Eintrag, um dorthin zu springen.',
                  style: ctx.t.bodySmall),
            ),
            if (items.isEmpty)
              Padding(padding: const EdgeInsets.all(20), child: Text('Noch kein Verlauf.', style: ctx.t.bodyLarge)),
            Grouped(children: [
              for (final it in items)
                Row2(
                  title: '${fmtClock((it['position'] as num).toDouble())} · '
                      '${b.chapters.isEmpty ? '' : b.chapters[b.chapterIndexAt((it['position'] as num).toDouble())].title}',
                  value: fmtRelative(it['at'] as int),
                  onTap: () {
                    Navigator.pop(ctx);
                    player.playBook(b, at: (it['position'] as num).toDouble());
                  },
                ),
            ]),
          ]);
        },
      ),
    ),
  );
}
