import 'package:flutter/material.dart';

/// Design D ("Saakshya"): the witness from space.
///
/// Paper and ink for the record, one amber for what the satellite found and
/// for the single action that matters on a screen, green only when the ground
/// is proven clean. Square corners: this is a public record, not an app toy.
class DColors {
  static const paper = Color(0xFFFAFAF7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14213D);
  static const inkRaised = Color(0xFF1C2A4A);
  static const inkLine = Color(0xFF3B4A6B);
  static const onInkMuted = Color(0xFFC9CFDD);
  static const onInkFaint = Color(0xFFB9C0D0);
  static const body = Color(0xFF3B4252);
  static const muted = Color(0xFF5A6275);
  static const rule = Color(0xFFD9DCE3);
  static const ruleSoft = Color(0xFFECEEF2);
  static const track = Color(0xFFE3E6EC);
  static const selected = Color(0xFFEEF0F8);

  /// Links, ticket codes, focus: the record's own blue.
  static const evidence = Color(0xFF3346D3);

  /// What the satellite found, and the primary action. Nothing else.
  static const signal = Color(0xFFF2A33A);

  /// A complaint filed or work under way.
  static const filed = Color(0xFFB45309);
  static const filedText = Color(0xFF8A3F06);

  static const fire = Color(0xFFB42318);
  static const clean = Color(0xFF1F7A4D);
  static const cleanTint = Color(0xFFE8F3EC);

  /// Score scale, ash to clean.
  static const ash = Color(0xFF8A857C);
  static const ochre = Color(0xFFB7A86A);
}

class DFonts {
  static const serif = 'SourceSerif4';
  static const sans = 'PublicSans';
  static const mono = 'IBMPlexMono';
  static const serifHi = 'TiroDevanagariHindi';
  static const sansHi = 'NotoSansDevanagari';

  static const sansFallback = [sansHi];
  static const serifFallback = [serifHi, sansHi];
}

/// Text styles that know the language: Hindi headings use Tiro Devanagari,
/// Hindi body text Noto Sans Devanagari, and Latin text keeps its own faces.
class DText {
  const DText(this.hindi);
  final bool hindi;

  String get _serif => hindi ? DFonts.serifHi : DFonts.serif;
  List<String> get _serifFallback => hindi ? const [DFonts.serif, DFonts.sansHi] : DFonts.serifFallback;
  String get _sans => hindi ? DFonts.sansHi : DFonts.sans;
  List<String> get _sansFallback => hindi ? const [DFonts.sans] : DFonts.sansFallback;

  TextStyle head(double size, {Color color = DColors.ink, double height = 1.12}) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: hindi ? size * 0.92 : size,
    fontWeight: hindi ? FontWeight.w400 : FontWeight.w600,
    height: hindi ? height + 0.18 : height,
    letterSpacing: hindi ? 0 : -0.2,
    color: color,
  );

  TextStyle body(double size, {Color color = DColors.ink, FontWeight weight = FontWeight.w400, double height = 1.5}) =>
      TextStyle(
        fontFamily: _sans,
        fontFamilyFallback: _sansFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
      );

  /// Codes, dates and measurements. Always Latin.
  static TextStyle mono(double size, {Color color = DColors.ink, FontWeight weight = FontWeight.w400}) => TextStyle(
    fontFamily: DFonts.mono,
    fontFamilyFallback: DFonts.sansFallback,
    fontSize: size,
    fontWeight: weight,
    height: 1.35,
    letterSpacing: 0.2,
    color: color,
  );
}

ThemeData drishtiTheme({bool hindi = false}) {
  final t = DText(hindi);
  const radius = BorderRadius.all(Radius.circular(2));
  const shape = RoundedRectangleBorder(borderRadius: radius);
  final scheme = ColorScheme.fromSeed(seedColor: DColors.ink, surface: DColors.paper).copyWith(
    primary: DColors.ink,
    onPrimary: DColors.paper,
    secondary: DColors.signal,
    onSecondary: DColors.ink,
    tertiary: DColors.clean,
    error: DColors.fire,
    surface: DColors.paper,
    onSurface: DColors.ink,
    onSurfaceVariant: DColors.muted,
    outline: DColors.rule,
    outlineVariant: DColors.ruleSoft,
    surfaceContainerHighest: DColors.track,
    surfaceContainerHigh: DColors.ruleSoft,
    surfaceContainer: DColors.surface,
    surfaceContainerLow: DColors.surface,
    surfaceContainerLowest: DColors.surface,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = base.textTheme
      .apply(
        fontFamily: hindi ? DFonts.sansHi : DFonts.sans,
        fontFamilyFallback: hindi ? const [DFonts.sans] : DFonts.sansFallback,
        bodyColor: DColors.ink,
        displayColor: DColors.ink,
      )
      .copyWith(
        headlineLarge: t.head(32),
        headlineMedium: t.head(28),
        headlineSmall: t.head(24),
        titleLarge: t.head(22),
      );
  return base.copyWith(
    scaffoldBackgroundColor: DColors.paper,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: DColors.surface,
      foregroundColor: DColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(bottom: BorderSide(color: DColors.rule)),
      titleTextStyle: t.head(20),
    ),
    cardTheme: const CardThemeData(
      color: DColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: DColors.rule),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DColors.ink,
        foregroundColor: DColors.paper,
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: t.body(15, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DColors.ink,
        minimumSize: const Size(48, 48),
        shape: shape,
        side: const BorderSide(color: DColors.ink, width: 1.5),
        textStyle: t.body(15, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DColors.evidence,
        minimumSize: const Size(48, 44),
        shape: shape,
        textStyle: t.body(15, weight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: DColors.surface,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFFC9CDD6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFFC9CDD6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: DColors.evidence, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: Color(0xFFC9CDD6)),
      ),
      backgroundColor: DColors.surface,
      selectedColor: DColors.selected,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DColors.surface,
      indicatorColor: DColors.selected,
      indicatorShape: shape,
      labelTextStyle: WidgetStatePropertyAll(t.body(12, weight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: DColors.surface,
      indicatorColor: DColors.selected,
      indicatorShape: shape,
      selectedLabelTextStyle: t.body(12, weight: FontWeight.w700),
      unselectedLabelTextStyle: t.body(12, color: DColors.muted),
    ),
    dividerTheme: const DividerThemeData(color: DColors.rule, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DColors.ink,
      contentTextStyle: t.body(14, color: DColors.paper),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: DColors.surface, shape: shape),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: DColors.paper, shape: shape),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: DColors.ink, linearTrackColor: DColors.track),
    focusColor: DColors.signal.withValues(alpha: 0.3),
  );
}
