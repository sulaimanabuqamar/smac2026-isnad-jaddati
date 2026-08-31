import 'package:flutter/material.dart';

/// The app's colours and type.
///
/// Chosen to feel like a room rather than a tool: warm paper, ink brown,
/// a muted olive. Nothing saturated, nothing that flashes. Someone is
/// sitting with their grandmother while this is on screen, and the app
/// should stay out of the way of that.
class JaddatiTheme {
  const JaddatiTheme._();

  // Warm neutrals. `paper` is the page, `linen` is anything raised off it.
  static const paper = Color(0xFFFBF6EF);
  static const linen = Color(0xFFF3E9DA);
  static const ink = Color(0xFF33291F);
  static const inkSoft = Color(0xFF6B5D4D);

  // One accent, used sparingly: the record button, the FAB, a selected row.
  static const clay = Color(0xFF9C5B3C);
  static const olive = Color(0xFF6E7A5A);

  /// Type is a step larger than Material's defaults throughout.
  ///
  /// The person reading this screen may be twenty or may be eighty, and the
  /// phone is often at arm's length on a table between them. Bigger text
  /// costs us nothing and is the cheapest accessibility win available.
  static const _bodySize = 17.0;
  static const _arabicSize = 21.0;

  /// Arabic renders visually smaller than Latin at the same point size, and
  /// needs more line height for its diacritics. This is not decoration — set
  /// the same size for both and the Arabic looks like a footnote to the
  /// English, which is the wrong relationship between them.
  static const arabic = TextStyle(
    fontSize: _arabicSize,
    height: 1.8,
    color: ink,
  );

  static const arabicLarge = TextStyle(
    fontSize: 26,
    height: 1.7,
    color: ink,
    fontWeight: FontWeight.w500,
  );

  /// English shown beneath Arabic is a translation, not a heading. It is
  /// deliberately quieter than the Arabic it sits under.
  static const english = TextStyle(
    fontSize: _bodySize,
    height: 1.4,
    color: inkSoft,
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: clay,
      brightness: Brightness.light,
    ).copyWith(
      surface: paper,
      primary: clay,
      secondary: olive,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: linen,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: _bodySize, height: 1.5, color: ink),
        bodyMedium: TextStyle(fontSize: _bodySize, height: 1.5, color: ink),
        titleMedium: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: linen,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: clay,
        foregroundColor: Colors.white,
      ),
    );
  }
}
