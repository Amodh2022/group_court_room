import 'package:flutter/material.dart';

/// The courtroom theme, taken from the "Finance App Design" reference: a soft
/// grey canvas, white rounded cards with barely-there shadows, round icon
/// buttons with small labels, black pill buttons and a floating black nav bar.
/// Verdict colours (red / green / orange) keep their meaning; primary actions
/// are black. Dart mirror of the CSS tokens in `web/src/styles.css`.
class CourtColors {
  const CourtColors._();

  // Semantic fills (sampled)
  static const blue = Color(0xFF1773E4);
  static const blueDeep = Color(0xFF125FBF);
  static const blueSoft = Color(0xFF3D8CF0);
  static const onBlue = Color(0xFFFFFFFF);

  static const greenFill = Color(0xFF7AE86F);
  static const onGreen = Color(0xFF0C3A14);
  static const presence = Color(0xFF89FB7D);

  static const red = Color(0xFFD9524C);
  static const orange = Color(0xFFFF7441);
  static const onOrange = Color(0xFF3B1404);
  static const yellow = Color(0xFFFFC929);

  // Verdicts. `notGuilty` is the text-safe green; `greenFill` is for fills.
  static const guilty = red;
  static const notGuilty = Color(0xFF1C9D46);
  static const bothGuilty = orange;
  static const insufficient = Color(0xFF8A8F98);

  // Light surfaces (the reference's white and its grey trays)
  static const lightBg = Color(0xFFF4F4F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTray = Color(0xFFF1F1F2);
  static const lightTray2 = Color(0xFFE6E6E8);
  static const lightLine = Color(0xFFE8E8EA);
  // Pastel hero wash used on the welcome screen.
  static const heroPink = Color(0xFFFF7ED8);
  static const heroViolet = Color(0xFFA78BFA);
  static const heroBlue = Color(0xFF8EB8FF);

  static const lightInk = Color(0xFF0E0E10);
  static const lightInkDim = Color(0xFF62666E);
  static const lightInkFaint = Color(0xFF9A9EA6);

  // Dark variant: same hues on deep neutrals. The reference is a light design,
  // so this exists for people whose phone is set to dark, not as the identity.
  static const darkBg = Color(0xFF0B0B0D);
  static const darkSurface = Color(0xFF17171A);
  static const darkTray = Color(0xFF1D2129);
  static const darkTray2 = Color(0xFF262B35);
  static const darkLine = Color(0xFF242932);
  static const darkInk = Color(0xFFF2F3F5);
  static const darkInkDim = Color(0xFFA4A9B3);
  static const darkInkFaint = Color(0xFF6F7480);
  static const darkGreenText = Color(0xFF6FE07A);

  // Squircle tile tints, picked per person so a face keeps its colour.
  static const tints = <Color>[
    yellow,
    Color(0xFFFF9D8F),
    greenFill,
    Color(0xFF8EC5FF),
    Color(0xFFC4B0FF),
  ];
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
  });

  /// The primary action colour (blue).
  final Color accent;

  /// The grey tray colour.
  final Color surfaceAlt;
  final Color surfaceAlt2;
  final Color line;
  final Color inkDim;
  final Color inkFaint;

  /// Green that is safe to read as text on this theme's surface.
  final Color successText;

  @override
  CourtPalette copyWith({
    Color? accent,
    Color? surfaceAlt,
    Color? surfaceAlt2,
    Color? line,
    Color? inkDim,
    Color? inkFaint,
    Color? successText,
  }) => CourtPalette(
    accent: accent ?? this.accent,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    surfaceAlt2: surfaceAlt2 ?? this.surfaceAlt2,
    line: line ?? this.line,
    inkDim: inkDim ?? this.inkDim,
    inkFaint: inkFaint ?? this.inkFaint,
    successText: successText ?? this.successText,
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
    );
  }
}

extension CourtTheme on BuildContext {
  CourtPalette get palette => Theme.of(this).extension<CourtPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// The one typeface. Bundled in pubspec.yaml, not fetched at runtime.
const courtDisplayFont = 'Inter';
const _font = courtDisplayFont;

/// Soft, broad shadow used under cards, like the reference's floating panels.
List<BoxShadow> courtShadow(BuildContext context) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.05),
    blurRadius: 30,
    offset: const Offset(0, 8),
  ),
  BoxShadow(
    color: Colors.black.withValues(alpha: context.isDark ? 0.35 : 0.04),
    blurRadius: 3,
    offset: const Offset(0, 1),
  ),
];

ThemeData _base(ColorScheme scheme, CourtPalette palette) {
  final text = Typography.material2021().black.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
    fontFamily: _font,
  );
  const pill = StadiumBorder();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [palette],
    fontFamily: _font,
    textTheme: text.copyWith(
      // Light, large headings; bold names. The reference pairs both.
      displayLarge: text.displayLarge?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.05,
        letterSpacing: -1.8,
      ),
      displayMedium: text.displayMedium?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.08,
        letterSpacing: -1.4,
      ),
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.08,
        letterSpacing: -0.9,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.6,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      // Section labels: quiet grey, not a shout.
      labelSmall: text.labelSmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w600,
        color: palette.inkFaint,
      ),
      bodySmall: text.bodySmall?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.5),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: _font,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      selectedColor: palette.accent,
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: palette.inkDim,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: scheme.onPrimary,
      ),
      checkmarkColor: scheme.onPrimary,
      shape: pill,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: CourtColors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: CourtColors.red, width: 2),
      ),
      hintStyle: TextStyle(color: palette.inkFaint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: scheme.onPrimary,
        // 52 keeps every primary action a comfortable touch target.
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: pill,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: palette.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: pill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: pill,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: pill,
      extendedTextStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: palette.line, space: 1),
  );
}

ThemeData courtLightTheme() => _base(
  const ColorScheme.light(
    primary: CourtColors.lightInk,
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
    accent: CourtColors.lightInk,
    surfaceAlt: CourtColors.lightTray,
    surfaceAlt2: CourtColors.lightTray2,
    line: CourtColors.lightLine,
    inkDim: CourtColors.lightInkDim,
    inkFaint: CourtColors.lightInkFaint,
    successText: CourtColors.notGuilty,
  ),
);

ThemeData courtDarkTheme() => _base(
  const ColorScheme.dark(
    primary: Colors.white,
    onPrimary: CourtColors.darkBg,
    secondary: CourtColors.greenFill,
    onSecondary: CourtColors.onGreen,
    tertiary: CourtColors.orange,
    surface: CourtColors.darkBg,
    onSurface: CourtColors.darkInk,
    surfaceContainerHighest: CourtColors.darkSurface,
    error: CourtColors.red,
  ),
  const CourtPalette(
    accent: Colors.white,
    surfaceAlt: CourtColors.darkTray,
    surfaceAlt2: CourtColors.darkTray2,
    line: CourtColors.darkLine,
    inkDim: CourtColors.darkInkDim,
    inkFaint: CourtColors.darkInkFaint,
    successText: CourtColors.darkGreenText,
  ),
);
