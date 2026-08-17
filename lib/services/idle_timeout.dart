import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 無操作時の自動ログアウト。
///
/// 根拠: 「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編
///
///   12 遵守事項⑥
///   > 利用者が医療情報を入力・参照する端末から長時間離席する際など、正当な利用者以外の者に
///   > よる入力・参照が生じないよう対策を実施すること。
///
///   12.3.2 端末・サーバ装置等の不適切な利用等に関する対策
///   > 利用者が医療情報を入力・参照する端末から長時間離席する際に、正当な利用者以外の者による
///   > 入力・参照を防止するため、自動での画面ロックアウト等の対策を実施すること。
///
/// 介護施設では1台の端末を複数の職員で共用するのが一般的で、入居者対応のために
/// 開いたまま離席する場面が避けられない。OS側の画面ロックに任せず、アプリ側でも
/// 一定時間操作が無ければサインアウトする。
class IdleTimeout extends StatefulWidget {
  final Widget child;

  /// 無操作でサインアウトするまでの時間。
  /// 介護現場では入居者対応で数分手が離れることが普通にあるため、短すぎると
  /// 業務の妨げになる。安全性と実用性の折り合いとして15分を既定値にしている。
  final Duration timeout;

  const IdleTimeout({
    super.key,
    required this.child,
    this.timeout = const Duration(minutes: 15),
  });

  @override
  State<IdleTimeout> createState() => _IdleTimeoutState();
}

class _IdleTimeoutState extends State<IdleTimeout> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _onIdle);
  }

  Future<void> _onIdle() async {
    // 未ログインなら何もしない(ログイン画面で放置しているだけのケース)
    if (FirebaseAuth.instance.currentUser == null) return;

    await FirebaseAuth.instance.signOut();
    // サインアウトすると main.dart の AuthGate が authStateChanges を受けて
    // ログイン画面へ戻すため、ここで明示的な画面遷移は行わない。

    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '${widget.timeout.inMinutes}分間操作がなかったため、'
          '自動的にログアウトしました（患者情報保護のため）',
        ),
        backgroundColor: Colors.orange[800],
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listener はタップ・ポインタ移動を、下位ウィジェットの操作を邪魔せずに拾える。
    // behavior: HitTestBehavior.translucent により、子がタップを消費しても通知は届く。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerMove: (_) => _restart(),
      onPointerSignal: (_) => _restart(),
      child: widget.child,
    );
  }
}
