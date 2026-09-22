import 'package:flutter/material.dart';

/// Color palette mirrored from the MVEC web app (mvec_frontend) homepage.
///
/// Tracks the CSS custom properties in `styles.css`:
/// `--blue`, `--blue-dark`, `--blue-deep`, `--gradient`, `--page`,
/// `--surface`, `--surface-2`, `--text`, `--muted-text`, `--border`,
/// `--soft` and the rating/status colors used across the storefront.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF55C9F2); // --blue
  static const Color primaryDark = Color(0xFF25ADDB); // --blue-dark
  static const Color primaryDeep = Color(0xFF168DB8); // --blue-deep
  static const Color primaryLight = Color(0xFF9AE2FB); // gradient start

  /// Brand gradient, same as `--gradient` in the web app:
  /// `#9ae2fb 0%, #55c9f2 45%, #25addb 100%`.
  static const List<Color> brandGradient = <Color>[
    Color(0xFF9AE2FB),
    Color(0xFF55C9F2),
    Color(0xFF25ADDB),
  ];

  static const Color secondary = Color(0xFFF0A629); // star rating amber
  static const Color accent = Color(0xFF168D67); // price-drop green
  static const Color soft = Color(0xFFEEFAFF); // --soft

  static const Color background = Color(0xFFF7FBFD); // --page
  static const Color surface = Colors.white; // --surface
  static const Color surfaceVariant = Color(0xFFF7FAFB); // --surface-2
  static const Color textPrimary = Color(0xFF16252D); // --text / --ink
  static const Color textSecondary = Color(0xFF71808A); // --muted-text
  static const Color border = Color(0xFFE4EDF1); // --border / --line

  static const Color error = Color(0xFFC22F2F); // status.danger
  static const Color warning = Color(0xFFB56A00); // status.warning/pending
  static const Color success = Color(0xFF15815E); // status.active
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          );

  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          );

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          );

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: AppColors.textPrimary,
          );

  static TextStyle bodySecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: AppColors.textSecondary,
          );

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            color: AppColors.textSecondary,
          );

  static TextStyle price(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      );

  static TextStyle oldPrice(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: AppColors.textSecondary,
        decoration: TextDecoration.lineThrough,
      );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
          primary: AppColors.primaryDark,
          secondary: AppColors.secondary,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.soft,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.soft,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.border),
      );
}