import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double page = 16;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 20;
}

class AppTheme {
  static const Color primaryPurple = Color(0xFF5B3B8C);
  static const Color primaryPurpleLight = Color(0xFF8B5CF6);
  static const Color primaryPurpleGlow = Color(0xFF9F75FF);
  static const Color deepPurple = Color(0xFF3B1D66);
  static const Color imperialGold = Color(0xFFD4AF37);
  static const Color amberGold = Color(0xFFF59E0B);
  static const Color emeraldGreen = Color(0xFF0D5C52);

  static const Color statusSuccess = Color(0xFF2F9E63);
  static const Color statusWarning = Color(0xFFC26705);
  static const Color statusDanger = Color(0xFFDC2626);
  static const Color statusInfo = Color(0xFF3B82F6);

  static const Color darkBg = Color(0xFF0E0F17);
  static const Color darkSurface = Color(0xFF161524);
  static const Color darkSurfaceVariant = Color(0xFF1F1D33);
  static const Color darkBorder = Color(0xFF2E2B48);
  static const Color darkTextPrimary = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);

  static const Color lightBg = Color(0xFFF7F5FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF0ECF7);
  static const Color lightBorder = Color(0xFFE2DCED);
  static const Color lightTextPrimary = Color(0xFF181126);
  static const Color lightTextSecondary = Color(0xFF5D6572);

  static const List<Color> brandGradientColors = [
    Color(0xFF2A1545),
    Color(0xFF4A2B78),
    Color(0xFF6B3FA0),
  ];
  static const LinearGradient brandGradient = LinearGradient(
    colors: brandGradientColors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static TextTheme _buildTextTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      headlineLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary, height: 1.2),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary, height: 1.25),
      headlineSmall: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: textPrimary, height: 1.3),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary, height: 1.3),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary, height: 1.3),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary, height: 1.35),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary, height: 1.45),
      bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: textPrimary, height: 1.45),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: textSecondary, height: 1.4),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary),
      labelSmall: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: textSecondary, letterSpacing: 0.4),
    );
  }

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: primaryPurpleGlow,
      onPrimary: Colors.white,
      primaryContainer: deepPurple,
      onPrimaryContainer: Color(0xFFE9D5FF),
      secondary: amberGold,
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF452B00),
      onSecondaryContainer: Color(0xFFFFDDB3),
      tertiary: emeraldGreen,
      error: statusDanger,
      surface: darkSurface,
      onSurface: darkTextPrimary,
      onSurfaceVariant: darkTextSecondary,
      surfaceContainerHighest: darkSurfaceVariant,
      outline: darkBorder,
      outlineVariant: Color(0xFF383556),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBg,
      canvasColor: darkBg,
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(darkTextPrimary, darkTextSecondary),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryPurpleGlow,
        unselectedLabelColor: darkTextSecondary,
        indicatorColor: primaryPurpleGlow,
        dividerColor: darkBorder,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: darkSurfaceVariant,
        side: BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        labelStyle: TextStyle(color: darkTextPrimary, fontSize: 12),
        secondaryLabelStyle: TextStyle(color: darkTextPrimary, fontSize: 12),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(color: darkTextPrimary, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
        contentTextStyle: const TextStyle(color: darkTextPrimary, fontSize: 14, height: 1.45),
        barrierColor: Colors.black54,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkSurfaceVariant,
        contentTextStyle: const TextStyle(color: darkTextPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: deepPurple, borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 350),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: darkTextSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryPurpleGlow,
        linearTrackColor: darkSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryPurpleGlow, width: 1.5),
        ),
        labelStyle: const TextStyle(color: darkTextSecondary),
        hintStyle: const TextStyle(color: darkTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurpleGlow,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryPurpleGlow,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurpleGlow,
          side: const BorderSide(color: primaryPurpleGlow),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryPurpleGlow,
        inactiveTrackColor: darkBorder,
        thumbColor: amberGold,
        overlayColor: amberGold.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
    );
  }

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: primaryPurple,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEADDFF),
      onPrimaryContainer: deepPurple,
      secondary: imperialGold,
      onSecondary: Color(0xFF3D2E00),
      secondaryContainer: Color(0xFFFFF3D6),
      onSecondaryContainer: Color(0xFF5A4300),
      tertiary: emeraldGreen,
      error: statusDanger,
      surface: lightSurface,
      onSurface: lightTextPrimary,
      onSurfaceVariant: lightTextSecondary,
      surfaceContainerHighest: lightSurfaceVariant,
      outline: lightBorder,
      outlineVariant: Color(0xFFD3CBE0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBg,
      canvasColor: lightBg,
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(lightTextPrimary, lightTextSecondary),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryPurple,
        unselectedLabelColor: lightTextSecondary,
        indicatorColor: primaryPurple,
        dividerColor: lightBorder,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: lightSurfaceVariant,
        side: BorderSide(color: lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        labelStyle: TextStyle(color: lightTextPrimary, fontSize: 12),
        secondaryLabelStyle: TextStyle(color: lightTextPrimary, fontSize: 12),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(color: lightTextPrimary, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
        contentTextStyle: const TextStyle(color: lightTextPrimary, fontSize: 14, height: 1.45),
        barrierColor: Colors.black26,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: deepPurple,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: deepPurple, borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 350),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: lightTextSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryPurple,
        linearTrackColor: lightSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryPurple, width: 1.5),
        ),
        labelStyle: const TextStyle(color: lightTextSecondary),
        hintStyle: const TextStyle(color: lightTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurple,
          side: const BorderSide(color: primaryPurple),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryPurple,
        inactiveTrackColor: lightBorder,
        thumbColor: primaryPurple,
        overlayColor: primaryPurple.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
    );
  }
}
