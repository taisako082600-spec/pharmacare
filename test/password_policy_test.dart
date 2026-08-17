import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacist_app/services/password_policy.dart';

/// パスワード要件のテスト。
/// 根拠は「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編 14.1.1
/// （二要素認証を採用していない場合は13桁以上、英数字混在）。
void main() {
  group('validatePassword', () {
    test('13文字以上・英数字混在なら通る', () {
      expect(validatePassword('Kaigo2026Shien'), isNull);
      expect(validatePassword('yakuzaishi1234'), isNull);
    });

    test('12文字以下は桁数不足で弾く', () {
      expect(validatePassword('Kaigo2026Sh'), isNotNull);
      // 二要素認証ありなら許容される8桁も、未導入の現状では弾かれる
      expect(validatePassword('Kaigo123'), isNotNull);
    });

    test('境界値: ちょうど13文字は通り、12文字は通らない', () {
      expect('Kaigo20261234'.length, minLengthWithoutMfa);
      expect(validatePassword('Kaigo20261234'), isNull);
      expect('Kaigo2026123'.length, minLengthWithoutMfa - 1);
      expect(validatePassword('Kaigo2026123'), isNotNull);
    });

    test('英字だけ・数字だけは弾く', () {
      expect(validatePassword('abcdefghijklmn'), isNotNull);
      expect(validatePassword('12345678901234'), isNotNull);
    });

    test('推測されやすい文字列を含むものは弾く', () {
      // 桁数と英数字混在の条件自体は満たしていても弾かれること
      expect(validatePassword('mypassword123456'), isNotNull);
      expect(validatePassword('pharmacare12345'), isNotNull);
      expect(validatePassword('Qwerty123456789'), isNotNull);
    });

    test('大文字小文字を変えても推測されやすい判定は回避できない', () {
      expect(validatePassword('MyPassWord123456'), isNotNull);
    });

    test('同じ文字の繰り返しだけのものは弾く', () {
      expect(validatePassword('aaaaaaaaaaaaaaa'), isNotNull);
    });

    test('空文字は弾く', () {
      expect(validatePassword(''), isNotNull);
    });
  });
}
