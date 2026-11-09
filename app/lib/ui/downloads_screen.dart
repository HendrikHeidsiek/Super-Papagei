import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/downloads.dart';
import '../state/library.dart';
import '../state/player.dart';
import 'library_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'parrot.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Future<void> _removeOne(Book b) async {
    if (await confirm(context, '„${b.title}“ vom Gerät entfernen?',
        '${fmtBytes(b.totalSize)} werden frei. Dein Fortschritt bleibt erhalten, und du kannst das Buch jederzeit neu laden.',
        'Entfernen')) {
      if (!mounted) return;
      await context.read<Downloads>().remove(b);
    }
  }

  /// Per-book actions behind the ••• button.
  Future<void> _menu(Book b) async {
    final lib = context.read<Library>();
    final finished = lib.isFinished(b.id);
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(b.title),
        message: Text('${fmtBytes(b.totalSize)} auf diesem Gerät'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'open'), child: const Text('Zum Buch')),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'finished'),
            child: Text(finished ? 'Als ungehört markieren' : 'Als beendet markieren'),
          ),
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
      case 'open':
        openBook(context, b);
      case 'finished':
        await lib.markFinished(b.id, !finished);
      case 'delete':
        await _removeOne(b);
    }
  }

  Future<void> _removeFinished(List<Book> books) async {
    final size = books.fold<int>(0, (a, b) => a + b.totalSize);
    final names = books.take(4).map((b) => '• ${b.title}').join('\n');
    final more = books.length > 4 ? '\n… und ${books.length - 4} weitere' : '';
    if (await confirm(
        context,
        books.length == 1 ? 'Beendetes Buch entfernen?' : '${books.length} beendete Bücher entfernen?',
        '$names$more\n\n${fmtBytes(size)} werden frei. Dein Fortschritt bleibt erhalten.',
        'Entfernen')) {
      if (!mounted) return;
      final dl = context.read<Downloads>();
      for (final b in books) {
        await dl.remove(b);
      }
      if (mounted) toast(context, '${fmtBytes(size)} freigegeben');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final lib = context.watch<Library>();
    final player = context.watch<PlayerController>();
    final c = context.c;
    final all = dl.downloadedOrWanted.map((b) => lib.byId[b.id] ?? b).toList();
    final active = all.where((b) {
      final s = dl.stateOf(b).state;
      return s == DlState.downloading || s == DlState.queued || s == DlState.failed || s == DlState.paused;
    }).toList();
    final done = all.where((b) => dl.stateOf(b).state == DlState.done).toList()
      ..sort((a, b) => (lib.progress[b.id]?.updatedAt ?? 0).compareTo(lib.progress[a.id]?.updatedAt ?? 0));
    // The book in the player stays, unless it is really marked finished.
    final finishedDone = done
        .where((b) => lib.isPracticallyFinished(b) && (player.book?.id != b.id || lib.isFinished(b.id)))
        .toList();

    return LargeTitlePage(
      title: 'Downloads',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fmtBytes(dl.usedBytes)} auf diesem Gerät',
                  style: context.t.titleMedium!.copyWith(fontFeatures: tabular)),
              const SizedBox(height: 4),
              Text(
                  done.isEmpty
                      ? 'Bücher laden automatisch, sobald du sie abspielst, und bleiben offline verfügbar.'
                      : 'Bücher laden automatisch, sobald du sie abspielst. Zum Entfernen auf ••• tippen oder nach links wischen.',
                  style: context.t.bodySmall),
            ]),
          ),
        ),
        if (finishedDone.isNotEmpty)
          SliverToBoxAdapter(
            child: _CleanupCard(
              count: finishedDone.length,
              bytes: finishedDone.fold<int>(0, (a, b) => a + b.totalSize),
              onTap: () => _removeFinished(finishedDone),
            ),
          ),
        if (all.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: const ParrotEmpty(
              title: 'Noch nichts geladen',
              text: 'Der Papagei wartet. Spiel ein Buch ab oder tippe auf der Buchseite auf den Pfeil.',
            ),
          ),
        if (active.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Wird geladen')),
          SliverList.list(children: [for (final b in active) _ActiveRow(book: b)]),
        ],
        if (done.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Auf dem Gerät')),
          SliverList.list(children: [
            for (final b in done)
              Dismissible(
                key: ValueKey('dl-${b.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => confirm(context, '„${b.title}“ vom Gerät entfernen?',
                    '${fmtBytes(b.totalSize)} werden frei. Dein Fortschritt bleibt erhalten.', 'Entfernen'),
                onDismissed: (_) => dl.remove(b),
                background: Container(
                  color: c.danger,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.trash, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Entfernen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                ),
                child: BookRow(b,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(fmtBytes(b.totalSize), style: context.t.bodySmall!.copyWith(fontFeatures: tabular)),
                      Semantics(
                        button: true,
                        label: 'Aktionen für ${b.title}',
                        child: InkResponse(
                          radius: 22,
                          onTap: () => _menu(b),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: SizedBox(
                              width: 36,
                              height: 44,
                              child: Icon(CupertinoIcons.ellipsis_circle, color: c.tint, size: 24),
                            ),
                          ),
                        ),
                      ),
                    ])),
              ),
          ]),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// One tap to free the space of everything you have finished listening to.
class _CleanupCard extends StatelessWidget {
  final int count;
  final int bytes;
  final VoidCallback onTap;
  const _CleanupCard({required this.count, required this.bytes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: c.fill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(children: [
              Icon(CupertinoIcons.checkmark_circle, color: c.tintText, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(count == 1 ? '1 beendetes Buch entfernen' : '$count beendete Bücher entfernen',
                      style: context.t.bodyLarge!.copyWith(color: c.label, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Gibt ${fmtBytes(bytes)} frei. Gilt auch, wenn nur noch der Abspann fehlt.',
                      style: context.t.bodySmall!.copyWith(fontFeatures: tabular)),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 16, color: c.tertiary),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActiveRow extends StatelessWidget {
  final Book book;
  const _ActiveRow({required this.book});
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final st = dl.stateOf(book);
    final c = context.c;
    final status = switch (st.state) {
      DlState.downloading => '${(st.progress * 100).round()} % von ${fmtBytes(book.totalSize)}',
      DlState.queued => dl.waitingForWifi ? 'Wartet auf WLAN · ${fmtBytes(book.totalSize)}' : 'Wartet · ${fmtBytes(book.totalSize)}',
      DlState.failed => st.error ?? 'Unterbrochen, wird erneut versucht',
      DlState.paused => 'Pausiert · ${(st.progress * 100).round()} %',
      _ => '',
    };
    return InkWell(
      onTap: () => openBook(context, book),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          Cover(book, size: 56, radius: 5),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              ProgressLine(st.progress, height: 4, color: st.state == DlState.failed ? c.danger : null),
              const SizedBox(height: 4),
              Text(status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall!.copyWith(color: st.state == DlState.failed ? c.danger : c.secondary, fontFeatures: tabular)),
            ]),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: st.state == DlState.paused || st.state == DlState.failed ? 'Fortsetzen' : 'Pausieren',
            child: InkResponse(
              radius: 24,
              onTap: () => st.state == DlState.paused || st.state == DlState.failed ? dl.ensure(book) : dl.pause(book),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  st.state == DlState.paused || st.state == DlState.failed ? CupertinoIcons.play_circle : CupertinoIcons.pause_circle,
                  color: c.tint,
                  size: 28,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
