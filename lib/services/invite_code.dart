import 'dart:math';

/// 招待コードの生成・正規化・表示形式。
///
/// もとは6桁の数字だった。乱数は `Random.secure()` を使っていて質は問題なかったが、
/// **空間が 10^6 しかなく総当たりが現実的**だった。招待コードは
/// 「持っている＝その施設(あるいはその入居者)に参加してよい」という
/// 権限そのものなので、当てられるということは他人の施設に入れるということになる。
/// firestore.rules も最終的にこのコードの実在で判定している。
///
/// 文字種を増やして 8 文字にしたことで 31^8 ≒ 8.5×10^11 になり、
/// 10^6 から約85万倍になる。
///
/// 紛らわしい文字は除いてある。介護施設では紙に書いて渡したり口頭で伝えたりするため、
/// `0/O` `1/I/L` を含めると入力ミスが増え、「コードが違う」という問い合わせに化ける。
class InviteCode {
  /// I・L・O・0・1 を除いた31文字。
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// 新しく発行するコードの長さ。
  static const length = 8;

  /// 旧形式(6桁の数字)。既に配ってあるコードを無効にしないために受け付ける。
  static const legacyLength = 6;

  static final _random = Random.secure();

  /// 新しいコードを作る。保存・照合に使うのはこの文字列そのもの
  /// (firestore.rules が invite_codes のドキュメントIDとして get() する)。
  static String generate() =>
      List.generate(length, (_) => alphabet[_random.nextInt(alphabet.length)]).join();

  /// 入力されたものを保存形式に揃える。
  ///
  /// 表示は `ABCD-EFGH` と区切るので、利用者はハイフンごと写しがちで、
  /// スマートフォンだと小文字や全角空白も混ざる。ここで吸収する。
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.trim().toUpperCase().runes) {
      final ch = String.fromCharCode(rune);
      // 全角英数字を半角に寄せる
      if (rune >= 0xFF21 && rune <= 0xFF3A) {
        buffer.write(String.fromCharCode(rune - 0xFF21 + 0x41)); // Ａ-Ｚ
      } else if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.write(String.fromCharCode(rune - 0xFF10 + 0x30)); // ０-９
      } else if (RegExp(r'[A-Z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      }
      // ハイフン・空白・その他は捨てる
    }
    return buffer.toString();
  }

  /// 照合しにいく価値がある形か。通信する前に弾くための軽い判定で、
  /// これを通ったからといって有効なコードとは限らない。
  static bool isPlausible(String normalized) {
    if (normalized.length == legacyLength) {
      return RegExp(r'^[0-9]+$').hasMatch(normalized);
    }
    if (normalized.length != length) return false;
    return normalized.split('').every(alphabet.contains);
  }

  /// 画面に出すときの形。8文字は4文字ずつ区切ると写し間違いが減る。
  /// 旧形式(6桁)はそのまま返す。
  static String formatForDisplay(String code) {
    if (code.length != length) return code;
    return '${code.substring(0, 4)}-${code.substring(4)}';
  }

  /// 入力欄の最大文字数。ハイフン込みで打たれても切れないようにする。
  static const inputMaxLength = length + 1;
}
