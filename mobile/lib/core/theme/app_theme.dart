import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Colour palette ───────────────────────────────────────────────────────────
//
// Single source of truth for every activity-type and surface colour in the app.
// Import this file wherever segment/tag colours are needed.

abstract final class AppColors {
  // ── Outdoor segment tags ───────────────────────────────────────────────────
  static const warmUp   = Color(0xFFFFD740); // amber accent
  static const work     = Color(0xFF69F0AE); // vibrant green
  static const rest     = Color(0xFF80D8FF); // calm blue
  static const coolDown = Color(0xFFEA80FC); // soft purple
  static const custom   = Color(0xFF64FFDA); // teal accent

  // ── Gym segment types ──────────────────────────────────────────────────────
  static const emom     = Color(0xFF64FFDA); // teal
  static const amrap    = Color(0xFFFFAB40); // orange
  static const forTime  = Color(0xFFFF6E6E); // coral-red
  static const gymRest  = Color(0xFF9E9E9E); // neutral grey

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const success = Color(0xFF69F0AE); // = work green
  static const danger  = Color(0xFFFF6E6E); // = forTime coral-red
  static const warning = Color(0xFFFFD740); // = warmUp amber

  // ── Surface palette ────────────────────────────────────────────────────────
  static const background      = Color(0xFF0D0D0F);
  static const surface         = Color(0xFF1A1A1C);
  static const surfaceElevated = Color(0xFF252528);
}

// ─── Theme ────────────────────────────────────────────────────────────────────

abstract final class AppTheme {
  static ThemeData get dark {
    final cs = ColorScheme.fromSeed(
      seedColor: AppColors.work,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceElevated,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: AppColors.background,

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // ── Bottom navigation bar ──────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.work.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.work);
          }
          return IconThemeData(color: Colors.white.withValues(alpha: 0.45));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.work,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
          );
        }),
      ),

      // ── Card ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // ── Input decoration ───────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.work, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        prefixIconColor: Colors.white.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ── Filled button ──────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.work,
          foregroundColor: const Color(0xFF003319),
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Outlined button ────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.work,
          minimumSize: const Size(88, 48),
          side: const BorderSide(color: AppColors.work),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Text button ────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.work,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // ── Elevated button ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),

      // ── FAB ────────────────────────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.work,
        foregroundColor: Color(0xFF003319),
        extendedTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),

      // ── Tab bar ────────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.work,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
        indicatorColor: AppColors.work,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 13,
        ),
      ),

      // ── Bottom sheet ───────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        dragHandleColor: Colors.white.withValues(alpha: 0.3),
      ),

      // ── Dialog ─────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Divider ────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),

      // ── SnackBar ───────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.work,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── ListTile ───────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        iconColor: Colors.white.withValues(alpha: 0.7),
      ),

      // ── Checkbox ───────────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.work;
          return null;
        }),
        checkColor: const WidgetStatePropertyAll(Color(0xFF003319)),
      ),
    );
  }

  // ── Shared text style for large timer displays ─────────────────────────────
  //
  // Uses tabular figures so digit width is constant — prevents the timer
  // display from jumping around during countdown.

  static TextStyle timerStyle({
    double fontSize = 80,
    Color color = Colors.white,
    FontWeight weight = FontWeight.bold,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -1,
      );
}
