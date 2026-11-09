import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state/downloads.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    _server = TextEditingController(text: s.serverUrl);
    _showServer = defaultServer.isEmpty || s.serverUrl != defaultServer;
    // Debug builds only: --dart-define=HW_SERVER=… HW_USER=… HW_PASS=… for automated tests.
    const tServer = String.fromEnvironment('HW_SERVER');
    const tUser = String.fromEnvironment('HW_USER');
    const tPass = String.fromEnvironment('HW_PASS');
    if (kDebugMode && tServer.isNotEmpty && tUser.isNotEmpty) {
      _server.text = tServer;
      _user.text = tUser;
      _pw.text = tPass;
      WidgetsBinding.instance.addPostFrameCallback((_) => _login());
    }
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_server.text, _user.text, _pw.text);
      if (!mounted) return;
      await context.read<Library>().open();
      if (mounted) context.read<PlayerController>().restoreLast();
      if (mounted) context.read<Downloads>().requestNotificationPermission();
    } on ApiException catch (e) {
      setState(() => _error = e.message == 'Server nicht erreichbar'
          ? 'Server nicht erreichbar. Prüfe die Adresse und deine Verbindung.'
          : e.message);
    } catch (e) {
      setState(() => _error = 'Anmeldung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ready = _user.text.trim().isNotEmpty && _pw.text.isNotEmpty && _server.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: c.grouped,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 12, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: Image.asset('assets/icon.png', semanticLabel: 'Super-Papagei'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Super-Papagei', style: context.t.displaySmall),
                      const SizedBox(height: 6),
                      Text('Deine Hörbücher vom NAS, überall dabei.',
                          textAlign: TextAlign.center, style: context.t.bodyLarge!.copyWith(color: c.secondary)),
                    ]),
                  ),
                  const SizedBox(height: 36),
                  Grouped(children: [
                    _Field(
                      controller: _user,
                      placeholder: 'Benutzername',
                      autofill: const [AutofillHints.username],
                      onChanged: (_) => setState(() {}),
                    ),
                    _Field(
                      controller: _pw,
                      placeholder: 'Passwort',
                      obscure: true,
                      autofill: const [AutofillHints.password],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: ready ? (_) => _login() : null,
                    ),
                  ]),
                  if (_showServer)
                    Grouped(
                      header: 'Server',
                      footer: 'Adresse deines Super-Papagei-Servers, z. B. https://audio.example.org',
                      children: [
                        _Field(
                          controller: _server,
                          placeholder: 'https://…',
                          keyboard: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                      child: Text(_error!, style: context.t.bodyMedium!.copyWith(color: c.danger)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledPill('Anmelden', onPressed: ready ? _login : null, busy: _busy),
                  ),
                  const SizedBox(height: 12),
                  if (!_showServer)
                    CupertinoButton(
                      onPressed: () => setState(() => _showServer = true),
                      child: Text('Anderen Server verwenden', style: TextStyle(color: c.tintText, fontSize: 15, letterSpacing: track(15))),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final bool obscure;
  final TextInputType? keyboard;
  final Iterable<String>? autofill;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  const _Field(
      {required this.controller,
      required this.placeholder,
      this.obscure = false,
      this.keyboard,
      this.autofill,
      this.onChanged,
      this.onSubmitted});
  @override
  Widget build(BuildContext context) {
    return CupertinoTextField.borderless(
      controller: controller,
      placeholder: placeholder,
      placeholderStyle: TextStyle(color: context.c.tertiary, fontSize: 17),
      style: TextStyle(color: context.c.label, fontSize: 17),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboard,
      autofillHints: autofill,
      textInputAction: onSubmitted != null ? TextInputAction.go : TextInputAction.next,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
