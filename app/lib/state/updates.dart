import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';

/// Knows whether the server offers a newer Android app than the one installed.
/// The server learns the newest version on every release (see server/release.sh).
class AppUpdate extends ChangeNotifier {
  final Session session;
  AppUpdate(this.session);

  int? _installedBuild;
  String? latestVersion;
  int? latestBuild;
  int? size;
  String? _url;
  int _dismissed = 0;
  DateTime? _lastCheck;

  /// Only Android can install an APK.
  bool get available =>
      Platform.isAndroid && latestBuild != null && _installedBuild != null && latestBuild! > _installedBuild!;

  /// The note on Start; "Später" hides it until an even newer version appears.
  bool get showNote => available && latestBuild! > _dismissed;

  Future<void> check({bool force = false}) async {
    if (!Platform.isAndroid || session.serverUrl.isEmpty) return;
    if (!force && _lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(minutes: 10)) return;
    _lastCheck = DateTime.now();
    try {
      if (_installedBuild == null) {
        final p = await PackageInfo.fromPlatform();
        _installedBuild = int.tryParse(p.buildNumber);
        _dismissed = (await SharedPreferences.getInstance()).getInt('update_dismissed') ?? 0;
      }
      final r = await http.get(Uri.parse('${session.api.baseUrl}/api/app')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final a = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['android'];
      if (a is! Map) return;
      latestVersion = a['version'] as String?;
      latestBuild = (a['build'] as num?)?.toInt();
      size = (a['size'] as num?)?.toInt();
      _url = a['url'] as String?;
      notifyListeners();
    } catch (e) {
      debugPrint('[update] check failed: $e');
    }
  }

  Future<void> dismiss() async {
    if (latestBuild == null) return;
    _dismissed = latestBuild!;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('update_dismissed', _dismissed);
  }

  /// Opens the APK in the browser; Android then offers to install it.
  Future<bool> download() async {
    final path = _url ?? '/super-papagei.apk';
    final uri = Uri.parse(path.startsWith('http') ? path : '${session.api.baseUrl}$path');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
