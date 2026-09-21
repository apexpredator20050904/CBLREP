import 'package:flutter/material.dart';

/// CBLREP design system — polished dark-forest + amber brand theme.
///
/// Palette:
/// - Deep forest backgrounds: #1B382B (browse), #2D4D36 (dashboard/exchanges/map)
/// - Dialog green: #1E3A27, card field green: #2E5339
/// - Neutral card grey: #CCCCCC, dark card green: #234735
/// - Action orange: #E58824, deep amber: #D9822B, avatar amber: #D97706
/// - Seed/brand green: #1B3B22
class CblrepColors {
  static const deepForest = Color(0xFF1B382B);
  static const surfaceGreen = Color(0xFF2D4D36);
  static const dialogGreen = Color(0xFF1E3A27);
  static const fieldGreen = Color(0xFF2E5339);
  static const cardGrey = Color(0xFFCCCCCC);
  static const darkCardGreen = Color(0xFF234735);
  static const actionOrange = Color(0xFFE58824);
  static const deepAmber = Color(0xFFD9822B);
  static const avatarAmber = Color(0xFFD97706);
  static const brandGreen = Color(0xFF1B3B22);
  static const completedBrown = Color(0xFF6E2800);

  /// Extended polish tokens.
  static const inkGreen = Color(0xFF10241A);
  static const softCream = Color(0xFFF5EFE2);
  static const goldHighlight = Color(0xFFF2C25C);
  static const successGreen = Color(0xFF3E9B5F);
  static const dangerRed = Color(0xFFD64545);
}

/// Reusable branded logo avatar — official CBLREP logo from the portal.
class CblrepLogo extends StatelessWidget {
  final double radius;
  final double padding;
  const CblrepLogo({super.key, this.radius = 20, this.padding = 2});

  @override
  Widget build(BuildContext context) {
    // Decode the 1408×768 progressive JPEG at (twice) the displayed size, not
    // at full source resolution — every instance on every screen otherwise
    // pays a multi-millisecond decode, which reads as jank on emulators and
    // low-end phones. RepaintBoundary caches the raster per instance.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: ClipOval(
            child: Image.asset(
              'assets/cblrep_logo.jpg',
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              cacheWidth: ((radius * 2 + padding * 2) * dpr).round(),
              errorBuilder: (_, _, _) => const Icon(Icons.eco, color: CblrepColors.brandGreen),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient header card used on dashboard / home feed.
class CblrepGradientHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CblrepGradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E5339), Color(0xFF1B382B)],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class CblrepTheme {
  static ThemeData _base({required Brightness brightness, required Color scaffold}) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffold,
      colorScheme: ColorScheme.fromSeed(
        seedColor: CblrepColors.brandGreen,
        brightness: brightness,
        primary: dark ? CblrepColors.actionOrange : CblrepColors.brandGreen,
        secondary: CblrepColors.actionOrange,
        surface: dark ? scaffold : Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: dark ? Colors.white : CblrepColors.brandGreen,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: dark ? Colors.white : CblrepColors.brandGreen,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scaffold),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF142B1D) : Colors.white,
        indicatorColor: CblrepColors.actionOrange,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: dark ? Colors.white70 : Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CblrepColors.cardGrey,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CblrepColors.actionOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      // Dark mode used to fill inputs pure white while text/labels stayed
      // white, making dropdown options and typed text invisible. Fields now use
      // brand field-green with light text in dark, cream with dark text in light.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? CblrepColors.fieldGreen : const Color(0xFFF4F1E8),
        hintStyle: TextStyle(color: dark ? Colors.white60 : Colors.black45, fontSize: 13),
        labelStyle: TextStyle(color: dark ? Colors.white70 : Colors.black54, fontSize: 12),
        floatingLabelStyle: TextStyle(
          color: dark ? CblrepColors.goldHighlight : CblrepColors.brandGreen,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        prefixIconColor: dark ? Colors.white70 : Colors.black45,
        suffixIconColor: dark ? Colors.white70 : Colors.black45,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: dark ? Colors.white24 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CblrepColors.actionOrange, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CblrepColors.dangerRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: CblrepColors.dangerRed, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? CblrepColors.cardGrey : Colors.white,
        elevation: dark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // Branded overlays so dropdown menus, dialogs and progress spinners stay
      // readable and on-brand in both light and dark modes.
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(dark ? CblrepColors.darkCardGreen : Colors.white),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? CblrepColors.darkCardGreen : Colors.white,
        textStyle: TextStyle(color: dark ? Colors.white : Colors.black87, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? CblrepColors.dialogGreen : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: TextStyle(
          color: dark ? Colors.white : CblrepColors.brandGreen,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(color: dark ? Colors.white70 : Colors.black87, fontSize: 13),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: CblrepColors.actionOrange),
      dividerTheme: DividerThemeData(color: dark ? Colors.white12 : Colors.black12),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFF2E5339),
        labelStyle: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: StadiumBorder(),
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(color: dark ? Colors.white : CblrepColors.brandGreen, fontWeight: FontWeight.bold, fontSize: 20),
        titleMedium: TextStyle(color: dark ? Colors.white : CblrepColors.brandGreen, fontWeight: FontWeight.bold, fontSize: 14),
        // Explicit input text colour so typed text / dropdown selections are
        // never rendered white-on-white.
        bodyLarge: TextStyle(color: dark ? Colors.white : Colors.black87, fontSize: 14),
        bodyMedium: TextStyle(color: dark ? Colors.white : Colors.black87, fontSize: 13),
        bodySmall: TextStyle(color: dark ? Colors.white70 : Colors.black54, fontSize: 11),
        labelLarge: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  static ThemeData get darkGreen => _base(brightness: Brightness.dark, scaffold: CblrepColors.surfaceGreen);

  static ThemeData get lightCream => _base(brightness: Brightness.light, scaffold: const Color(0xFFF5EFE2));

  /// Dark-field decoration used inside dialogs / dark sheets.
  static InputDecoration darkField(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
        filled: true,
        fillColor: CblrepColors.fieldGreen,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}
