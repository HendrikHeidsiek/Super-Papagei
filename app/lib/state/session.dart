import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../models.dart';

/// Preset server address, baked in at build time:
///   flutter build apk --dart-define=DEFAULT_SERVER=https://audio.example.org
/// Empty means the login screen asks for it.
const defaultServer = String.fromEnvironment('DEFAULT_SERVER');

/// Login state. Persisted so the app opens straight into the library, also offline.
class Session extends ChangeNotifier {
  String serverUrl = defaultServer;
  String? token;
  UserInfo? user;
  String? serverName;

  /// The server rejected our token (password changed elsewhere, account reset).
  /// The app keeps working offline and shows a hint instead of logging out.
  bool authExpired = false;

  void markAuthExpired() {
    if (authExpired) return;
    authExpired = true;
    notifyListeners();
  }

  bool get loggedIn => token != null && user != null;
  Api get api => Api(serverUrl, token);

  /// Stable key for per-user local data (progress database).
  String get userKey {
    final host = Uri.tryParse(serverUrl)?.host ?? 'server';
    return '${host}_${user?.id ?? 0}';
  }

  static String get deviceName {
    final os = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android' : Platform.operatingSystem);
    // Hostnames on phones are UUIDs or "localhost", not useful to show.
    return os;
  }

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString('server') ?? defaultServer;
    token = p.getString('token');
    serverName = p.getString('server_name');
    final u = p.getString('user');
    if (u != null) user = UserInfo.fromJson(jsonDecode(u));
    notifyListeners();
  }

  Future<void> login(String server, String username, String password) async {
    final url = Api.normalize(server);
    final probe = Api(url, null);
    final h = await probe.health();
    if (h['app'] != 'hoerwerk') throw ApiException('Unter dieser Adresse läuft kein Super-Papagei-Server');
    final (t, u) = await probe.login(username.trim(), password, deviceName);
    serverUrl = url;
    authExpired = false;
    token = t;
    user = u;
    serverName = h['name'] as String?;
    final p = await SharedPreferences.getInstance();
    await p.setString('server', url);
    await p.setString('token', t);
    await p.setString('user', jsonEncode(u.toJson()));
    if (serverName != null) await p.setString('server_name', serverName!);
    notifyListeners();
  }

  /// Refreshes the user record; logs out if the token was revoked.
  Future<void> refreshUser() async {
    if (!loggedIn) return;
    try {
      user = await api.me();
      final p = await SharedPreferences.getInstance();
      await p.setString('user', jsonEncode(user!.toJson()));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.unauthorized) markAuthExpired();
    }
  }

  Future<void> setUser(UserInfo u) async {
    user = u;
    final p = await SharedPreferences.getInstance();
    await p.setString('user', jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> logout({bool remote = true}) async {
    if (remote) {
      try {
        await api.logout();
      } catch (_) {}
    }
    token = null;
    user = null;
    authExpired = false;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    notifyListeners();
  }
}
