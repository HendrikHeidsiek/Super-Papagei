import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import 'theme.dart';

/// Three preview tiles: Automatisch / Hell / Dunkel.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    Widget tile(ThemeMode m, String label) => Expanded(
          child: _Tile(mode: m, label: label, selected: s.themeMode == m, onTap: () => s.setThemeMode(m)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text('DARSTELLUNG', style: context.t.bodySmall!.copyWith(letterSpacing: .3)),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          decoration: BoxDecoration(color: context.c.card, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            tile(ThemeMode.system, 'Automatisch'),
            const SizedBox(width: 10),
            tile(ThemeMode.light, 'Hell'),
            const SizedBox(width: 10),
            tile(ThemeMode.dark, 'Dunkel'),
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tile({required this.mode, required this.label, required this.selected, required this.onTap});

  static const _light = (Color(0xFFF2F2F7), Color(0xFFFFFFFF), Color(0xFF1C1C1E), Color(0xFF8E8E93), Color(0xFFE8590C));
  static const _dark = (Color(0xFF121214), Color(0xFF1C1C1E), Color(0xFFF2F2F7), Color(0xFF8E8E93), Color(0xFFFF8A3D));

  Widget _half((Color, Color, Color, Color, Color) p) => Container(
        color: p.$1,
        padding: const EdgeInsets.all(5),
        child: Container(
          decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: p.$5, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 4, width: 22, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 3),
                Container(height: 4, width: 14, decoration: BoxDecoration(color: p.$4, borderRadius: BorderRadius.circular(2))),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final preview = switch (mode) {
      ThemeMode.light => _half(_light),
      ThemeMode.dark => _half(_dark),
      ThemeMode.system => Row(children: [Expanded(child: _half(_light)), Expanded(child: _half(_dark))]),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: 'Darstellung $label',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 58,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? c.tint : c.separator, width: selected ? 2.5 : 1),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: preview),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Text(label,
                style: context.t.bodyMedium!.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.label : c.secondary,
                )),
          ),
        ]),
      ),
    );
  }
}
