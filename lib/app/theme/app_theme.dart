import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/theme_choice.dart';
import 'tavli_colors.dart';
import 'tavli_palette.dart';
import 'tavli_status_colors.dart';

/// Ugrađen font (assets/fonts).
const tavliFontFamily = 'PlusJakartaSans';

/// [ThemeData] za temu i osvetljenost: [ColorScheme] je sastavljen ručno od
/// odobrenih tokena (ne `fromSeed`), ostali tokeni su u [TavliColors].
ThemeData buildTavliTheme(TavliTheme theme, Brightness brightness) {
  final p = TavliPalette.of(theme, brightness);
  final dark = brightness == Brightness.dark;
  final other = TavliPalette.of(
    theme,
    dark ? Brightness.light : Brightness.dark,
  );
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.container,
    onPrimaryContainer: p.onContainer,
    secondary: p.primary,
    onSecondary: p.onPrimary,
    secondaryContainer: p.container,
    onSecondaryContainer: p.onContainer,
    tertiary: p.onContainer,
    onTertiary: p.container,
    tertiaryContainer: p.tints.first,
    onTertiaryContainer: p.text,
    // Material 3 osnovne boje greške.
    error: dark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E),
    onError: dark ? const Color(0xFF601410) : const Color(0xFFFFFFFF),
    errorContainer: dark ? const Color(0xFF8C1D18) : const Color(0xFFF9DEDC),
    onErrorContainer: dark ? const Color(0xFFF9DEDC) : const Color(0xFF410E0B),
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceDim: p.bg,
    surfaceBright: dark ? p.line : p.surface,
    surfaceContainerLowest: dark ? p.bg : p.surface,
    surfaceContainerLow: Color.lerp(p.surface, p.bg, 0.5),
    surfaceContainer: dark ? p.surface : p.bg,
    surfaceContainerHigh: dark
        ? Color.lerp(p.surface, p.line, 0.35)
        : Color.lerp(p.bg, p.line, 0.5),
    surfaceContainerHighest: p.line,
    outline: p.boxLine,
    outlineVariant: p.line,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: p.text,
    onInverseSurface: p.bg,
    inversePrimary: other.primary,
    surfaceTint: const Color(0x00000000),
  );

  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: apple
        ? const CupertinoThemeData().textTheme.textStyle.fontFamily
        : tavliFontFamily,
    fontFamilyFallback: const [tavliFontFamily],
  );
  final text = base.textTheme;
  TextStyle? heading(TextStyle? s, {FontWeight weight = FontWeight.w700}) => s
      ?.copyWith(fontWeight: weight, letterSpacing: -0.02 * (s.fontSize ?? 16));
  final textTheme = text.copyWith(
    displayLarge: heading(text.displayLarge),
    displayMedium: heading(text.displayMedium),
    displaySmall: heading(text.displaySmall),
    headlineLarge: heading(text.headlineLarge),
    headlineMedium: heading(text.headlineMedium)?.copyWith(fontSize: 32),
    headlineSmall: heading(text.headlineSmall),
    titleLarge: heading(text.titleLarge),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
    bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.5),
    labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  final lineSide = BorderSide(color: p.line);
  WidgetStateProperty<T> selected<T>(T on, T off) =>
      WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? on : off,
      );

  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    textTheme: textTheme,
    extensions: [
      dark ? TavliStatusColors.dark : TavliStatusColors.light,
      TavliColors(
        motif: theme,
        bg: p.bg,
        line: p.line,
        boxLine: p.boxLine,
        tints: p.tints,
      ),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      toolbarHeight: 64,
      shape: Border(bottom: lineSide),
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: p.text),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: lineSide,
      ),
    ),
    chipTheme: ChipThemeData(
      color: selected(p.primary, p.surface),
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BorderSide.none : lineSide,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: textTheme.labelLarge?.copyWith(
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onPrimary : p.text,
        ),
      ),
      checkmarkColor: p.onPrimary,
      iconTheme: IconThemeData(color: p.muted, size: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: p.text,
        side: BorderSide(color: p.boxLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(p.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(lineSide),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      constraints: const BoxConstraints(minHeight: 50),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: p.muted, fontSize: 16),
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: p.text, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: lineSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: lineSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: p.container,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      iconTheme: selected(
        IconThemeData(color: p.onContainer),
        IconThemeData(color: p.muted),
      ),
      labelTextStyle: selected(
        textTheme.labelMedium?.copyWith(
          color: p.onContainer,
          fontWeight: FontWeight.w700,
        ),
        textTheme.labelMedium?.copyWith(
          color: p.muted,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.bg,
      indicatorColor: p.container,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      selectedIconTheme: IconThemeData(color: p.onContainer, size: 20),
      unselectedIconTheme: IconThemeData(color: p.muted, size: 20),
      selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: p.onContainer,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: p.muted),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
      extendedTextStyle: textTheme.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 12,
      iconColor: p.muted,
      selectedColor: p.onContainer,
      selectedTileColor: p.container,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.boxLine,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.container,
      circularTrackColor: p.container,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: p.boxLine, width: 2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: selected(p.container, p.surface),
        foregroundColor: selected(p.onContainer, p.text),
        side: WidgetStatePropertyAll(lineSide),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: p.muted,
        hoverColor: p.container,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: p.text,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: textTheme.labelMedium?.copyWith(color: p.surface),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.text,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.bg),
      actionTextColor: other.primary,
    ),
  );
}
