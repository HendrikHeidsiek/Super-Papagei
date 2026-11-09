import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'appearance_picker.dart';
import 'avatar.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'parrot.dart';
import '../state/downloads.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final lib = context.watch<Library>();
    final p = context.watch<PlayerController>();
    final c = context.c;
    final u = s.user!;
    final finished = lib.books.where((b) => lib.isFinished(b.id)).length;
    final listened = lib.progress.values.fold<double>(0, (a, pr) => a + pr.position);
    return LargeTitlePage(
      title: 'Profil',
      background: c.grouped,
      slivers: [
        if (s.authExpired) const SliverToBoxAdapter(child: AuthNote()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Row(children: [
              Semantics(
                button: true,
                label: 'Profilbild ändern',
                child: GestureDetector(
                  onTap: () => editAvatar(context),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Avatar(u, radius: 32, tinted: true),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.grouped, width: 2),
                        ),
                        child: Icon(CupertinoIcons.camera_fill, size: 13, color: c.tintText),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.displayName, style: context.t.titleLarge),
                  Text(u.isAdmin ? 'Admin · ${u.username}' : u.username, style: context.t.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Grouped(header: 'Dein Hören', children: [
            Row2(title: 'Beendete Bücher', value: '$finished'),
            Row2(title: 'Angefangen', value: '${lib.inProgress.length}'),
            Row2(title: 'Gehörte Zeit', value: fmtDuration(listened)),
          ]),
        ),
        const SliverToBoxAdapter(child: AppearancePicker()),
        SliverToBoxAdapter(
          child: Grouped(header: 'Wiedergabe', children: [
            Row2(
              title: 'Zurückspringen',
              value: '${p.skipBack} s',
              chevron: true,
              onTap: () => _pickSkip(context, true),
            ),
            Row2(
              title: 'Vorspringen',
              value: '${p.skipForward} s',
              chevron: true,
              onTap: () => _pickSkip(context, false),
            ),
          ], footer: 'Nach einer Pause von mehr als 30 Sekunden springt Super-Papagei beim Fortsetzen kurz zurück, nach 5 Minuten um 10 Sekunden.'),
        ),
        SliverToBoxAdapter(
          child: Grouped(
            header: 'Downloads',
            footer: 'Abspielen geht auch unterwegs: Das Buch wird dann gestreamt und erst im WLAN aufs Gerät geladen.',
            children: [
              Row2(
                title: 'Nur über WLAN laden',
                trailing: CupertinoSwitch(
                  value: context.watch<Downloads>().wifiOnly,
                  activeTrackColor: c.tintFill,
                  onChanged: (v) => context.read<Downloads>().setWifiOnly(v),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Grouped(
            header: 'Server',
            footer: lib.lastSync == null
                ? (lib.offline ? 'Gerade offline.' : null)
                : 'Fortschritt zuletzt abgeglichen ${fmtRelative(lib.lastSync!.millisecondsSinceEpoch)}.',
            children: [
              Row2(title: s.serverName ?? 'Super-Papagei', value: Uri.tryParse(s.serverUrl)?.host),
              Row2(title: 'Bücher in der Bibliothek', value: '${lib.books.length}'),
              Row2(
                title: 'Jetzt abgleichen',
                titleColor: c.tintText,
                trailing: lib.loading ? const CupertinoActivityIndicator() : null,
                onTap: lib.refresh,
              ),
            ],
          ),
        ),
        if (u.isAdmin)
          SliverToBoxAdapter(
            child: Grouped(header: 'Verwaltung', children: [
              Row2(
                leading: Icon(CupertinoIcons.person_2, color: c.tint),
                title: 'Benutzer',
                chevron: true,
                onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const UsersScreen())),
              ),
              Row2(
                leading: Icon(CupertinoIcons.arrow_2_circlepath, color: c.tint),
                title: 'Bibliothek neu einlesen',
                chevron: true,
                onTap: () => _scan(context),
              ),
            ]),
          ),
        SliverToBoxAdapter(
          child: Grouped(children: [
            Row2(title: 'Passwort ändern', chevron: true, onTap: () => _changePassword(context)),
            Row2(
              title: 'Abmelden',
              titleColor: c.danger,
              onTap: () async {
                if (await confirm(context, 'Abmelden?', 'Geladene Bücher bleiben auf dem Gerät.', 'Abmelden')) {
                  await context.read<PlayerController>().unload();
                  if (context.mounted) await context.read<Session>().logout();
                }
              },
            ),
          ]),
        ),
        const SliverToBoxAdapter(child: AboutParrot()),
      ],
    );
  }

  Future<void> _pickSkip(BuildContext context, bool back) async {
    final p = context.read<PlayerController>();
    final options = back ? [10, 15, 30] : [10, 15, 30];
    final r = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(back ? 'Zurückspringen um' : 'Vorspringen um'),
        actions: [
          for (final o in options)
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, o), child: Text('$o Sekunden')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
      ),
    );
    if (r != null) await p.setSkips(back ? r : p.skipBack, back ? p.skipForward : r);
  }

  Future<void> _scan(BuildContext context) async {
    final api = context.read<Session>().api;
    final lib = context.read<Library>();
    try {
      await api.scan();
      if (!context.mounted) return;
      toast(context, 'Scan läuft. Neue Bücher erscheinen in ein paar Minuten.');
      Timer.periodic(const Duration(seconds: 5), (t) async {
        try {
          final st = await api.scanState();
          if (st['running'] != true) {
            t.cancel();
            await lib.refresh();
          }
        } catch (_) {
          t.cancel();
        }
      });
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final old = TextEditingController();
    final neu = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Passwort ändern'),
        content: Column(children: [
          const SizedBox(height: 12),
          CupertinoTextField(controller: old, placeholder: 'Aktuelles Passwort', obscureText: true),
          const SizedBox(height: 8),
          CupertinoTextField(controller: neu, placeholder: 'Neues Passwort (mind. 6 Zeichen)', obscureText: true),
        ]),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Ändern')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<Session>().api.changePassword(old.text, neu.text);
      if (context.mounted) toast(context, 'Passwort geändert. Andere Geräte müssen sich neu anmelden.');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.status == 422 ? 'Das neue Passwort braucht mindestens 6 Zeichen.' : e.message);
    }
  }
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<UserInfo>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await context.read<Session>().api.users();
      if (mounted) setState(() => _users = u);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final display = TextEditingController();
    final pw = TextEditingController();
    var admin = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.c.grouped,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(children: [
                  CupertinoButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                  Expanded(child: Text('Neuer Benutzer', textAlign: TextAlign.center, style: ctx.t.titleMedium)),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Anlegen', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              Grouped(children: [
                _plain(ctx, name, 'Benutzername'),
                _plain(ctx, display, 'Anzeigename (optional)'),
                _plain(ctx, pw, 'Passwort (mind. 6 Zeichen)', obscure: true),
              ]),
              Grouped(children: [
                Row2(
                  title: 'Admin',
                  trailing: CupertinoSwitch(value: admin, activeTrackColor: ctx.c.tint, onChanged: (v) => set(() => admin = v)),
                ),
              ], footer: 'Admins können Benutzer verwalten und die Bibliothek neu einlesen.'),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<Session>().api.createUser(name.text.trim(), display.text.trim(), pw.text, admin);
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.status == 422 ? 'Benutzername fehlt oder Passwort ist zu kurz.' : e.message);
    }
  }

  Widget _plain(BuildContext ctx, TextEditingController c, String ph, {bool obscure = false}) =>
      CupertinoTextField.borderless(
        controller: c,
        placeholder: ph,
        obscureText: obscure,
        autocorrect: false,
        style: TextStyle(color: ctx.c.label, fontSize: 17),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Future<void> _userMenu(UserInfo u) async {
    final me = context.read<Session>().user!;
    final r = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(u.displayName),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'pw'), child: const Text('Passwort zurücksetzen')),
          if (u.id != me.id)
            CupertinoActionSheetAction(
                isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'del'), child: const Text('Benutzer löschen')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
      ),
    );
    if (!mounted || r == null) return;
    final api = context.read<Session>().api;
    if (r == 'del') {
      if (await confirm(context, '${u.displayName} löschen?', 'Konto und Hörfortschritt werden gelöscht.', 'Löschen')) {
        await api.deleteUser(u.id);
        await _load();
      }
    } else if (r == 'pw') {
      final ctrl = TextEditingController();
      if (!mounted) return;
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('Neues Passwort für ${u.displayName}'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(controller: ctrl, placeholder: 'Mindestens 6 Zeichen', obscureText: true),
          ),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Setzen')),
          ],
        ),
      );
      if (ok == true) {
        try {
          await api.resetUserPassword(u.id, ctrl.text);
          if (mounted) toast(context, 'Passwort gesetzt. ${u.displayName} muss sich neu anmelden.');
        } on ApiException catch (e) {
          if (mounted) toast(context, e.status == 422 ? 'Mindestens 6 Zeichen.' : e.message);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LargeTitlePage(
      title: 'Benutzer',
      background: c.grouped,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: _add,
        child: Icon(CupertinoIcons.add, color: c.tint, size: 26, semanticLabel: 'Benutzer anlegen'),
      ),
      slivers: [
        if (_error != null)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: TextStyle(color: c.danger)))),
        if (_users == null && _error == null)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: CupertinoActivityIndicator())),
        if (_users != null)
          SliverToBoxAdapter(
            child: Grouped(
              footer: 'Jeder Benutzer hat eigenen Fortschritt, eigene Lesezeichen und eine eigene Weiterhören-Liste.',
              children: [
                for (final u in _users!)
                  Row2(
                    leading: Avatar(u, radius: 16),
                    title: u.displayName,
                    value: u.isAdmin ? 'Admin' : (u.lastSeen == null ? 'nie angemeldet' : fmtRelative(u.lastSeen! * 1000)),
                    chevron: true,
                    onTap: () => _userMenu(u),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
