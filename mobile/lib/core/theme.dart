import 'package:flutter/material.dart';

/// The playful-game theme, matched one-for-one to the "Sue Me — App Screens"
/// design canvas: a warm cream page, white cards with a 3px ink border and a
/// hard offset shadow (no blur), fat radii, and a dark "stage" panel that
/// carries the one loud statistic on each screen.
///
/// Every value below is a colour taken literally from an artboard. Where the
/// design names a token twice (light / dark) it lives on [CourtPalette]; where
/// it is the same in both modes it is a `static const` here.
class CourtColors {
  const CourtColors._();

  // Brand. The action colour, and the darker shade that sits under it as the
  // hard shadow so a button looks like a physical key. Unchanged in dark mode:
  // the design uses the same violet on both.
  static const violet = Color(0xFF7A3BF0);
  static const violetHover = Color(0xFF6A2CE0);
  static const violetInk = Color(0xFF4A17B0);

  // Semantic fills
  static const blue = Color(0xFF2E6BFF);
  static const blueDeep = Color(0xFF1B4ACB);
  static const blueSoft = Color(0xFF3D8CF0);
  static const onBlue = Color(0xFFFFFFFF);

  static const greenFill = Color(0xFF35D07F);
  static const greenDeep = Color(0xFF0E8A52);
  static const onGreen = Color(0xFF0B3B22);
  static const presence = Color(0xFF35D07F);

  static const red = Color(0xFFFF3B52);
  static const redDeep = Color(0xFFC70F31);
  static const redText = Color(0xFFB3122A);
  static const redInk = Color(0xFFD61F37);
  /// The red that is legible on the dark stage, where [red] is too dense.
  static const redOnStage = Color(0xFFFF6B7D);
  static const orange = Color(0xFFFF8A3D);
  static const orangeDeep = Color(0xFFC2521A);
  static const onOrange = Color(0xFF3A1500);
  static const yellow = Color(0xFFFFC93C);
  static const yellowDeep = Color(0xFFA87400);
  static const pink = Color(0xFFFF5CA8);

  // Verdicts. `notGuilty` is the text-safe green; `greenFill` is for fills.
  static const guilty = red;
  static const notGuilty = greenDeep;
  static const bothGuilty = orange;
  static const insufficient = Color(0xFF8B7C99);

  // The stage: a near-black plum panel that the design drops onto both the
  // light and the dark page. Its own text colours never change with the mode,
  // because the panel never changes with the mode.
  static const stageLight = Color(0xFF171023);
  static const stageDark = Color(0xFF0B0713);
  static const stageInk = Color(0xFFFFF7EC);
  static const stageDim = Color(0xFFBCAACD);
  static const stageChipLight = Color(0xFF2A1F3A);
  static const stageChipDark = Color(0xFF221833);

  // Light surfaces: warm paper, and ink that is both the text and the border.
  static const lightBg = Color(0xFFFFF7EC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTray = Color(0xFFFFEEDA);
  static const lightTray2 = Color(0xFFFFE0BD);
  static const lightLine = Color(0xFF171023);
  static const lineSoft = Color(0xFFEADBC8);
  // Pastel hero wash used on the welcome screen.
  static const heroPink = Color(0xFFFF7ED8);
  static const heroViolet = Color(0xFFA78BFA);
  static const heroBlue = Color(0xFF8EB8FF);

  static const lightInk = Color(0xFF171023);
  static const lightInkDim = Color(0xFF5A4A68);
  static const lightInkFaint = Color(0xFF8E7FA0);
  static const lightMistrial = Color(0xFFC9BBD6);

  // Dark variant, exactly as the canvas draws it: ink-plum surfaces over a
  // near-black page, with a **black** border. The design keeps the hard
  // shadow in dark mode too — it reads as a crisp edge rather than a glow.
  static const darkBg = Color(0xFF140E1F);
  static const darkSurface = Color(0xFF221833);
  static const darkTray = Color(0xFF2E2142);
  static const darkTray2 = Color(0xFF3A2C4F);
  static const darkLine = Color(0xFF000000);
  static const darkInk = Color(0xFFFFF7EC);
  static const darkInkDim = Color(0xFFBCAACD);
  static const darkInkFaint = Color(0xFF8E7FA0);
  static const darkGreenText = Color(0xFF35D07F);
  static const darkMistrial = Color(0xFF6E5C82);

  // Vote buttons on a card (design: Dashboard "jury duty").
  static const guiltyBgLight = Color(0xFFFFE1E5);
  static const guiltyFgLight = Color(0xFFB3122A);
  static const innocentBgLight = Color(0xFFD9F5E6);
  static const innocentFgLight = Color(0xFF0A6B3F);
  static const guiltyBgDark = Color(0xFF3A1620);
  static const guiltyFgDark = Color(0xFFFF8796);
  static const innocentBgDark = Color(0xFF123524);
  static const innocentFgDark = Color(0xFF5BE39B);

  /// The defence speech bubble.
  static const bubblePinkLight = Color(0xFFFFE0EF);
  static const bubblePinkDark = Color(0xFF3B1D35);

  // Squircle tile tints, picked per person so a face keeps its colour. These
  // are the five avatar fills the canvas uses.
  static const tints = <Color>[
    Color(0xFFFFC93C), // yellow
    Color(0xFFFF5CA8), // pink
    Color(0xFFFF8A3D), // orange
    Color(0xFF35D07F), // green
    Color(0xFF2E6BFF), // blue
  ];
  static const onTint = lightInk;
}

/// Colours that are not part of [ColorScheme] but are used in several places.
@immutable
class CourtPalette extends ThemeExtension<CourtPalette> {
  const CourtPalette({
    required this.accent,
    required this.surfaceAlt,
    required this.surfaceAlt2,
    required this.line,
    required this.inkDim,
    required this.inkFaint,
    required this.successText,
    required this.accentInk,
    required this.border,
    required this.shadowInk,
    required this.lineSoft,
    required this.stage,
    required this.stageChip,
    required this.nav,
    required this.mistrial,
    required this.bubble,
    required this.guiltyBg,
    required this.guiltyFg,
    required this.innocentBg,
    required this.innocentFg,
  });

  /// The primary action colour (violet).
  final Color accent;

  /// The tray colour.
  final Color surfaceAlt;
  final Color surfaceAlt2;
  final Color line;
  final Color inkDim;
  final Color inkFaint;

  /// The darker shade of [accent], used as the hard shadow under a primary
  /// button so it reads as a physical key.
  final Color accentInk;

  /// The 3px structural border on every raised surface.
  final Color border;

  /// The colour of the hard offset shadow.
  final Color shadowInk;

  /// A hairline for dividers *inside* a card, where [border] would shout.
  final Color lineSoft;

  /// Green that is safe to read as text on this theme's surface.
  final Color successText;

  /// The dark panel that carries the one loud number on a screen. Its own
  /// foreground colours are [CourtColors.stageInk] / [CourtColors.stageDim]
  /// in both modes — the panel is dark either way.
  final Color stage;

  /// A quiet tile *inside* the stage.
  final Color stageChip;

  /// The bottom navigation pill, which is dark in both modes.
  final Color nav;

  /// The third verdict colour, for a record bar segment.
  final Color mistrial;

  /// The accused's speech bubble on the case file.
  final Color bubble;

  final Color guiltyBg;
  final Color guiltyFg;
  final Color innocentBg;
  final Color innocentFg;

  @override
  CourtPalette copyWith({
    Color? accent,
    Color? surfaceAlt,
    Color? surfaceAlt2,
    Color? line,
    Color? inkDim,
    Color? inkFaint,
    Color? successText,
    Color? accentInk,
    Color? border,
    Color? shadowInk,
    Color? lineSoft,
    Color? stage,
    Color? stageChip,
    Color? nav,
    Color? mistrial,
    Color? bubble,
    Color? guiltyBg,
    Color? guiltyFg,
    Color? innocentBg,
    Color? innocentFg,
  }) => CourtPalette(
    accent: accent ?? this.accent,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    surfaceAlt2: surfaceAlt2 ?? this.surfaceAlt2,
    line: line ?? this.line,
    inkDim: inkDim ?? this.inkDim,
    inkFaint: inkFaint ?? this.inkFaint,
    successText: successText ?? this.successText,
    accentInk: accentInk ?? this.accentInk,
    border: border ?? this.border,
    shadowInk: shadowInk ?? this.shadowInk,
    lineSoft: lineSoft ?? this.lineSoft,
    stage: stage ?? this.stage,
    stageChip: stageChip ?? this.stageChip,
    nav: nav ?? this.nav,
    mistrial: mistrial ?? this.mistrial,
    bubble: bubble ?? this.bubble,
    guiltyBg: guiltyBg ?? this.guiltyBg,
    guiltyFg: guiltyFg ?? this.guiltyFg,
    innocentBg: innocentBg ?? this.innocentBg,
    innocentFg: innocentFg ?? this.innocentFg,
  );

  @override
  CourtPalette lerp(ThemeExtension<CourtPalette>? other, double t) {
    if (other is! CourtPalette) return this;
    return CourtPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceAlt2: Color.lerp(surfaceAlt2, other.surfaceAlt2, t)!,
      line: Color.lerp(line, other.line, t)!,
      inkDim: Color.lerp(inkDim, other.inkDim, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadowInk: Color.lerp(shadowInk, other.shadowInk, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      stageChip: Color.lerp(stageChip, other.stageChip, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      mistrial: Color.lerp(mistrial, other.mistrial, t)!,
      bubble: Color.lerp(bubble, other.bubble, t)!,
      guiltyBg: Color.lerp(guiltyBg, other.guiltyBg, t)!,
      guiltyFg: Color.lerp(guiltyFg, other.guiltyFg, t)!,
      innocentBg: Color.lerp(innocentBg, other.innocentBg, t)!,
      innocentFg: Color.lerp(innocentFg, other.innocentFg, t)!,
    );
  }
}

extension CourtTheme on BuildContext {
  CourtPalette get palette => Theme.of(this).extension<CourtPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Two typefaces, bundled in pubspec.yaml and never fetched at runtime.
/// Fredoka is display-only: it has no italic, stops at 700, and is too soft
/// to read at 14–16px. Nunito carries body text and rhymes with it.
const courtDisplayFont = 'Fredoka';
const courtBodyFont = 'Nunito';
const _font = courtBodyFont;

/// Geometry, straight off the canvas.
const courtRadiusSm = 14.0;
const courtRadius = 20.0;
const courtRadiusLg = 24.0;
const courtRadiusXl = 28.0;
const courtRadiusPill = 999.0;
const courtBorderThin = 2.0;
const courtBorderWidth = 3.0;
const courtShadowOffset = 4.0;
const courtShadowOffsetLg = 6.0;

/// Height of the floating nav pill, and the gap a scrolling body must leave
/// under itself so nothing ever ends up behind it.
const courtNavHeight = 70.0;
const courtNavBottomInset = 110.0;

/// The hard shadow: a solid offset with **zero blur**. Together with the 3px
/// border this is what makes a surface look like a physical, pressable tile
/// rather than a floating panel.
List<BoxShadow> courtHardShadow(
  BuildContext context, {
  Color? ink,
  double dy = courtShadowOffset,
}) => [
  BoxShadow(
    color: ink ?? context.palette.shadowInk,
    offset: Offset(0, dy),
    blurRadius: 0,
    spreadRadius: 0,
  ),
];

/// Kept so existing call sites compile while they are migrated one by one.
@Deprecated('Use courtHardShadow')
List<BoxShadow> courtShadow(BuildContext context) => courtHardShadow(context);

/// The whole look in one call: fill, 3px ink border, hard offset shadow.
/// Every raised surface should use this rather than rolling its own.
BoxDecoration courtChunk(
  BuildContext context, {
  Color? fill,
  Color? shadowInk,
  double radius = courtRadiusLg,
  double width = courtBorderWidth,
  double dy = courtShadowOffset,
}) => BoxDecoration(
  color: fill ?? context.colors.surfaceContainerHighest,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: context.palette.border, width: width),
  boxShadow: courtHardShadow(context, ink: shadowInk, dy: dy),
);

ThemeData _base(ColorScheme scheme, CourtPalette palette) {
  final text = Typography.material2021().black.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
    fontFamily: _font,
  );
  const pill = StadiumBorder();

  // Display sizes are Fredoka 700 and almost un-tracked: the canvas tightens
  // only the largest heading, and the old -1.8 tracking is what made this
  // read as a finance dashboard rather than a game.
  TextStyle? display(TextStyle? s, double height, double tracking) =>
      s?.copyWith(
        fontFamily: courtDisplayFont,
        fontWeight: FontWeight.w700,
        height: height,
        letterSpacing: tracking,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [palette],
    fontFamily: _font,
    textTheme: text.copyWith(
      displayLarge: display(text.displayLarge, 1.0, -1.0),
      displayMedium: display(text.displayMedium, 1.0, -0.8),
      displaySmall: display(text.displaySmall, 1.0, -0.5),
      headlineLarge: display(text.headlineLarge, 1.05, -0.4),
      headlineMedium: display(text.headlineMedium, 1.05, -0.3),
      headlineSmall: display(text.headlineSmall, 1.1, -0.2),
      titleLarge: display(text.titleLarge, 1.1, -0.1),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
      ),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      // Section labels: quiet grey, not a shout.
      labelSmall: text.labelSmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w800,
        color: palette.inkDim,
      ),
      bodySmall: text.bodySmall?.copyWith(height: 1.4, fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: courtDisplayFont,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(courtRadiusLg),
        side: BorderSide(color: palette.border, width: courtBorderWidth),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.onSurface,
      side: BorderSide(color: palette.border, width: courtBorderThin),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: scheme.surface,
      ),
      checkmarkColor: scheme.surface,
      shape: pill,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(courtRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(courtRadius),
        borderSide: BorderSide(color: palette.border, width: courtBorderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(courtRadius),
        borderSide: BorderSide(color: palette.accent, width: courtBorderWidth),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(courtRadius),
        borderSide: const BorderSide(color: CourtColors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(courtRadius),
        borderSide: const BorderSide(color: CourtColors.red, width: 2),
      ),
      hintStyle: TextStyle(color: palette.inkFaint, fontWeight: FontWeight.w600),
      labelStyle: TextStyle(color: palette.inkDim, fontWeight: FontWeight.w800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: scheme.onPrimary,
        // 58: the canvas's primary key, comfortably past the 48dp target.
        minimumSize: const Size.fromHeight(58),
        textStyle: const TextStyle(
          fontFamily: courtDisplayFont,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: palette.border, width: courtBorderWidth),
        textStyle: const TextStyle(
          fontFamily: courtDisplayFont,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: pill,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      shape: pill,
      extendedTextStyle: const TextStyle(
        fontFamily: courtDisplayFont,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(courtRadiusXl),
        side: BorderSide(color: palette.border, width: courtBorderWidth),
      ),
      titleTextStyle: TextStyle(
        fontFamily: courtDisplayFont,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.lineSoft, space: 1),
  );
}

ThemeData courtLightTheme() => _base(
  const ColorScheme.light(
    primary: CourtColors.violet,
    onPrimary: Colors.white,
    secondary: CourtColors.greenFill,
    onSecondary: CourtColors.onGreen,
    tertiary: CourtColors.orange,
    surface: CourtColors.lightBg,
    onSurface: CourtColors.lightInk,
    surfaceContainerHighest: CourtColors.lightSurface,
    error: CourtColors.red,
  ),
  const CourtPalette(
    accent: CourtColors.violet,
    surfaceAlt: CourtColors.lightTray,
    surfaceAlt2: CourtColors.lightTray2,
    line: CourtColors.lightLine,
    inkDim: CourtColors.lightInkDim,
    inkFaint: CourtColors.lightInkFaint,
    successText: CourtColors.notGuilty,
    accentInk: CourtColors.violetInk,
    border: CourtColors.lightInk,
    shadowInk: CourtColors.lightInk,
    lineSoft: CourtColors.lineSoft,
    stage: CourtColors.stageLight,
    stageChip: CourtColors.stageChipLight,
    nav: CourtColors.stageLight,
    mistrial: CourtColors.lightMistrial,
    bubble: CourtColors.bubblePinkLight,
    guiltyBg: CourtColors.guiltyBgLight,
    guiltyFg: CourtColors.guiltyFgLight,
    innocentBg: CourtColors.innocentBgLight,
    innocentFg: CourtColors.innocentFgLight,
  ),
);

ThemeData courtDarkTheme() => _base(
  const ColorScheme.dark(
    primary: CourtColors.violet,
    onPrimary: Colors.white,
    secondary: CourtColors.greenFill,
    onSecondary: CourtColors.onGreen,
    tertiary: CourtColors.orange,
    surface: CourtColors.darkBg,
    onSurface: CourtColors.darkInk,
    surfaceContainerHighest: CourtColors.darkSurface,
    error: CourtColors.red,
  ),
  const CourtPalette(
    accent: CourtColors.violet,
    surfaceAlt: CourtColors.darkTray,
    surfaceAlt2: CourtColors.darkTray2,
    line: CourtColors.darkLine,
    inkDim: CourtColors.darkInkDim,
    inkFaint: CourtColors.darkInkFaint,
    successText: CourtColors.darkGreenText,
    accentInk: CourtColors.violetInk,
    // The canvas keeps the black rim and the hard shadow in dark mode: on an
    // ink-plum surface a black edge still reads as an edge.
    border: CourtColors.darkLine,
    shadowInk: CourtColors.darkLine,
    lineSoft: CourtColors.darkTray2,
    stage: CourtColors.stageDark,
    stageChip: CourtColors.stageChipDark,
    nav: CourtColors.stageDark,
    mistrial: CourtColors.darkMistrial,
    bubble: CourtColors.bubblePinkDark,
    guiltyBg: CourtColors.guiltyBgDark,
    guiltyFg: CourtColors.guiltyFgDark,
    innocentBg: CourtColors.innocentBgDark,
    innocentFg: CourtColors.innocentFgDark,
  ),
);
