import 'package:flutter/material.dart';

/// アプリ全体の見た目を1か所にまとめたもの。
///
/// 方針:
///   - 触るのは色・角丸・影・文字だけ。レイアウトや動作には一切関与しない。
///     凝ったアニメーションやすりガラス表現は入れない — 施設の共用端末は非力な
///     ことが多く、描画負荷とブラウザ差が表示崩れの温床になるため。
///   - 背景は明るいまま。介護の現場は昼間の明るい居室で使うので、
///     全面ダークにすると視認性が落ちる。締まって見せたいのは上下の枠(ヘッダー・
///     ナビ)なので、そこだけ濃紺にする。
///   - ロールごとの色は「今どの立場でログインしているか」を示す情報なので残す。
///     ただし彩度を落として、画面全体を支配しないようにする。
class AppTheme {
  // ── 基調 ──────────────────────────────────────────────
  /// ヘッダー・ナビゲーションに使う濃紺。原色の青緑より落ち着いて見える。
  static const ink = Color(0xFF14213D);
  static const inkSoft = Color(0xFF25334F);

  /// 主アクセント。青緑系にすると「医療らしさ」と現代的な印象が両立する。
  static const accent = Color(0xFF14A4A0);
  static const accentDeep = Color(0xFF0E7C79);

  /// 背景と面。真っ白ではなく僅かに冷たい灰を敷くと、カードの輪郭が出る。
  static const canvas = Color(0xFFF6F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E8EF);

  static const textMain = Color(0xFF16202E);
  static const textSub = Color(0xFF5C6B7F);

  /// 意味を持つ色。トリアージの信号などに使うので、むやみに変えないこと。
  static const ok = Color(0xFF2E7D4F);
  static const warn = Color(0xFFC98A22);
  static const danger = Color(0xFFB23A2F);

  // ── ロール色 ──────────────────────────────────────────
  /// 立場の識別に使う。彩度を落とし、濃紺の基調と喧嘩しない範囲に収めてある。
  static Color roleColor(String role) {
    switch (role) {
      case '薬剤師':
        return const Color(0xFF2C6E9B);
      case '介護士':
        return const Color(0xFF2F7D62);
      case '看護師':
        return const Color(0xFFA8484A);
      case '家族':
        return const Color(0xFF6B5B95);
      default:
        return accentDeep;
    }
  }

  static const _radius = 14.0;

  static ThemeData build() {
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accentDeep,
      secondary: accent,
      surface: surface,
      error: danger,
      onSurface: textMain,
    );

    return ThemeData(
      colorScheme: base,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,

      // 文字。字面を少し詰めると締まって見える。
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: textMain),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: textMain),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: textMain),
        bodyLarge: TextStyle(height: 1.6, color: textMain),
        bodyMedium: TextStyle(height: 1.6, color: textMain),
        bodySmall: TextStyle(height: 1.5, color: textSub),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: line),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentDeep,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentDeep,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
        labelStyle: const TextStyle(color: textSub),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        titleTextStyle: const TextStyle(
          color: textMain, fontSize: 17, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: textMain, fontSize: 14, height: 1.6),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: ink,
        selectedItemColor: Colors.white,
        unselectedItemColor: Color(0xFF8FA0BA),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: canvas,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: const TextStyle(fontSize: 12, color: textMain),
      ),

      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: inkSoft,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: textSub,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textMain),
        subtitleTextStyle: TextStyle(fontSize: 13, color: textSub),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
