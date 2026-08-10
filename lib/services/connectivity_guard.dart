import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// 患者の臨床データ(バイタル・服薬記録・服薬ログ・患者情報等)を編集する前に、
/// オンライン状態を確認するためのガード。
///
/// Firestoreはオフラインでも書き込みを画面上は即座に反映する(ローカルキャッシュに
/// 先に適用されるため)が、実際にはサーバーに届いておらずローカルにキューされているだけ。
/// これにより「保存できたと思っていたら実は届いていない」「複数スタッフの編集が
/// 気づかないまま競合し、後から同期した方が無言で上書きする」というリスクがある
/// (2026-07-18の検討結果)。臨床データについては、オフライン時はそもそも書き込みを
/// 行わせずエラー表示して中断する方針とした。チャット・カレンダー等は対象外
/// (競合してもヒヤリハットに直結しないため、Firestoreの標準キューイングのままでよい)。
class ConnectivityGuard {
  /// オンラインであれば true を返す。オフラインなら赤色SnackBarでエラーを表示し false を返す。
  /// 呼び出し側は保存処理の先頭で
  /// `if (!await ConnectivityGuard.ensureOnline(context)) return;`
  /// のように使う。
  static Future<bool> ensureOnline(BuildContext context) async {
    final results = await Connectivity().checkConnectivity();
    final isOnline = !results.contains(ConnectivityResult.none);

    if (!isOnline && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('オフラインのため保存できません。接続を確認してから再度お試しください。'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
    return isOnline;
  }
}
