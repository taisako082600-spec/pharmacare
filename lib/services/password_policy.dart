/// パスワードの強度要件。
///
/// 根拠: 「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編
/// 14.1.1 利用者の識別・認証
///
///   > 二要素認証を採用していることを前提とした場合、パスワードの桁数は 8 桁
///   > （PIN であれば 4 桁）以上が求められる。この際、英数字の混在（大文字小文字は
///   > 問わない）を求める。ただし、二要素認証を採用していない場合には 13 桁以上とすること。
///
/// 本アプリは現時点で二要素認証を実装していないため、**13桁以上**が必要になる。
/// 二要素認証を導入した際は [minLengthWithoutMfa] ではなく 8 桁へ緩和してよい。
///
/// また同ガイドラインは「パスワードの定期的な変更は不要」としているため、
/// 有効期限による強制変更は設けない。
library;

/// 二要素認証を採用していない場合に必要な最小桁数。
const int minLengthWithoutMfa = 13;

/// 二要素認証を採用した場合に必要な最小桁数（現在は未使用。導入時に切り替える）。
const int minLengthWithMfa = 8;

/// よくある推測されやすいパターン。
/// ガイドライン 14 遵守事項⑥(1)「類推されやすいパスワードを使用させないよう、
/// 設定可能なパスワードに制限を設けること」への対応。
const List<String> _commonWeakPatterns = [
  'password',
  'passw0rd',
  '123456',
  'qwerty',
  'abc123',
  'admin',
  'letmein',
  'welcome',
  'pharmacare',
  'pharmacist',
];

/// パスワードを検証し、問題があれば利用者向けの日本語メッセージを返す。
/// 問題なければ null を返す。
String? validatePassword(String password) {
  if (password.length < minLengthWithoutMfa) {
    return 'パスワードは$minLengthWithoutMfa文字以上で設定してください'
        '（医療情報を扱うため、国のガイドラインで定められています）';
  }

  final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
  final hasDigit = RegExp(r'[0-9]').hasMatch(password);
  if (!hasLetter || !hasDigit) {
    return 'パスワードには英字と数字の両方を含めてください';
  }

  final lower = password.toLowerCase();
  for (final weak in _commonWeakPatterns) {
    if (lower.contains(weak)) {
      return '推測されやすい文字列（$weak）が含まれています。別のパスワードにしてください';
    }
  }

  // 同一文字の連続や単純な連番だけで桁数を稼いだものを弾く
  if (RegExp(r'^(.)\1+$').hasMatch(password)) {
    return '同じ文字の繰り返しだけのパスワードは使用できません';
  }

  return null;
}
