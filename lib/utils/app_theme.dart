import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF0277BD);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        appBarTheme: const AppBarTheme(centerTitle: false),
      );
}
