import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player.dart';
import 'theme.dart';
import 'widgets.dart';

/// Choices for the two wheels.
const _pauses = [10, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 21600, 43200, 86400];
const _backs = [1, 2, 3, 4, 5, 7, 10, 15, 20, 30, 45, 60];

String fmtPause(int s) => s < 60 ? '$s s' : (s < 3600 ? '${s ~/ 60} min' : '${s ~/ 3600} h');

/// Value for the row on the Profil page.
String rewindSummary(PlayerController p) {
  if (!p.rewindOn || p.rewindSteps.isEmpty) return 'Aus';
  final n = p.rewindSteps.length;
  return n == 1 ? '1 Stufe' : '$n Stufen';
}

/// Profil → Wiedergabe → Nach Pause zurück: tiers of "pause at least X → jump back Y".
class RewindSettingsScreen extends StatelessWidget {
  const RewindSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final c = context.c;
    final steps = p.rewindSteps;
    return LargeTitlePage(
      title: 'Nach Pause zurück',
      background: c.grouped,
      slivers: [
        SliverToBoxAdapter(
          child: Grouped(
            footer: p.rewindOn
                ? 'Beim Fortsetzen hörst du die letzten Sekunden noch einmal, damit du wieder reinkommst.'
                : 'Nach einer Pause geht es genau dort weiter, wo du aufgehört hast.',
            children: [
              Row2(
                title: 'Zurückspringen nach Pause',
                trailing: CupertinoSwitch(
                  value: p.rewindOn,
                  activeTrackColor: c.tintFill,
                  onChanged: (v) => p.setRewind(on: v),
                ),
              ),
            ],
          ),
        ),
        if (p.rewindOn)
          SliverToBoxAdapter(
            child: Grouped(
              header: 'Stufen',
              footer: steps.isEmpty
                  ? 'Ohne Stufe springt Super-Papagei nie zurück.'
                  : 'Kürzere Pausen als ${fmtPause(steps.first.pause)} springen nicht zurück. '
                      'Zum Löschen nach links wischen.',
              children: [
                for (final r in steps)
                  Dismissible(
                    key: ValueKey('rw-${r.pause}'),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => p.setRewind(steps: [...steps]..remove(r)),
                    background: Container(
                      color: c.danger,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(CupertinoIcons.trash, color: Colors.white, size: 20, semanticLabel: 'Löschen'),
                    ),
                    child: Row2(
                      title: 'ab ${fmtPause(r.pause)} Pause',
                      value: '${r.back} s zurück',
                      chevron: true,
                      onTap: () => _edit(context, r),
                    ),
                  ),
                Row2(
                  leading: Icon(CupertinoIcons.add_circled_solid, color: c.tint, size: 22),
                  title: 'Stufe hinzufügen',
                  titleColor: c.tintText,
                  onTap: () => _edit(context, null),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, RewindStep? old) async {
    final p = context.read<PlayerController>();
    final steps = p.rewindSteps;
    // A new tier starts one step past the longest pause so far.
    final start = old ??
        (steps.isEmpty
            ? const RewindStep(60, 2)
            : RewindStep(
                _pauses[(_pauses.indexOf(steps.last.pause) + 1).clamp(0, _pauses.length - 1)],
                _backs[(_backs.indexOf(steps.last.back) + 2).clamp(0, _backs.length - 1)],
              ));
    final r = await showCupertinoModalPopup<_Edit>(
      context: context,
      builder: (_) => _StepSheet(start: start, existing: old != null),
    );
    if (r == null) return;
    final next = [...steps]..remove(old);
    if (!r.delete) {
      // Same pause as another tier: the new one replaces it.
      next.removeWhere((x) => x.pause == r.step.pause);
      next.add(r.step);
    }
    await p.setRewind(steps: next);
  }
}

class _Edit {
  final RewindStep step;
  final bool delete;
  const _Edit(this.step, {this.delete = false});
}

class _StepSheet extends StatefulWidget {
  final RewindStep start;
  final bool existing;
  const _StepSheet({required this.start, required this.existing});
  @override
  State<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends State<_StepSheet> {
  late int _pause = _nearest(_pauses, widget.start.pause);
  late int _back = _nearest(_backs, widget.start.back);

  static int _nearest(List<int> list, int v) {
    var best = 0;
    for (var i = 0; i < list.length; i++) {
      if ((list[i] - v).abs() < (list[best] - v).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = context.t.bodySmall!.copyWith(color: c.secondary);
    final wheel = TextStyle(color: c.label, fontSize: 21, fontFeatures: tabular);
    Widget column(String title, List<String> items, int selected, ValueChanged<int> onChanged) => Expanded(
          child: Column(children: [
            Text(title.toUpperCase(), style: label.copyWith(letterSpacing: .3)),
            SizedBox(
              height: 180,
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: selected),
                itemExtent: 38,
                useMagnifier: true,
                magnification: 1.08,
                selectionOverlay: CupertinoPickerDefaultSelectionOverlay(background: c.label.withValues(alpha: .06)),
                onSelectedItemChanged: onChanged,
                children: [for (final t in items) Center(child: Text(t, style: wheel))],
              ),
            ),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Row(children: [
                CupertinoButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
                Expanded(
                  child: Text(widget.existing ? 'Stufe ändern' : 'Neue Stufe',
                      textAlign: TextAlign.center, style: context.t.titleMedium),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context, _Edit(RewindStep(_pauses[_pause], _backs[_back]))),
                  child: const Text('Fertig', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Nach ${fmtPause(_pauses[_pause])} Pause geht es ${_backs[_back]} Sekunden zurück.',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium!.copyWith(color: c.secondary, fontFeatures: tabular),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                column('Pause ab', [for (final s in _pauses) fmtPause(s)], _pause, (i) => setState(() => _pause = i)),
                const SizedBox(width: 12),
                column('Zurück um', [for (final s in _backs) '$s s'], _back, (i) => setState(() => _back = i)),
              ]),
            ),
            if (widget.existing)
              CupertinoButton(
                onPressed: () => Navigator.pop(context, _Edit(widget.start, delete: true)),
                child: Text('Stufe löschen', style: TextStyle(color: c.danger)),
              )
            else
              const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}
