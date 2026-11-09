import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'library_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'parrot.dart';
import '../state/updates.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final last = lib.lastPlayed;
    final more = lib.inProgress.skip(1).toList();
    final next = lib.upNextInSeries;
    return LargeTitlePage(
      title: 'Start',
      onRefresh: lib.refresh,
      slivers: [
        if (context.watch<Session>().authExpired) const SliverToBoxAdapter(child: AuthNote()),
        if (lib.offline && !context.watch<Session>().authExpired) const SliverToBoxAdapter(child: OfflineNote()),
        if (context.watch<AppUpdate>().showNote) const SliverToBoxAdapter(child: UpdateNote()),
        if (lib.books.isEmpty && lib.loading)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: CupertinoActivityIndicator(radius: 14))),
        if (lib.books.isEmpty && !lib.loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: ParrotEmpty(
              title: 'Noch keine Bücher',
              text: lib.error ?? 'Der Server hat noch keine Hörbücher gefunden. Ein Admin kann im Profil einen Scan starten.',
            ),
          ),
        if (last != null) SliverToBoxAdapter(child: _NowCard(book: last)),
        if (last == null && lib.books.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Such dir ein Buch aus. Sobald du auf Abspielen tippst, wird es auf dieses Gerät geladen.',
                  style: context.t.bodyLarge!.copyWith(color: context.c.secondary)),
            ),
          ),
        if (more.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Weiterhören')),
          SliverToBoxAdapter(child: Shelf(more)),
        ],
        if (next.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Als Nächstes in deinen Serien')),
          SliverToBoxAdapter(child: Shelf(next)),
        ],
        if (lib.books.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader('Neu in der Bibliothek',
                onMore: () => Navigator.of(context).push(CupertinoPageRoute(
                    builder: (_) => const BookListScreen(title: 'Neu in der Bibliothek', sort: SortMode.added)))),
          ),
          SliverToBoxAdapter(child: Shelf(lib.recentlyAdded)),
        ],
      ],
    );
  }
}

/// The book you were last listening to, large.
class _NowCard extends StatelessWidget {
  final Book book;
  const _NowCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.watch<PlayerController>();
    final c = context.c;
    final pos = player.book?.id == book.id ? player.position : lib.positionOf(book.id);
    final chapter = book.chapters.isEmpty ? null : book.chapters[book.chapterIndexAt(pos)];
    final isCurrent = player.book?.id == book.id;
    final playing = isCurrent && player.playing;
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = (width * 0.62).clamp(180.0, 340.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => openBook(context, book),
            child: Cover(book, size: coverSize, radius: 12, full: true),
          ),
          const SizedBox(height: 20),
          Text(book.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.t.titleLarge),
          const SizedBox(height: 2),
          Text(book.author, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: context.t.bodyLarge!.copyWith(color: c.secondary)),
          const SizedBox(height: 14),
          SizedBox(
            width: coverSize,
            child: Column(children: [
              ProgressLine(book.duration > 0 ? pos / book.duration : 0),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(chapter?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                ),
                Text('noch ${fmtDuration(book.duration - pos)}', style: context.t.bodySmall!.copyWith(fontFeatures: tabular)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: coverSize,
            child: !playing && player.unavailable(book)
                ? FilledPill('Offline nicht verfügbar',
                    icon: CupertinoIcons.wifi_slash, secondary: true, onPressed: () => player.playBook(book))
                : FilledPill(
                    playing ? 'Pause' : 'Weiterhören',
                    icon: playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                    busy: isCurrent && player.loading,
                    onPressed: () => playing ? player.pause() : player.playBook(book),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the server no longer accepts this device's login.
/// Listening and offline use carry on; only syncing waits for a new login.
class AuthNote extends StatelessWidget {
  const AuthNote({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(CupertinoIcons.person_crop_circle_badge_exclam, size: 20, color: c.tintText),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Anmeldung abgelaufen. Hören geht weiter, abgeglichen wird nach dem Neu-Anmelden.',
                style: context.t.bodySmall!.copyWith(color: c.label)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 44),
            onPressed: () => reLogin(context),
            child: Text('Anmelden', style: TextStyle(color: c.tintText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: track(15))),
          ),
        ]),
      ),
    );
  }
}

/// Saves the position, then returns to the login screen. Downloads and
/// unsynced progress stay on the device and continue after the new login.
Future<void> reLogin(BuildContext context) async {
  final ok = await confirm(context, 'Neu anmelden?',
      'Die Wiedergabe stoppt kurz. Geladene Bücher und dein Fortschritt bleiben erhalten.', 'Anmelden',
      destructive: false);
  if (!ok || !context.mounted) return;
  await context.read<PlayerController>().unload();
  if (context.mounted) await context.read<Session>().logout(remote: false);
}

/// A newer app is on the server: one tap downloads it, Android installs it.
class UpdateNote extends StatelessWidget {
  const UpdateNote({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final u = context.watch<AppUpdate>();
    final mb = u.size == null ? '' : ' · ${(u.size! / 1e6).round()} MB';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(CupertinoIcons.arrow_down_circle_fill, size: 22, color: c.tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Neue Version ${u.latestVersion ?? ''} verfügbar',
                  style: context.t.bodyMedium!.copyWith(color: c.label, fontWeight: FontWeight.w600)),
              Text('Download$mb', style: context.t.bodySmall),
            ]),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(44, 44),
            onPressed: () async {
              if (!await u.download() && context.mounted) toast(context, 'Download konnte nicht geöffnet werden.');
            },
            child: Text('Laden', style: TextStyle(color: c.tintText, fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          Semantics(
            button: true,
            label: 'Später',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 44),
              onPressed: u.dismiss,
              child: Icon(CupertinoIcons.xmark, size: 18, color: c.secondary),
            ),
          ),
        ]),
      ),
    );
  }
}

class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(CupertinoIcons.wifi_slash, size: 18, color: c.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Offline. Geladene Bücher kannst du weiter hören, blasse sind noch nicht auf dem Gerät. Dein Fortschritt wird später abgeglichen.',
                style: context.t.bodySmall!.copyWith(color: c.label)),
          ),
        ]),
      ),
    );
  }
}

