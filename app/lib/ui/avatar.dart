import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state/session.dart';
import 'avatar_crop.dart';
import 'theme.dart';
import 'widgets.dart';

/// Round user picture, or the initial on a tinted circle.
class Avatar extends StatelessWidget {
  final UserInfo user;
  final double radius;
  final bool tinted;
  const Avatar(this.user, {super.key, this.radius = 16, this.tinted = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final api = context.read<Session>().api;
    final initial = CircleAvatar(
      radius: radius,
      backgroundColor: tinted ? c.tintFill : c.fill,
      child: Text(
        user.displayName.characters.first.toUpperCase(),
        style: TextStyle(
            color: tinted ? c.onTint : c.label, fontSize: radius * .85, fontWeight: FontWeight.w600),
      ),
    );
    if (user.avatarVersion == null) return initial;
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: '${api.avatarUrl(user.id)}?v=${user.avatarVersion}',
          cacheKey: 'avatar_${user.id}_${user.avatarVersion}',
          httpHeaders: api.authHeaders,
          fit: BoxFit.cover,
          placeholder: (_, __) => initial,
          errorWidget: (_, __, ___) => initial,
        ),
      ),
    );
  }
}

/// Lets the user pick, take or remove their own profile picture.
Future<void> editAvatar(BuildContext context) async {
  final session = context.read<Session>();
  final hasAvatar = session.user?.avatarVersion != null;
  final choice = await showCupertinoModalPopup<String>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('Profilbild'),
      actions: [
        CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'gallery'), child: const Text('Foto auswählen')),
        CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'camera'), child: const Text('Foto aufnehmen')),
        if (hasAvatar)
          CupertinoActionSheetAction(
              isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Profilbild entfernen')),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'remove') {
      await session.setUser(await session.api.deleteAvatar());
      return;
    }
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      // Large enough to stay sharp when zooming in on the crop screen.
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    final picked = await file.readAsBytes();
    if (!context.mounted) return;
    final cropped = await cropAvatar(context, picked);
    if (cropped == null) return;
    await session.setUser(await session.api.uploadAvatar(cropped));
    if (context.mounted) toast(context, 'Profilbild gespeichert');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message == 'Server nicht erreichbar' ? 'Profilbilder brauchen eine Verbindung zum Server.' : e.message);
  } catch (e) {
    if (context.mounted) toast(context, 'Das Foto konnte nicht geladen werden.');
  }
}
