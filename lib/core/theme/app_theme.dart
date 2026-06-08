import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      textTheme: _textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.surfaceLight,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey[50],
        labelStyle: GoogleFonts.cairo(),
        hintStyle: GoogleFonts.cairo(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
      dividerTheme: DividerThemeData(color: Colors.grey[200]),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.cairo(),
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.cardDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey[850],
        labelStyle: GoogleFonts.cairo(),
        hintStyle: GoogleFonts.cairo(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surfaceDark),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final color = brightness == Brightness.light ? Colors.black87 : Colors.white;
    return TextTheme(
      displayLarge: GoogleFonts.cairo(fontSize: 32, fontWeight: FontWeight.bold, color: color),
      displayMedium: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.bold, color: color),
      displaySmall: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold, color: color),
      headlineLarge: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w700, color: color),
      headlineMedium: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w600, color: color),
      headlineSmall: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleLarge: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600, color: color),
      titleMedium: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w500, color: color),
      titleSmall: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w500, color: color),
      bodyLarge: GoogleFonts.cairo(fontSize: 16, color: color),
      bodyMedium: GoogleFonts.cairo(fontSize: 14, color: color),
      bodySmall: GoogleFonts.cairo(fontSize: 12, color: color),
      labelLarge: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      labelMedium: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w500, color: color),
      labelSmall: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w400, color: color),
    );
  }
}
