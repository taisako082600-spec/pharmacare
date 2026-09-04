import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/user_model.dart';
import '../services/mfa_service.dart';
import 'main_shell.dart';
import 'mfa_screens.dart' show showReauthDialog;

/// 二要素認証の登録が済むまでアプリ本体に入れない画面。
///
/// `mfaRequired` が立っているアカウント（＝新しく作られた職員アカウント）だけが
/// ここを通る。既存アカウントはフラグが無いので影響を受けない。
///
/// Firebase は「未登録の利用者でも、正しいパスワードならサインインは成功する」
/// 仕様で、必須化はアプリ側の責任だと公式ドキュメントに明記されている。
/// そのため、この画面が実質的な強制ポイントになる。
///
/// 手順は2段階:
///   1. メールアドレスの確認 — Firebase は未確認アドレスへの二要素認証の登録を
///      拒否する。本人でないアドレスに紐づけて、本当の持ち主を締め出す事故を
///      防ぐための仕様。
///   2. 認証アプリの登録 — 表示したキーを登録し、6桁を入力して確定する。
class MfaRequiredScreen extends StatefulWidget {
  final UserModel user;
  const MfaRequiredScreen({super.key, required this.user});

  @override
  State<MfaRequiredScreen> createState() => _MfaRequiredScreenState();
}

class _MfaRequiredScreenState extends State<MfaRequiredScreen> {
  final _codeController = TextEditingController();

  bool _busy = true;
  bool _emailVerified = false;
  TotpEnrollmentStart? _start;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// メール確認の状況を取り直し、確認済みなら登録用のキーを用意する。
  Future<void> _refresh() async {
    setState(() { _busy = true; _error = null; });
    try {
      // 既に登録済みで戻ってきた場合(再ログイン等)はそのまま通す
      if (await MfaService().isEnrolled()) {
        _enter();
        return;
      }

      final verified = await MfaService().isEmailVerified();
      if (!mounted) return;

      if (verified && _start == null) {
        _start = await _startEnrollmentWithReauth();
        if (_start == null) {
          if (!mounted) return;
          setState(() { _emailVerified = verified; _busy = false; });
          return;
        }
      }
      if (!mounted) return;
      setState(() { _emailVerified = verified; _busy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _readable(e); _busy = false; });
    }
  }

  /// 登録用のキーを取得する。直近ログインが古いと Firebase に拒まれるので、
  /// その場合はパスワードを聞き直してから一度だけ再試行する。
  Future<TotpEnrollmentStart?> _startEnrollmentWithReauth() async {
    try {
      return await MfaService().startEnrollment(accountName: widget.user.email);
    } catch (e) {
      if (!MfaService.isRecentLoginRequired(e) || !mounted) rethrow;

      final password = await showReauthDialog(context);
      if (password == null || password.isEmpty) {
        if (!mounted) return null;
        setState(() => _error = '本人確認が済むまで設定を続けられません');
        return null;
      }
      await MfaService().reauthenticate(password);
      return MfaService().startEnrollment(accountName: widget.user.email);
    }
  }

  Future<void> _resendVerification() async {
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await MfaService().sendEmailVerification();
      if (!mounted) return;
      setState(() { _notice = '確認メールを送りました。受信箱をご確認ください'; _busy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _readable(e); _busy = false; });
    }
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '認証アプリに表示されている6桁を入力してください');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await MfaService().completeEnrollment(
        secret: _start!.secret,
        oneTimePassword: code,
      );
      _enter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '6桁が一致しませんでした。時間が経つと変わるので、表示中の数字を入れ直してください';
        _busy = false;
      });
    }
  }

  void _enter() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainShell(user: widget.user)),
    );
  }

  /// 中断したい場合の逃げ道。アカウントは残るので、次回ログイン時にまたここへ来る。
  Future<void> _cancel() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String _readable(Object e) {
    if (MfaService.isUnverifiedEmail(e)) {
      return 'メールアドレスの確認が済んでいません。受信箱のリンクを開いてから、'
          '「確認しました」を押してください';
    }
    if (e is StateError) return 'ログインし直してください';
    // 原因の切り分けができるよう、コードだけは残す
    return '設定を進められませんでした（${MfaService.errorCode(e)}）。'
        '通信状況をご確認のうえ、もう一度お試しください';
  }

  @override
  Widget build(BuildContext context) {
    // 戻るボタンやスワイプで抜けられないようにする。
    // 抜け道は「中断してログアウト」だけにして、未登録のままアプリに入る道を塞ぐ。
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('二要素認証の設定'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('中断', style: TextStyle(color: Colors.white)),
            ),
          ],
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'この先へ進むには設定が必要です',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'このアプリは患者さんの医療情報を扱います。パスワードが漏れても、'
                  'あなた以外がログインできないようにするための設定です。\n'
                  '設定すると、次回から6桁の確認が入ります。',
                  style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.6),
                ),
                const SizedBox(height: 24),

                _step(1, 'メールアドレスの確認', _emailVerified),
                if (!_emailVerified) _emailStep(),

                const SizedBox(height: 16),
                _step(2, '認証アプリの登録', false),
                if (_emailVerified) _totpStep(),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 16),
                  Text(_notice!, style: const TextStyle(color: Color(0xFF2E7D4F), fontSize: 13)),
                ],
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(int n, String label, bool done) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done ? const Color(0xFF2E7D4F) : const Color(0xFF1976D2),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('$n', style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _emailStep() {
    return Padding(
      padding: const EdgeInsets.only(left: 38, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.user.email} 宛に確認メールを送りました。\n'
            'メール内のリンクを開いてから、下のボタンを押してください。',
            style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('確認しました'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _busy ? null : _resendVerification,
                child: const Text('メールを再送'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totpStep() {
    final key = _start?.manualEntryKey;
    final qrUrl = _start?.qrCodeUrl;

    return Padding(
      padding: const EdgeInsets.only(left: 38, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 何のためのアプリなのかを先に説明する。
          // 「認証アプリ」という言葉だけでは、初めての人には何も伝わらない。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'スマートフォンに「認証アプリ」を入れます',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '30秒ごとに変わる6桁の数字を表示するだけの、無料のアプリです。\n'
                  'このアプリと連携させると、ログインのときにその6桁が必要になります。\n'
                  'スマホを持っているあなただけがログインできる、という仕組みです。',
                  style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.7),
                ),
                SizedBox(height: 10),
                Text(
                  'お使いのスマホのアプリストアで、次のいずれかを入れてください。',
                  style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
                ),
                SizedBox(height: 4),
                Text(
                  '・Google Authenticator\n・Microsoft Authenticator',
                  style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.7),
                ),
                SizedBox(height: 8),
                Text(
                  'iPhoneをお使いなら、標準の「パスワード」アプリでも代用できます。',
                  style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'アプリを入れたら、中の「＋」から読み取り画面を開き、'
            '下のQRコードを写してください。',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.7),
          ),
          const SizedBox(height: 12),

          // QRコードでの登録を主にする。手入力のキーはカメラが使えないときの控え。
          if (qrUrl != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFDCE6E4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrUrl,
                  version: QrVersions.auto,
                  size: 190,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // カメラで読めない場合(この端末がスマホ本体である等)の代替。
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'QRコードが読み取れないとき',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'この画面をスマホで見ている場合など、カメラで写せないときは、'
                  '認証アプリの「キーを手動で入力」を選び、下の文字列を貼り付けてください。',
                  style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
                ),
              ),
              const SizedBox(height: 10),
              if (key != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          key,
                          style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 14, letterSpacing: 1.2),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'コピー',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: key));
                          if (!mounted) return;
                          setState(() => _notice = 'キーをコピーしました');
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          const Text(
            '連携できると、認証アプリに6桁の数字が表示されます。'
            'その数字を下に入れてください。',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.7),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: '認証アプリに表示された6桁',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('設定を完了してアプリを始める'),
            ),
          ),
        ],
      ),
    );
  }
}
