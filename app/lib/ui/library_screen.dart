import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/downloads.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'parrot.dart';

enum _Segment { books, series, authors }

enum BookFilter { all, started, unstarted, downloaded, finished }

const _filterLabels = {
  BookFilter.all: 'Alle',
  BookFilter.started: 'Begonnen',
  BookFilter.unstarted: 'Neu',
  BookFilter.downloaded: 'Geladen',
  BookFilter.finished: 'Beendet',
};

const _sortLabels = {
  SortMode.recent: 'Zuletzt gehört',
  SortMode.title: 'Titel',
  SortMode.author: 'Autor',
  SortMode.added: 'Neu hinzugefügt',
  SortMode.length: 'Länge',
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Segment _segment = _Segment.books;
  BookFilter _filter = BookFilter.all;
  SortMode _sort = SortMode.title;
  String _query = '';

  Future<void> _chooseSort() async {
    final r = await showCupertinoModalPopup<SortMode>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sortieren nach'),
        actions: [
          for (final m in SortMode.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_sortLabels[m]!),
                if (m == _sort) ...[const SizedBox(width: 8), const Icon(CupertinoIcons.checkmark_alt, size: 20)],
              ]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
      ),
    );
    if (r != null) setState(() => _sort = r);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dl = context.watch<Downloads>();
    final c = context.c;
    final found = lib.search(_query);

    List<Book> books = found.where((b) {
      switch (_filter) {
        case BookFilter.all:
          return true;
        case BookFilter.started:
          return lib.isStarted(b.id);
        case BookFilter.unstarted:
          return !lib.isStarted(b.id) && !lib.isFinished(b.id);
        case BookFilter.downloaded:
          return dl.isComplete(b);
        case BookFilter.finished:
          return lib.isFinished(b.id);
      }
    }).toList();
    books = lib.sorted(books, _sort);

    return LargeTitlePage(
      title: 'Bibliothek',
      onRefresh: lib.refresh,
      trailing: _segment == _Segment.books
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: _chooseSort,
              child: Icon(CupertinoIcons.arrow_up_arrow_down_circle, color: c.tint, size: 26, semanticLabel: 'Sortieren'),
            )
          : null,
      slivers: [
        if (context.watch<Session>().authExpired) const SliverToBoxAdapter(child: AuthNote()),
        if (lib.offline && !context.watch<Session>().authExpired) const SliverToBoxAdapter(child: OfflineNote()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CupertinoSearchTextField(
              placeholder: 'Titel, Autor, Sprecher, Serie',
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: c.label),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<_Segment>(
                groupValue: _segment,
                onValueChanged: (v) => setState(() => _segment = v ?? _Segment.books),
                children: const {
                  _Segment.books: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Bücher')),
                  _Segment.series: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Serien')),
                  _Segment.authors: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Autoren')),
                },
              ),
            ),
          ),
        ),
        if (_segment == _Segment.books) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final f in BookFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: _filterLabels[f]!,
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Text(
                '${books.length} ${books.length == 1 ? 'Buch' : 'Bücher'} · ${_sortLabels[_sort]}',
                style: context.t.bodySmall,
              ),
            ),
          ),
          if (books.isEmpty)
            SliverToBoxAdapter(child: _NoResults(query: _query, filter: _filter))
          else
            BookGrid(books),
        ],
        if (_segment == _Segment.series) _SeriesList(query: _query),
        if (_segment == _Segment.authors) _AuthorList(query: _query),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: selected ? c.label : c.fill,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: track(15), color: selected ? c.background : c.label)),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final BookFilter filter;
  const _NoResults({required this.query, required this.filter});
  @override
  Widget build(BuildContext context) {
    final text = query.isNotEmpty
        ? 'Nichts gefunden für „$query“.'
        : switch (filter) {
            BookFilter.started => 'Du hast gerade kein Buch angefangen.',
            BookFilter.downloaded => 'Noch nichts auf diesem Gerät. Bücher laden automatisch, sobald du sie abspielst.',
            BookFilter.finished => 'Noch kein Buch beendet.',
            _ => 'Keine Bücher.',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      child: Column(children: [
        const ParrotLine(size: 64),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: context.t.bodyLarge!.copyWith(color: context.c.secondary)),
      ]),
    );
  }
}

/// Responsive cover grid that reflows in whole cells.
class BookGrid extends StatelessWidget {
  final List<Book> books;
  const BookGrid(this.books, {super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = (w / 180).floor().clamp(2, 8);
    final cell = (w - 40 - (cols - 1) * 16) / cols;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 22,
          // cover + progress line (9) + caption (3 lines of small text)
          mainAxisExtent: cell + 12 + 72 * MediaQuery.textScalerOf(context).scale(1),
        ),
        delegate: SliverChildBuilderDelegate((_, i) => BookTile(books[i]), childCount: books.length),
      ),
    );
  }
}

class _SeriesList extends StatelessWidget {
  final String query;
  const _SeriesList({required this.query});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final q = query.toLowerCase();
    final entries = lib.series.entries
        .where((e) => q.isEmpty || e.key.toLowerCase().contains(q) || e.value.any((b) => b.author.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return SliverList.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => Padding(padding: const EdgeInsets.only(left: 112), child: Divider(color: context.c.separator)),
      itemBuilder: (context, i) {
        final e = entries[i];
        final done = e.value.where((b) => lib.isFinished(b.id)).length;
        return _StackRow(
          books: e.value,
          title: e.key,
          subtitle: '${e.value.first.author} · ${e.value.length} ${e.value.length == 1 ? 'Band' : 'Bände'}'
              '${done > 0 ? ' · $done gehört' : ''}',
          onTap: () => Navigator.of(context).push(CupertinoPageRoute(
              builder: (_) => BookListScreen(title: e.key, books: e.value, seriesOrder: true))),
        );
      },
    );
  }
}

class _AuthorList extends StatelessWidget {
  final String query;
  const _AuthorList({required this.query});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final q = query.toLowerCase();
    final entries = lib.authors.entries.where((e) => q.isEmpty || e.key.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return SliverList.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => Padding(padding: const EdgeInsets.only(left: 112), child: Divider(color: context.c.separator)),
      itemBuilder: (context, i) {
        final e = entries[i];
        return _StackRow(
          books: e.value,
          title: e.key,
          subtitle: '${e.value.length} ${e.value.length == 1 ? 'Buch' : 'Bücher'}',
          onTap: () => Navigator.of(context).push(CupertinoPageRoute(
              builder: (_) => BookListScreen(title: e.key, books: e.value, seriesOrder: true))),
        );
      },
    );
  }
}

class _StackRow extends StatelessWidget {
  final List<Book> books;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _StackRow({required this.books, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final shown = books.take(3).toList().reversed.toList();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 80,
            height: 64,
            child: Stack(children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: (shown.length - 1 - i) * 8.0,
                  top: (shown.length - 1 - i) * 0.0,
                  child: Cover(shown[i], size: 64 - (shown.length - 1 - i) * 6.0, radius: 5, shadow: i == shown.length - 1),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.t.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
            ]),
          ),
          Icon(CupertinoIcons.chevron_right, size: 16, color: context.c.tertiary),
        ]),
      ),
    );
  }
}

/// A titled list of books, e.g. a series, an author, or "Neu in der Bibliothek".
class BookListScreen extends StatelessWidget {
  final String title;
  final List<Book>? books;
  final SortMode? sort;
  final bool seriesOrder;
  const BookListScreen({super.key, required this.title, this.books, this.sort, this.seriesOrder = false});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    var list = books != null ? books!.map((b) => lib.byId[b.id] ?? b).toList() : lib.books;
    if (sort != null) list = lib.sorted(list, sort!);
    final total = list.fold<double>(0, (a, b) => a + b.duration);
    return LargeTitlePage(
      title: title,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text('${list.length} ${list.length == 1 ? 'Buch' : 'Bücher'} · ${fmtDuration(total)}',
                style: context.t.bodySmall),
          ),
        ),
        if (seriesOrder)
          SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => Padding(padding: const EdgeInsets.only(left: 112), child: Divider(color: context.c.separator)),
            itemBuilder: (_, i) => BookRow(list[i], showSeriesPart: true),
          )
        else
          BookGrid(list),
      ],
    );
  }
}

/// List row with cover, used in series and author lists and in Downloads.
class BookRow extends StatelessWidget {
  final Book book;
  final bool showSeriesPart;
  final Widget? trailing;
  final VoidCallback? onTap;
  const BookRow(this.book, {super.key, this.showSeriesPart = false, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final c = context.c;
    final part = book.seriesPart ?? RegExp(r'\s(\d+)$').firstMatch(book.series ?? '')?.group(1);
    return InkWell(
      onTap: onTap ?? () => openBook(context, book),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          OfflineDim(lib.offline && context.read<PlayerController>().unavailable(book),
              child: Cover(book, size: 76, radius: 6)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showSeriesPart && part != null)
                Text('Band $part', style: context.t.labelMedium!.copyWith(color: c.tintText)),
              Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.t.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
              const SizedBox(height: 6),
              Row(children: [
                if (lib.isStarted(book.id)) ...[
                  SizedBox(width: 60, child: ProgressLine(lib.fractionOf(book), height: 3)),
                  const SizedBox(width: 8),
                ],
                Text(
                  lib.isFinished(book.id)
                      ? 'Beendet'
                      : lib.isStarted(book.id)
                          ? 'noch ${fmtDuration(book.duration - lib.positionOf(book.id))}'
                          : fmtDuration(book.duration),
                  style: context.t.bodySmall!.copyWith(fontFeatures: tabular),
                ),
                const SizedBox(width: 8),
                DownloadGlyph(book, size: 13),
              ]),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}
