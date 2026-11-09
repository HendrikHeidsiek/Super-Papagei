import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Semantic colours modelled on Apple's system colours.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background; // systemBackground
  final Color grouped; // systemGroupedBackground
  final Color card; // secondarySystemGroupedBackground
  final Color label;
  final Color secondary;
  final Color tertiary;
  final Color separator;
  final Color fill;
  final Color tint;
  final Color tintText; // tint dark enough for text on the background
  final Color tintFill; // filled buttons
  final Color onTint; // label on tintFill, >= 4.5:1
  final Color success;
  final Color danger;

  const AppColors({
    required this.background,
    required this.grouped,
    required this.card,
    required this.label,
    required this.secondary,
    required this.tertiary,
    required this.separator,
    required this.fill,
    required this.tint,
    required this.tintText,
    required this.tintFill,
    required this.onTint,
    required this.success,
    required this.danger,
  });

  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    grouped: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondary: Color(0xFF6C6C70),
    tertiary: Color(0xFF8E8E93),
    separator: Color(0xFFD1D1D6),
    fill: Color(0xFFEDEDF0),
    tint: Color(0xFFE8590C),
    tintText: Color(0xFFC2410C),
    tintFill: Color(0xFFC2410C),
    onTint: Color(0xFFFFFFFF),
    success: Color(0xFF248A3D),
    danger: Color(0xFFD70015),
  );

  static const dark = AppColors(
    background: Color(0xFF000000),
    grouped: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    label: Color(0xFFFFFFFF),
    secondary: Color(0xFFAEAEB2),
    tertiary: Color(0xFF8E8E93),
    separator: Color(0xFF38383A),
    fill: Color(0xFF2C2C2E),
    tint: Color(0xFFFF8A3D),
    tintText: Color(0xFFFF9F5A),
    tintFill: Color(0xFFFF8A3D),
    onTint: Color(0xFF000000),
    success: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => (other is AppColors && t > .5) ? other : this;
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
}

/// SF Pro tracking per point size on iOS; Roboto keeps 0 on Android.
double track(double size) {
  if (defaultTargetPlatform != TargetPlatform.iOS) return 0;
  if (size >= 34) return 0.37;
  if (size >= 28) return 0.36;
  if (size >= 22) return -0.26;
  if (size >= 20) return -0.45;
  if (size >= 17) return -0.43;
  if (size >= 16) return -0.31;
  if (size >= 15) return -0.23;
  if (size >= 13) return -0.08;
  return 0;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.light ? AppColors.light : AppColors.dark;
  final base = ThemeData(brightness: b, useMaterial3: true);
  // Apple text styles: Large Title 34, Title 1 28, Title 2 22, Title 3 20,
  // Headline 17 semibold, Body 17, Callout 16, Subhead 15, Footnote 13, Caption 12.
  final text = base.textTheme.copyWith(
    displaySmall: TextStyle(fontSize: 34, letterSpacing: track(34), fontWeight: FontWeight.w700, color: c.label, height: 1.15),
    headlineMedium: TextStyle(fontSize: 28, letterSpacing: track(28), fontWeight: FontWeight.w700, color: c.label, height: 1.15),
    headlineSmall: TextStyle(fontSize: 22, letterSpacing: track(22), fontWeight: FontWeight.w700, color: c.label, height: 1.2),
    titleLarge: TextStyle(fontSize: 20, letterSpacing: track(20), fontWeight: FontWeight.w600, color: c.label, height: 1.2),
    titleMedium: TextStyle(fontSize: 17, letterSpacing: track(17), fontWeight: FontWeight.w600, color: c.label, height: 1.25),
    bodyLarge: TextStyle(fontSize: 17, letterSpacing: track(17), fontWeight: FontWeight.w400, color: c.label, height: 1.3),
    bodyMedium: TextStyle(fontSize: 15, letterSpacing: track(15), fontWeight: FontWeight.w400, color: c.label, height: 1.3),
    bodySmall: TextStyle(fontSize: 13, letterSpacing: track(13), fontWeight: FontWeight.w400, color: c.secondary, height: 1.3),
    labelLarge: TextStyle(fontSize: 17, letterSpacing: track(17), fontWeight: FontWeight.w600, color: c.label),
    labelMedium: TextStyle(fontSize: 13, letterSpacing: track(13), fontWeight: FontWeight.w600, color: c.secondary),
    labelSmall: TextStyle(fontSize: 12, letterSpacing: track(12), fontWeight: FontWeight.w500, color: c.secondary),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    colorScheme: ColorScheme.fromSeed(seedColor: c.tint, brightness: b).copyWith(
      primary: c.tintFill,
      onPrimary: c.onTint,
      surface: c.background,
      onSurface: c.label,
      error: c.danger,
    ),
    textTheme: text,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.fill.withValues(alpha: .6),
    dividerTheme: DividerThemeData(color: c.separator, thickness: 0.5, space: 0.5),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.tint,
      selectionColor: c.tint.withValues(alpha: .25),
      selectionHandleColor: c.tint,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.tint, linearTrackColor: c.fill),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: b == Brightness.light ? const Color(0xF21C1C1E) : const Color(0xF2F2F2F7),
      contentTextStyle: TextStyle(fontSize: 15, color: b == Brightness.light ? Colors.white : Colors.black),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: b,
      primaryColor: c.tintText, // text-safe tint for dialog actions and Cupertino buttons
      scaffoldBackgroundColor: c.background,
      barBackgroundColor: c.background.withValues(alpha: .86),
      textTheme: CupertinoTextThemeData(
        primaryColor: c.tintText, // text-safe tint for dialog actions and Cupertino buttons
        navLargeTitleTextStyle: TextStyle(
            fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: track(34), color: c.label, inherit: false),
        navTitleTextStyle: TextStyle(fontSize: 17, letterSpacing: track(17), fontWeight: FontWeight.w600, color: c.label, inherit: false),
        textStyle: TextStyle(fontSize: 17, letterSpacing: track(17), color: c.label),
        actionTextStyle: TextStyle(fontSize: 17, color: c.tintText),
      ),
    ),
  );
}

// ------------------------------------------------------------ formatting

String fmtDuration(double seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

String fmtClock(double seconds) {
  final s = seconds.isNaN || seconds < 0 ? 0 : seconds.floor();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String fmtBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).round()} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} GB';
}

String fmtSpeed(double s) {
  final t = s.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '').replaceFirst(RegExp(r'\.0$'), '');
  return '${t.replaceAll('.', ',')}×';
}

String fmtRelative(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'gerade eben';
  if (d.inMinutes < 60) return 'vor ${d.inMinutes} min';
  if (d.inHours < 24) return 'vor ${d.inHours} h';
  if (d.inDays == 1) return 'gestern';
  if (d.inDays < 7) return 'vor ${d.inDays} Tagen';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.day}.${t.month}.${t.year}';
}

const tabular = [FontFeature.tabularFigures()];
