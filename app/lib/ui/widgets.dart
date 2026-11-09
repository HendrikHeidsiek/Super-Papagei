import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/cover_store.dart';
import '../state/downloads.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'book_screen.dart';
import 'theme.dart';
import 'parrot.dart';

/// Book cover. Never tinted or overlaid; a coloured title card stands in when
/// the server has no cover or the image is not cached yet offline.
class Cover extends StatelessWidget {
  final Book book;
  final double? size;
  final double radius;
  final bool full;
  final bool shadow;
  const Cover(this.book, {super.key, this.size, this.radius = 8, this.full = false, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final store = context.watch<CoverStore>();
    final fallback = _Fallback(book);
    // Local copy first (works offline); a large cover falls back to the local small one.
    final local = book.hasCover ? store.file(book.id, full: full) : null;
    final exact = local != null && (!full || store.hasExact(book.id, full: true));
    Widget localImage() => Image.file(local!, fit: BoxFit.cover, gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback);
    Widget img;
    if (!book.hasCover) {
      img = fallback;
    } else if (exact) {
      img = localImage();
    } else {
      if (local == null) {
        // Not stored yet: fetch the small cover for next time.
        WidgetsBinding.instance.addPostFrameCallback((_) => store.fetch(book.id));
      }
      img = CachedNetworkImage(
        imageUrl: api.coverUrl(book.id, full: full),
        cacheKey: '${book.id}_${full ? 'f' : 't'}',
        httpHeaders: api.authHeaders,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => local != null ? localImage() : Container(color: book.coverColor ?? context.c.fill),
        errorWidget: (_, __, ___) => local != null ? localImage() : fallback,
      );
    }
    img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: AspectRatio(aspectRatio: 1, child: img));
    if (shadow) {
      img = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .10), blurRadius: 3, offset: const Offset(0, 1)),
            BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: img,
      );
    }
    return size == null ? img : SizedBox(width: size, height: size, child: img);
  }
}

class _Fallback extends StatelessWidget {
  final Book book;
  const _Fallback(this.book);
  @override
  Widget build(BuildContext context) {
    final bg = book.coverColor ?? const Color(0xFF3A4A5C);
    final fg = bg.computeLuminance() > .5 ? Colors.black : Colors.white;
    return Container(
      color: bg,
      padding: const EdgeInsets.all(10),
      alignment: Alignment.bottomLeft,
      child: LayoutBuilder(builder: (context, box) {
        final small = box.maxWidth < 90;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title,
                maxLines: small ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: small ? 11 : 17, height: 1.1)),
            if (!small) ...[
              const SizedBox(height: 4),
              Text(book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 12)),
            ],
          ],
        );
      }),
    );
  }
}

/// Thin progress line used under covers and in rows.
class ProgressLine extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  const ProgressLine(this.value, {super.key, this.height = 4, this.color});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: context.c.label.withValues(alpha: .12)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              heightFactor: 1,
              child: ColoredBox(color: color ?? context.c.tint),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Small status glyph: downloaded, downloading (with ring), failed.
class DownloadGlyph extends StatelessWidget {
  final Book book;
  final double size;
  const DownloadGlyph(this.book, {super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<Downloads>().stateOf(book);
    final c = context.c;
    switch (st.state) {
      case DlState.done:
        return Icon(CupertinoIcons.arrow_down_circle_fill, size: size, color: c.secondary, semanticLabel: 'Geladen');
      case DlState.downloading:
      case DlState.queued:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: st.state == DlState.queued ? null : st.progress.clamp(.03, 1),
            strokeWidth: 2,
            color: c.tint,
            backgroundColor: c.fill,
            semanticsLabel: 'Wird geladen',
          ),
        );
      case DlState.failed:
        return Icon(CupertinoIcons.exclamationmark_circle_fill, size: size, color: c.danger, semanticLabel: 'Download-Fehler');
      case DlState.paused:
        return Icon(CupertinoIcons.pause_circle, size: size, color: c.secondary, semanticLabel: 'Pausiert');
      case DlState.none:
        return const SizedBox.shrink();
    }
  }
}

/// The fixed line under every cover: author, then remaining time or status.
class BookCaption extends StatelessWidget {
  final Book book;
  const BookCaption(this.book, {super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final c = context.c;
    String status;
    if (lib.isFinished(book.id)) {
      status = 'Beendet';
    } else if (lib.isStarted(book.id)) {
      status = 'noch ${fmtDuration(book.duration - lib.positionOf(book.id))}';
    } else {
      status = fmtDuration(book.duration);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
        Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
        const SizedBox(height: 2),
        Row(children: [
          Flexible(
            child: Text(status,
                maxLines: 1,
                style: context.t.bodySmall!.copyWith(
                    color: lib.isStarted(book.id) ? c.tintText : c.secondary, fontFeatures: tabular)),
          ),
          const SizedBox(width: 6),
          DownloadGlyph(book, size: 13),
        ]),
      ],
    );
  }
}

/// Cover with caption, used in grids and horizontal shelves.
class BookTile extends StatelessWidget {
  final Book book;
  final double? width;
  const BookTile(this.book, {super.key, this.width});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final started = lib.isStarted(book.id);
    final off = lib.offline && context.read<PlayerController>().unavailable(book);
    return Semantics(
      button: true,
      label: '${book.title} von ${book.author}${off ? ', offline nicht verfügbar' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openBook(context, book),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              OfflineDim(off, child: Cover(book, radius: 8)),
              const SizedBox(height: 8),
              if (started) ...[ProgressLine(lib.fractionOf(book), height: 3), const SizedBox(height: 6)],
              BookCaption(book),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades a cover whose book cannot be played right now (offline, not on the device).
class OfflineDim extends StatelessWidget {
  final bool dim;
  final Widget child;
  const OfflineDim(this.dim, {super.key, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: dim ? .35 : 1,
        duration: const Duration(milliseconds: 250),
        child: child,
      );
}

void openBook(BuildContext context, Book b) {
  Navigator.of(context).push(CupertinoPageRoute(builder: (_) => BookScreen(bookId: b.id)));
}

/// Section title with optional trailing "Alle" link, Apple Books style.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  final String moreLabel;
  const SectionHeader(this.title, {super.key, this.onMore, this.moreLabel = 'Alle'});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 12, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.t.headlineSmall)),
          if (onMore != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
              onPressed: onMore,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(moreLabel, style: TextStyle(color: context.c.tintText, fontSize: 17, letterSpacing: track(17))),
                Icon(CupertinoIcons.chevron_right, size: 16, color: context.c.tintText),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Horizontal shelf of covers.
class Shelf extends StatelessWidget {
  final List<Book> books;
  final double itemWidth;
  const Shelf(this.books, {super.key, this.itemWidth = 140});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemWidth + 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => BookTile(books[i], width: itemWidth),
      ),
    );
  }
}

/// A grouped, inset list section (Settings style).
class Grouped extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  const Grouped({super.key, this.header, this.footer, required this.children});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) rows.add(Padding(padding: const EdgeInsets.only(left: 16), child: Divider(color: c.separator)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(header!.toUpperCase(), style: context.t.bodySmall!.copyWith(letterSpacing: .3)),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(color: c.card, child: Column(children: rows)),
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text(footer!, style: context.t.bodySmall)),
      ]),
    );
  }
}

class Row2 extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool chevron;
  const Row2(
      {super.key, this.leading, required this.title, this.value, this.trailing, this.onTap, this.titleColor, this.chevron = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(child: Text(title, style: context.t.bodyLarge!.copyWith(color: titleColor))),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!, style: context.t.bodyLarge!.copyWith(color: c.secondary, fontFeatures: tabular)),
              ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (chevron) ...[const SizedBox(width: 6), Icon(CupertinoIcons.chevron_right, size: 16, color: c.tertiary)],
          ]),
        ),
      ),
    );
  }
}

/// Large title page with Apple-style collapsing navigation bar.
class LargeTitlePage extends StatelessWidget {
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final Color? background;
  const LargeTitlePage(
      {super.key, required this.title, required this.slivers, this.trailing, this.onRefresh, this.background});
  @override
  Widget build(BuildContext context) {
    final bg = background ?? context.c.background;
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title),
            trailing: trailing,
            backgroundColor: bg.withValues(alpha: .88),
            border: null,
            previousPageTitle: 'Zurück',
          ),
          if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh, builder: parrotRefreshIndicator),
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ),
    );
  }
}

/// Plain filled button in the tint colour, Apple style.
class FilledPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool busy;
  const FilledPill(this.label, {super.key, this.icon, this.onPressed, this.secondary = false, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = secondary ? c.fill : c.tintFill;
    final fg = secondary ? c.tintText : c.onTint;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: onPressed == null ? bg.withValues(alpha: .5) : bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onPressed,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: track(17))),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

Future<bool> confirm(BuildContext context, String title, String message, String action, {bool destructive = true}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        CupertinoDialogAction(
            isDestructiveAction: destructive, onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}
