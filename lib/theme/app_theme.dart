import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeVariant { classic, refined }

/// Persists the active theme variant. Defaults to `classic` so existing users
/// see no change until they opt in from Settings.
final themeVariantProvider =
    StateNotifierProvider<ThemeVariantNotifier, ThemeVariant>((ref) {
  return ThemeVariantNotifier();
});

class ThemeVariantNotifier extends StateNotifier<ThemeVariant> {
  ThemeVariantNotifier() : super(ThemeVariant.classic) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('themeVariant');
    if (val == 'refined') state = ThemeVariant.refined;
  }

  Future<void> set(ThemeVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeVariant',
      variant == ThemeVariant.refined ? 'refined' : 'classic',
    );
  }
}

// ---------------------------------------------------------------------------
// Classic theme — the original look, preserved verbatim.
// ---------------------------------------------------------------------------

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4CAF50),
    brightness: Brightness.light,
  ),
);

final appDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4CAF50),
    brightness: Brightness.dark,
  ),
);

// ---------------------------------------------------------------------------
// Refined theme — softer sage palette, tighter type, rounded shapes, subtle
// elevation. Drop-in replacement: same ColorScheme roles, just more cohesive.
// ---------------------------------------------------------------------------

const _refinedSeed = Color(0xFF2F7D4F); // deeper, less neon than Material green

/// 3-step elevation scale for the refined theme — used across card / FAB /
/// dialog / modal. Keeps the visual vocabulary finite: flat at rest, a single
/// soft lift at hover, a deeper lift when pressed or modal.
const double refinedElevationRest = 0;
const double refinedElevationHover = 2;
const double refinedElevationPressed = 6;

ThemeData _buildRefined(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _refinedSeed,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;

  final baseText = (isDark ? Typography.whiteMountainView : Typography.blackMountainView);
  final textTheme = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(letterSpacing: -0.5, fontWeight: FontWeight.w600),
    headlineMedium: baseText.headlineMedium?.copyWith(letterSpacing: -0.3, fontWeight: FontWeight.w600),
    titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
  );

  // Sage-tinted shadow so elevation reads with the palette instead of muddying it.
  final shadowColor = _refinedSeed.withValues(alpha: isDark ? 0.8 : 0.35);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? scheme.surface : const Color(0xFFF7F6F2),
    textTheme: textTheme,
    shadowColor: shadowColor,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: isDark ? scheme.surface : const Color(0xFFF7F6F2),
      surfaceTintColor: scheme.surfaceTint,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: refinedElevationRest,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 24,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: refinedElevationHover,
      highlightElevation: refinedElevationPressed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: textTheme.labelMedium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? scheme.surfaceContainerHighest
          : const Color(0xFFFFFFFF),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 56,
      elevation: refinedElevationHover,
      backgroundColor: isDark ? scheme.surface : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: refinedElevationPressed,
      shadowColor: shadowColor,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: refinedElevationPressed,
      shadowColor: shadowColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check, size: 16);
        }
        return null;
      }),
    ),
  );
}

final appRefinedTheme = _buildRefined(Brightness.light);
final appRefinedDarkTheme = _buildRefined(Brightness.dark);
