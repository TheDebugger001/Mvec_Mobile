import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens lifted from MVEC frontend `src/styles.css`.
class MvColors {
  MvColors._();

  static const primary = Color(0xFF55C9F2);
  static const primaryDark = Color(0xFF25ADDB);
  static const primaryDeep = Color(0xFF168DB8);
  static const accentLight = Color(0xFF9AE2FB);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentLight, primary, primaryDark],
  );

  static const ink = Color(0xFF16252D);
  static const muted = Color(0xFF71808A);
  static const border = Color(0xFFE4EDF1);
  static const soft = Color(0xFFEEFAFF);
  static const page = Color(0xFFF7FBFD);
  static const surface2 = Color(0xFFF7FAFB);
  static const tableHeaderBg = Color(0xFFEEFAFF);
  static const rowHover = Color(0x0A25ADDB); // rgba(37,173,219,.035~0.04)

  static const successBg = Color(0xFFEAFAF4);
  static const successText = Color(0xFF15815E);
  static const successText2 = Color(0xFF16845B);
  static const warningBg = Color(0xFFFFF6E7);
  static const warningText = Color(0xFFB56A00);
  static const errorBg = Color(0xFFFFF0F0);
  static const errorText = Color(0xFFB42318);
  static const dangerBtn = Color(0xFFD94B4B);
  static const dangerIcon = Color(0xFFC63E3E);
  static const badgeRed = Color(0xFFE53935);
  static const neutralBg = Color(0xFFF2F5F6);
  static const neutralText = Color(0xFF66767D);
  static const infoBoxBg = Color(0xFFEFFAFF);
  static const infoBoxBorder = Color(0xFFC8EDF8);
  static const infoBoxText = Color(0xFF49646E);
  static const metricIconBg = Color(0xFFEAF9FD);

  // Dark theme
  static const darkPage = Color(0xFF0B151B);
  static const darkSurface = Color(0xFF13232C);
  static const darkSurface2 = Color(0xFF1A303B);
  static const darkText = Color(0xFFEDF8FB);
  static const darkMuted = Color(0xFFA7BAC3);
  static const darkBorder = Color(0xFF2B4653);
  static const darkHeaderBg = Color(0xFF0D1820);
}

/// Theme flicker controlled at app level. Persisted via secure storage.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final page = isDark ? MvColors.darkPage : MvColors.page;
  final surface = isDark ? MvColors.darkSurface : Colors.white;
  final surface2 = isDark ? MvColors.darkSurface2 : MvColors.surface2;
  final text = isDark ? MvColors.darkText : MvColors.ink;
  final muted = isDark ? MvColors.darkMuted : MvColors.muted;
  final border = isDark ? MvColors.darkBorder : MvColors.border;
  final headerBg = isDark ? MvColors.darkHeaderBg : Colors.white;

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: page,
    canvasColor: surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MvColors.primary,
      brightness: brightness,
      primary: MvColors.primaryDeep,
      surface: surface,
    ),
    dividerColor: border,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: headerBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: isDark ? MvColors.darkText : MvColors.ink),
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: text,
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
    dialogTheme: DialogThemeData(backgroundColor: surface),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? MvColors.darkSurface : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: GoogleFonts.dmSans(fontSize: 13, color: muted),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w800, color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MvColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: MvColors.errorText),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MvColors.primaryDeep,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MvColors.primaryDeep),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: MvColors.primaryDeep,
      unselectedLabelColor: muted,
      indicatorColor: MvColors.primaryDeep,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: text,
      contentTextStyle: GoogleFonts.dmSans(color: page),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: const TooltipThemeData(),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surface2,
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: border),
    ),
  );
}

extension MvHeadingX on BuildContext {
  TextStyle get mvH1 => GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w800, color: Theme.of(this).colorScheme.onSurface);
  TextStyle get mvEyebrow => GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: MvColors.primaryDeep);
}