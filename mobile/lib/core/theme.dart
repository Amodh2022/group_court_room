import 'package:flutter/material.dart';

/// The "Sue Me — App Screens" design canvas, matched to its artboards: a cool
/// grey page, white cards lifted by a soft blue-grey shadow (no borders), blue
/// as the action colour, orange for guilty and teal for not guilty, Outfit
/// throughout.
///
/// Names from the earlier theme are kept (`violet`, `red`, `greenFill`, ...) so
/// call sites did not have to move; the *values* are the canvas's. `violet` is
/// now the canvas blue.
class CourtColors {
  const CourtColors._();

  // Brand / action: canvas blue `#2F5BD8` and the darker shade under it.
  static const violet = Color(0xFF2F5BD8);
  static const violetHover = Color(0xFF2449B5);
  static const violetInk = Color(0xFF1B3A94);
  static const blueDark = Color(0xFF6C8EF0);

  static const blue = Color(0xFF2F5BD8);
  static const blueDeep = Color(0xFF2449B5);
  static const blueSoft = Color(0xFF5FD8E8);
  static const onBlue = Color(0xFFFFFFFF);

  // Teal = not guilty / success. Orange = guilty / urgency.
  static const greenFill = Color(0xFF1E9E97);
  static const greenDeep = Color(0xFF1A8C86);
  static const onGreen = Color(0xFFFFFFFF);
  static const presence = Color(0xFF1E9E97);

  static const red = Color(0xFFE2552D);
  static const redDeep = Color(0xFFC2431E);
  static const redText = Color(0xFFE2552D);
  static const redInk = Color(0xFFD9502A);
  static const redOnStage = Color(0xFFFF7A54);
  static const orange = Color(0xFFE2552D);
  static const orangeDeep = Color(0xFFC2431E);
  static const onOrange = Color(0xFFFFFFFF);
  static const yellow = Color(0xFFF5B82E);
  static const yellowDeep = Color(0xFFD99A12);
  static const pink = Color(0xFFB44FA8);
  static const gold = Color(0xFFF5B82E);
  static const goldDeep = Color(0xFFD99A12);

  static const guilty = red;
  static const notGuilty = Color(0xFF1E9E97);
  static const bothGuilty = orange;
  static const insufficient = Color(0xFF8A90A6);

  // The "stage": the one dark panel that carries a loud number.
  static const stageLight = Color(0xFF1E2235);
  static const stageDark = Color(0xFF0A0D15);
  static const stageInk = Color(0xFFFFFFFF);
  static const stageDim = Color(0xFFB9BECE);
  static const stageChipLight = Color(0xFF2B3050);
  static const stageChipDark = Color(0xFF191D29);

  // Light surfaces.
  static const lightBg = Color(0xFFF3F5FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTray = Color(0xFFEEF1F7);
  static const lightTray2 = Color(0xFFE6E9F1);
  static const lightLine = Color(0xFFE6E9F1);
  static const lineSoft = Color(0xFFEEF1F7);
  static const heroPink = Color(0xFFB44FA8);
  static const heroViolet = Color(0xFF5B7CFA);
  static const heroBlue = Color(0xFF5B7CFA);

  static const lightInk = Color(0xFF1E2235);
  static const lightInkDim = Color(0xFF8A90A6);
  static const lightInkFaint = Color(0xFFB9BECE);
  static const lightMistrial = Color(0xFFB9BECE);

  // Dark.
  static const darkBg = Color(0xFF0F121B);
  static const darkSurface = Color(0xFF191D29);
  static const darkTray = Color(0xFF262B3A);
  static const darkTray2 = Color(0xFF2E3446);
  static const darkLine = Color(0xFF262B3A);
  static const darkInk = Color(0xFFEEF0F7);
  static const darkInkDim = Color(0xFF8A90A6);
  static const darkInkFaint = Color(0xFF4A5068);
  static const darkGreenText = Color(0xFF3CCFC6);
  static const darkMistrial = Color(0xFF4A5068);

  // Tints (accent at ~10% on light, rgba on dark).
  static const blueTintLight = Color(0xFFE8EEFC);
  static const orangeTintLight = Color(0xFFFDEDE7);
  static const tealTintLight = Color(0xFFE2F6F4);
  static const goldTintLight = Color(0xFFFFF4D6);
  static const blueTintDark = Color(0x382F5BD8);
  static const orangeTintDark = Color(0x2EF0643C);
  static const tealTintDark = Color(0x2E2BB8B0);
  static const goldTintDark = Color(0x2EF5B82E);

  // Vote buttons on a card.
  static const guiltyBgLight = orangeTintLight;
  static const guiltyFgLight = Color(0xFFE2552D);
  static const innocentBgLight = tealTintLight;
  static const innocentFgLight = Color(0xFF1A8C86);
  static const guiltyBgDark = orangeTintDark;
  static const guiltyFgDark = Color(0xFFFF7A54);
  static const innocentBgDark = tealTintDark;
  static const innocentFgDark = Color(0xFF3CCFC6);

  static const bubblePinkLight = orangeTintLight;
  static const bubblePinkDark = orangeTintDark;

  /// Avatar tints, cycled per person. Order: orange, blue, teal, gold, magenta.
  static const tints = <Color>[
    Color(0xFFE2552D),
    Color(0xFF2F5BD8),
    Color(0xFF1E9E97),
    Color(0xFFC98A0A),
    Color(0xFFB44FA8),
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

/// One typeface, bundled in pubspec.yaml and never fetched at runtime.
const courtDisplayFont = 'Outfit';
const courtBodyFont = 'Outfit';
const _font = courtBodyFont;

/// Geometry, straight off the canvas.
const courtRadiusSm = 14.0;
const courtRadius = 20.0;
const courtRadiusLg = 24.0;
const courtRadiusXl = 28.0;
const courtRadiusPill = 999.0;
// The canvas has no borders: surfaces are lifted by shadow alone. The widths
// stay so call sites compile and the border colour is transparent. They are
// not 0: a zero width is a hairline, which Flutter refuses to draw on a
// rounded box. A screen that wants a real outline (a selected option) passes
// its own width.
const courtBorderThin = 0.01;
const courtBorderWidth = 0.01;
const courtShadowOffset = 10.0;
const courtShadowOffsetLg = 14.0;

/// Height of the floating nav pill, and the gap a scrolling body must leave
/// under itself so nothing ever ends up behind it.
const courtNavHeight = 84.0;
const courtNavBottomInset = 104.0;

/// The canvas's soft lift: `0 10px 30px rgba(46,72,140,.08)` on light, a
/// heavier black one on dark. `dy` > 10 gives the larger variant; `dy` < 10
/// the small `0 4px 14px` row shadow. `ink` overrides the colour (e.g. the
/// blue glow under a primary button).
List<BoxShadow> courtHardShadow(
  BuildContext context, {
  Color? ink,
  double dy = courtShadowOffset,
}) {
  final dark = context.isDark;
  final small = dy <= 6;
  return [
    BoxShadow(
      color:
          ink ??
          (dark
              ? Color.fromRGBO(0, 0, 0, small ? .25 : .35)
              : Color.fromRGBO(46, 72, 140, small ? .06 : .08)),
      offset: Offset(0, small ? 4 : 10),
      blurRadius: small ? 14 : 30,
    ),
  ];
}

/// Kept so existing call sites compile while they are migrated one by one.
@Deprecated('Use courtHardShadow')
List<BoxShadow> courtShadow(BuildContext context) => courtHardShadow(context);

/// The whole look in one call: fill, soft shadow, no border.
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
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      // Section labels: quiet grey, not a shout.
      labelSmall: text.labelSmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w800,
        color: palette.inkDim,
      ),
      bodySmall: text.bodySmall?.copyWith(
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: text.bodyLarge?.copyWith(
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
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
      hintStyle: TextStyle(
        color: palette.inkFaint,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: TextStyle(color: palette.inkDim, fontWeight: FontWeight.w800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: scheme.onPrimary,
        // 58: the canvas's primary key, comfortably past the 48dp target.
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(
          fontFamily: courtDisplayFont,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        textStyle: const TextStyle(
          fontFamily: courtBodyFont,
          fontWeight: FontWeight.w600,
        ),
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
    border: Colors.transparent,
    shadowInk: Color(0x142E488C),
    lineSoft: CourtColors.lineSoft,
    stage: CourtColors.stageLight,
    stageChip: CourtColors.stageChipLight,
    nav: CourtColors.lightSurface,
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
    primary: CourtColors.blueDark,
    onPrimary: Color(0xFF0F121B),
    secondary: CourtColors.greenFill,
    onSecondary: CourtColors.onGreen,
    tertiary: CourtColors.orange,
    surface: CourtColors.darkBg,
    onSurface: CourtColors.darkInk,
    surfaceContainerHighest: CourtColors.darkSurface,
    error: CourtColors.red,
  ),
  const CourtPalette(
    accent: CourtColors.blueDark,
    surfaceAlt: CourtColors.darkTray,
    surfaceAlt2: CourtColors.darkTray2,
    line: CourtColors.darkLine,
    inkDim: CourtColors.darkInkDim,
    inkFaint: CourtColors.darkInkFaint,
    successText: CourtColors.darkGreenText,
    accentInk: CourtColors.violetInk,
    // (no border in the canvas)
    // The canvas keeps the black rim and the hard shadow in dark mode: on an
    // ink-plum surface a black edge still reads as an edge.
    border: Colors.transparent,
    shadowInk: Color(0x59000000),
    lineSoft: CourtColors.darkTray2,
    stage: CourtColors.stageDark,
    stageChip: CourtColors.stageChipDark,
    nav: CourtColors.darkSurface,
    mistrial: CourtColors.darkMistrial,
    bubble: CourtColors.bubblePinkDark,
    guiltyBg: CourtColors.guiltyBgDark,
    guiltyFg: CourtColors.guiltyFgDark,
    innocentBg: CourtColors.innocentBgDark,
    innocentFg: CourtColors.innocentFgDark,
  ),
);
