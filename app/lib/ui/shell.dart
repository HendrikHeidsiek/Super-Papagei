import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_sheet.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tab bar + mini player. Each tab keeps its own navigation stack, so the
/// tab bar and mini player stay visible while browsing (Apple Music style).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _keys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const _tabs = [
    (CupertinoIcons.house, CupertinoIcons.house_fill, 'Start'),
    (CupertinoIcons.book, CupertinoIcons.book_fill, 'Bibliothek'),
    (CupertinoIcons.arrow_down_circle, CupertinoIcons.arrow_down_circle_fill, 'Downloads'),
    (CupertinoIcons.person_crop_circle, CupertinoIcons.person_crop_circle_fill, 'Profil'),
  ];

  Widget _root(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const LibraryScreen(),
        2 => const DownloadsScreen(),
        _ => const ProfileScreen(),
      };

  void _select(int i) {
    if (i == _tab) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final player = context.watch<PlayerController>();
    player.onShakeExtended ??= () {
      final m = player.sleepLeft?.inMinutes;
      if (mounted) toast(context, m == null ? 'Sleep-Timer neu gestartet' : 'Sleep-Timer neu gestartet: ${m + 1} Minuten');
    };
    // Surface player errors once.
    if (player.lastError != null) {
      final msg = player.lastError!;
      player.lastError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => toast(context, msg));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _keys[_tab].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(children: [
          for (var i = 0; i < 4; i++)
            Offstage(
              offstage: _tab != i,
              child: TickerMode(
                enabled: _tab == i,
                child: Navigator(
                  key: _keys[i],
                  onGenerateRoute: (s) => CupertinoPageRoute(builder: (_) => _root(i), settings: s),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.background.withValues(alpha: .86),
                    border: Border(top: BorderSide(color: c.separator, width: .5)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (player.book != null) const MiniPlayer(),
                      _TabBar(current: _tab, onSelect: _select, tabs: _tabs),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> tabs;
  const _TabBar({required this.current, required this.onSelect, required this.tabs});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 54,
      child: Row(children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: Semantics(
              selected: i == current,
              button: true,
              label: tabs[i].$3,
              child: InkResponse(
                onTap: () => onSelect(i),
                radius: 36,
                child: ExcludeSemantics(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(i == current ? tabs[i].$2 : tabs[i].$1, size: 25, color: i == current ? c.tint : c.tertiary),
                    const SizedBox(height: 2),
                    Text(tabs[i].$3,
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: track(11),
                            fontWeight: FontWeight.w500,
                            color: i == current ? c.tintText : c.secondary)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final b = p.book!;
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPlayer(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) openPlayer(context);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 12, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Row(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Hero(tag: 'cover-player', child: Cover(b, size: 44, radius: 6, shadow: false)),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
                    StreamBuilder(
                      stream: p.positionStream,
                      builder: (context, _) => Text(
                        p.chapter?.title ?? b.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              _RoundIcon(
                icon: p.playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                label: p.playing ? 'Pause' : 'Abspielen',
                busy: p.loading || p.waiting,
                onTap: p.toggle,
                size: 26,
              ),
              _RoundIcon(
                icon: CupertinoIcons.goforward_30,
                label: '${p.skipForward} Sekunden vor',
                onTap: p.fastForward,
                size: 24,
              ),
              const SizedBox(width: 6),
            ]),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: StreamBuilder(
                stream: p.positionStream,
                builder: (context, _) => LinearProgressIndicator(
                  value: b.duration > 0 ? (p.position / b.duration).clamp(0, 1) : 0,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: c.tint,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool busy;
  const _RoundIcon({required this.icon, required this.label, required this.onTap, this.size = 24, this.busy = false});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: size, color: context.c.label),
          ),
        ),
      ),
    );
  }
}
