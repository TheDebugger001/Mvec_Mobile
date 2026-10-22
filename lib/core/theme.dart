import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Importing cupertinopageTransistorsitionsBuilder to use the default iOS page transition for iOS platform.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import '../widgets/motion.dart' show MvPageTransitionsBuilder;

/// Brand tokens for the Ikiguzi mobile app.
///
/// The deep teal and the soft neutrals are sampled from the Landing page
/// design (`#064F65` for the brand, `#F3F3F3` / `#F5F5F5` for recessed fills),
/// so every screen reads as one app.
class MvColors {
  MvColors._();

  /// The brand teal. Every primary button, active state, badge and selected
  /// tab resolves back to this one token, so the accent can never drift
  /// between screens.
  static const brand = Color(0xFF064F65);

  /// Slightly lighter teal used as the start of the brand gradient.
  static const brandLight = Color(0xFF0B6580);

  /// Pressed / dark end of the brand gradient.
  static const brandDark = Color(0xFF043C4E);

  /// Brand fill on dark surfaces, where `#064F65` would sink into the page.
  static const brandOnDark = Color(0xFF0E7A97);

  /// Old name of [brand], kept so dashboard code that still says `skyBlue`
  /// compiles unchanged (it now resolves to the brand teal).
  static const skyBlue = brand;

  /// Aliases kept for the call sites that read the accent as `primary`.
  static const primary = brand;
  static const primaryDark = brandDark;
  static const primaryDeep = brand;

  /// Light teal: brand text and icons on dark surfaces.
  static const accentLight = Color(0xFF7CCADF);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandLight, brand],
  );

  static const gradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1290B0), brandOnDark],
  );

  static const ink = Color(0xFF12232B);
  static const muted = Color(0xFF6B7B84);
  static const border = Color(0xFFE4EAED);
  static const soft = Color(0xFFE9F3F6);
  static const page = Color(0xFFF6F8F9);
  static const surface2 = Color(0xFFF3F4F5);
  static const tableHeaderBg = Color(0xFFE9F3F6);
  static const rowHover = Color(0x0A064F65);

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
  static const infoBoxBg = Color(0xFFEBF5F8);
  static const infoBoxBorder = Color(0xFFCBE3EA);
  static const infoBoxText = Color(0xFF3F5E69);
  static const metricIconBg = Color(0xFFE6F2F5);

  // Dark theme
  static const darkPage = Color(0xFF0A1418);
  static const darkSurface = Color(0xFF12212A);
  static const darkSurface2 = Color(0xFF1A2E39);
  static const darkSoft = Color(0xFF123240);
  static const darkText = Color(0xFFEDF8FB);
  static const darkMuted = Color(0xFFA7BAC3);
  static const darkBorder = Color(0xFF2B4653);
  static const darkHeaderBg = Color(0xFF0E1B22);

  /// Saved-wishlist heart, and the soft pink circle behind it.
  static const rose = Color(0xFFE0457B);
  static const pink = Color(0xFFF5E8F2);
}

/// Mode-aware surface, text and border tokens.
///
/// Exposed as a [ThemeExtension] so widgets read them from
/// `context.mv` instead of hard-coding a light-only colour. Every storefront
/// widget pulls its backgrounds, borders and text from here, which is what
/// keeps the whole app legible when the dark-mode toggle flips the theme.
@immutable
class MvPalette extends ThemeExtension<MvPalette> {
  const MvPalette({
    required this.page,
    required this.surface,
    required this.surfaceMuted,
    required this.soft,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accentDeep,
    required this.onAccent,
    required this.shadow,
    required this.accent,
  });

  /// Light-mode tokens.
  factory MvPalette.light() => const MvPalette(
    page: MvColors.page,
    surface: Colors.white,
    surfaceMuted: MvColors.surface2,
    soft: MvColors.soft,
    border: MvColors.border,
    text: MvColors.ink,
    textMuted: MvColors.muted,
    accentDeep: MvColors.primaryDeep,
    onAccent: Colors.white,
    shadow: Color(0x14000000),
    accent: MvColors.brand,
  );

  /// Dark-mode tokens. Surfaces step up from the page background so cards stay
  /// separable, and the deep teal swaps to its light variant because
  /// `#064F65` is unreadable on the dark surface.
  factory MvPalette.dark() => const MvPalette(
    page: MvColors.darkPage,
    surface: MvColors.darkSurface,
    surfaceMuted: MvColors.darkSurface2,
    soft: MvColors.darkSoft,
    border: MvColors.darkBorder,
    text: MvColors.darkText,
    textMuted: MvColors.darkMuted,
    accentDeep: MvColors.accentLight,
    onAccent: Colors.white,
    shadow: Color(0x66000000),
    accent: MvColors.brandOnDark,
  );

  /// Page background behind cards and bars.
  final Color page;

  /// Card, top-bar, sheet and floating-bar background.
  final Color surface;

  /// Chips, inputs and other recessed fills.
  final Color surfaceMuted;

  /// Brand-tinted fill for placeholders, avatars and empty states.
  final Color soft;

  /// Hairline borders on cards, bars and inputs.
  final Color border;

  /// High-contrast body text.
  final Color text;

  /// De-emphasised supporting text.
  final Color textMuted;

  /// Deep teal for brand glyphs and text; brightened in dark mode.
  final Color accentDeep;

  /// Text and icons drawn on top of an [accent] fill.
  final Color onAccent;

  /// Drop-shadow colour for floating surfaces.
  final Color shadow;

  /// Fill for primary buttons and active states: the brand teal in light
  /// mode, a lighter teal in dark mode where `#064F65` would disappear.
  final Color accent;

  @override
  MvPalette copyWith({
    Color? page,
    Color? surface,
    Color? surfaceMuted,
    Color? soft,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? accentDeep,
    Color? onAccent,
    Color? shadow,
    Color? accent,
  }) {
    return MvPalette(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      soft: soft ?? this.soft,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      accentDeep: accentDeep ?? this.accentDeep,
      onAccent: onAccent ?? this.onAccent,
      shadow: shadow ?? this.shadow,
      accent: accent ?? this.accent,
    );
  }

  @override
  MvPalette lerp(covariant MvPalette? other, double t) {
    if (other == null) return this;
    return MvPalette(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension MvThemeX on BuildContext {
  /// Mode-aware design tokens for the active theme.
  MvPalette get mv => Theme.of(this).extension<MvPalette>()!;

  /// True while the dark theme is on screen.
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

/// Shared corner radii, so cards, fields and buttons round the same way.
class MvRadius {
  MvRadius._();
  static const double field = 12;
  static const double button = 14;
  static const double card = 16;
  static const double sheet = 24;
  static const double chip = 999;
  static const double input = field;
  static const double image = 14;
}

extension MvShadowX on BuildContext {
  /// Soft elevation for cards and floating bars (barely there in light mode).
  List<BoxShadow> get mvCardShadow => [BoxShadow(color: mv.shadow, blurRadius: 14, offset: const Offset(0, 4))];
}

/// Optional persistent store for the theme preference.
///
/// `main()` resolves the real instance before the first frame and overrides
/// this with it; when it is null (widget tests, or any embedding that has not
/// loaded storage yet) the theme simply stays in memory.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

const String _themeModeKey = 'mvec.theme_mode';

/// Theme flicker controlled at app level and persisted across launches.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.watch(sharedPreferencesProvider)?.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.light,
    );
  }

  /// Switches between the light and dark themes.
  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  /// Applies [mode] and remembers it for the next launch.
  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider)?.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Light theme, built once and shared.
final lightAppTheme = buildAppTheme(Brightness.light);

/// Dark theme, built once and shared.
final darkAppTheme = buildAppTheme(Brightness.dark);

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? MvPalette.dark() : MvPalette.light();
  final page = palette.page;
  final surface = palette.surface;
  final surface2 = palette.surfaceMuted;
  final text = palette.text;
  final muted = palette.textMuted;
  final border = palette.border;
  final headerBg = isDark ? MvColors.darkHeaderBg : surface;

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: page,
    canvasColor: surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MvColors.brand,
      brightness: brightness,
      primary: palette.accent,
      surface: surface,
    ),
    extensions: <ThemeExtension<dynamic>>[palette],
    dividerColor: border,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    // Short fade-and-slide between screens; iOS keeps its swipe-back transition.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: MvPageTransitionsBuilder(),
      TargetPlatform.fuchsia: MvPageTransitionsBuilder(),
      TargetPlatform.linux: MvPageTransitionsBuilder(),
      TargetPlatform.windows: MvPageTransitionsBuilder(),
      TargetPlatform.macOS: MvPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    // Mobile-sized, light type: DM Sans at ~90% of the Material defaults.
    textTheme: GoogleFonts.dmSansTextTheme(
      Typography.englishLike2021.apply(fontSizeFactor: .92),
    ).apply(bodyColor: text, displayColor: text),
    appBarTheme: AppBarTheme(
      backgroundColor: headerBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: text),
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: text,
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: surface),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(MvRadius.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.sheet)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.card)),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MvRadius.card),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? surface2 : surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: GoogleFonts.dmSans(fontSize: 13, color: muted, fontWeight: FontWeight.w400),
      labelStyle: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
      floatingLabelStyle: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.accentDeep,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: BorderSide(color: border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: BorderSide(color: border.withValues(alpha: .6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: BorderSide(color: palette.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: const BorderSide(color: MvColors.errorText),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MvRadius.field),
        borderSide: const BorderSide(color: MvColors.errorText, width: 1.6),
      ),
    ),
    // Primary CTAs ("Add to Cart", "Shop Now", "Checkout") are brand teal.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.button)),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.button)),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.button)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accentDeep),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.accentDeep,
      unselectedLabelColor: muted,
      indicatorColor: palette.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: text,
      contentTextStyle: GoogleFonts.dmSans(color: page),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MvRadius.field)),
    ),
    tooltipTheme: const TooltipThemeData(),
    // Active category filters fill with the brand teal, as pills.
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surface2,
      selectedColor: palette.accent,
      checkmarkColor: Colors.white,
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: text),
      secondaryLabelStyle: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(color: border),
    ),
    // Count badges pinned to top-bar icons are brand teal, not the M3 error red.
    badgeTheme: BadgeThemeData(
      backgroundColor: palette.accent,
      textColor: Colors.white,
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

extension MvHeadingX on BuildContext {
  TextStyle get mvH1 => GoogleFonts.manrope(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: Theme.of(this).colorScheme.onSurface,
  );
  TextStyle get mvEyebrow => GoogleFonts.dmSans(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: mv.accentDeep,
  );
}
