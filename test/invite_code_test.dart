import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacist_app/services/invite_code.dart';

void main() {
  group('generate', () {
    test('決められた長さと文字種で作られる', () {
      for (var i = 0; i < 200; i++) {
        final code = InviteCode.generate();
        expect(code.length, InviteCode.length);
        expect(code.split('').every(InviteCode.alphabet.contains), isTrue,
            reason: '許可外の文字が混ざっている: $code');
      }
    });

    test('紛らわしい文字は出てこない', () {
      // 紙に書いて渡す運用があるので、0/O と 1/I/L の取り違えを構造的に防ぐ
      for (var i = 0; i < 500; i++) {
        expect(InviteCode.generate(), isNot(matches(RegExp(r'[ILO01]'))));
      }
    });

    test('毎回違う値が出る', () {
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        seen.add(InviteCode.generate());
      }
      expect(seen.length, 300, reason: '重複が出るのは乱数の使い方が間違っている');
    });
  });

  group('normalize', () {
    test('小文字・ハイフン・空白を吸収する', () {
      expect(InviteCode.normalize(' abcd-efgh '), 'ABCDEFGH');
      expect(InviteCode.normalize('ABCD EFGH'), 'ABCDEFGH');
    });

    test('全角で入力されても通る', () {
      // スマートフォンの日本語入力だと全角のまま確定されることがある
      expect(InviteCode.normalize('ＡＢＣＤ－ＥＦＧＨ'), 'ABCDEFGH');
      expect(InviteCode.normalize('９４１３６９'), '941369');
    });

    test('記号だけなら空になる', () {
      expect(InviteCode.normalize('---'), '');
    });
  });

  group('isPlausible', () {
    test('新形式を受け付ける', () {
      expect(InviteCode.isPlausible(InviteCode.generate()), isTrue);
    });

    test('旧形式の6桁数字も受け付ける', () {
      // 既に配ってあるコードを無効にしないため
      expect(InviteCode.isPlausible('941369'), isTrue);
    });

    test('長さ違い・文字種違いは弾く', () {
      expect(InviteCode.isPlausible('ABCDEFG'), isFalse); // 7文字
      expect(InviteCode.isPlausible('ABCDEFGI'), isFalse); // 除外文字
      expect(InviteCode.isPlausible('12345'), isFalse);
      expect(InviteCode.isPlausible(''), isFalse);
    });

    test('旧形式の長さで数字以外は弾く', () {
      expect(InviteCode.isPlausible('ABCDEF'), isFalse);
    });
  });

  group('formatForDisplay', () {
    test('新形式は4文字ずつ区切る', () {
      expect(InviteCode.formatForDisplay('ABCDEFGH'), 'ABCD-EFGH');
    });

    test('旧形式はそのまま', () {
      expect(InviteCode.formatForDisplay('941369'), '941369');
    });

    test('表示形を正規化すると元に戻る', () {
      final code = InviteCode.generate();
      expect(InviteCode.normalize(InviteCode.formatForDisplay(code)), code);
    });
  });
}
