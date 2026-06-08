import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF003c8f);
  static const primaryLight = Color(0xFF5e92f3);
  static const secondary = Color(0xFF00897B);
  static const secondaryDark = Color(0xFF005b4f);
  static const secondaryLight = Color(0xFF4ebaaa);
  static const error = Color(0xFFD32F2F);
  static const warning = Color(0xFFF57C00);
  static const success = Color(0xFF388E3C);
  static const info = Color(0xFF0288D1);

  static const backgroundLight = Color(0xFFF5F5F5);
  static const backgroundDark = Color(0xFF121212);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const cardDark = Color(0xFF2C2C2C);

  static const criticalRed = Color(0xFFB71C1C);
  static const highOrange = Color(0xFFE65100);
  static const mediumYellow = Color(0xFFF9A825);
  static const lowGreen = Color(0xFF1B5E20);

  static const gradientBlue = LinearGradient(
    colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradientGreen = LinearGradient(
    colors: [Color(0xFF00897B), Color(0xFF00695C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
