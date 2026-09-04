import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/mfa_service.dart';

/// 再認証のためにパスワードを聞き直すダイアログ。
///
/// 二要素認証の登録は、直近のログインから時間が経っていると Firebase に拒否される
/// (`auth/requires-recent-login`)。乗っ取られたセッションで勝手に second factor を
/// 足されないための仕様なので、いったんパスワードで本人確認をやり直す。
///
/// 戻り値は入力されたパスワード。キャンセルなら null。
Future<String?> showReauthDialog(BuildContext context) {
  final ctrl = TextEditingController();
  var obscure = true;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('パスワードをもう一度入力してください'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ログインしてから時間が経っています。安全のため、'
              '設定を続ける前に本人確認をさせてください。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'パスワード',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setLocal(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('確認'),
          ),
        ],
      ),
    ),
  );
}

/// ログイン時に認証アプリの6桁を入力してもらうダイアログ。
/// 入力された6桁を返す。キャンセルされたら null。
Future<String?> showTotpChallengeDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('認証コードの入力'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '認証アプリに表示されている6桁の数字を入力してください。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: '6桁の認証コード',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              style: const TextStyle(fontSize: 22, letterSpacing: 8),
              textAlign: TextAlign.center,
              onSubmitted: (v) {
                if (v.length == 6) Navigator.pop(ctx, v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.length == 6) Navigator.pop(ctx, v);
            },
            child: const Text('確認'),
          ),
        ],
      );
    },
  );
}

/// 二要素認証の設定画面(登録・解除)。
///
/// ガイドライン システム運用編 14⑤ が求める二要素認証を、TOTP(認証アプリ)方式で提供する。
/// SMS方式にしていない理由は [MfaService] のコメントを参照。
class MfaSettingsScreen extends StatefulWidget {
  /// 認証アプリ側に表示される名前。誰のアカウントか分かるようメールアドレスを渡す。
  final String accountName;

  const MfaSettingsScreen({super.key, required this.accountName});

  @override
  State<MfaSettingsScreen> createState() => _MfaSettingsScreenState();
}

class _MfaSettingsScreenState extends State<MfaSettingsScreen> {
  bool _loading = true;
  bool _enrolled = false;
  bool _emailVerified = false;
  bool _verificationSent = false;
  String? _error;

  // 登録手続き中に保持する情報
  TotpEnrollmentStart? _enrollment;
  final _codeController = TextEditingController();
  bool _submitting = false;

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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      // メール確認の状態はサーバーから取り直す(確認直後でも反映されるように)
      final verified = await MfaService().isEmailVerified();
      final enrolled = await MfaService().isEnrolled();
      if (!mounted) return;
      setState(() {
        _emailVerified = verified;
        _enrolled = enrolled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '状態を取得できませんでした: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sendVerification() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await MfaService().sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _verificationSent = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 短時間に何度も送るとFirebase側で弾かれる
        _error = '確認メールを送れませんでした。しばらく待ってからもう一度お試しください';
        _submitting = false;
      });
    }
  }

  Future<void> _startEnrollment({bool retriedAfterReauth = false}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final start = await MfaService().startEnrollment(accountName: widget.accountName);
      if (!mounted) return;
      setState(() {
        _enrollment = start;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;

      // ログインから時間が経っていると Firebase が登録を拒む。
      // パスワードを聞き直して本人確認をやり直し、一度だけ自動で再試行する。
      if (MfaService.isRecentLoginRequired(e) && !retriedAfterReauth) {
        setState(() => _submitting = false);
        final password = await showReauthDialog(context);
        if (password == null || password.isEmpty) return;
        try {
          await MfaService().reauthenticate(password);
          if (!mounted) return;
          await _startEnrollment(retriedAfterReauth: true);
          return;
        } catch (_) {
          if (!mounted) return;
          setState(() => _error = 'パスワードが正しくありません。もう一度お試しください');
          return;
        }
      }

      setState(() {
        _error = MfaService.isUnverifiedEmail(e)
            ? 'メールアドレスの確認が済んでいません。確認メールのリンクを開いてから、'
                '「状態を更新」を押してください'
            : '設定を開始できませんでした。時間をおいて、もう一度お試しください'
                '${_detail(e)}';
        _submitting = false;
      });
    }
  }

  /// 失敗の手がかりを括弧書きで添える。
  /// 以前は `e.runtimeType` をそのまま出していて「（JSObject）」としか表示されず、
  /// 利用者にも問い合わせを受ける側にも何の情報にもなっていなかった。
  /// コードが取れないときは、せめてJS側のメッセージを出す。
  String _detail(Object e) {
    final code = MfaService.errorCode(e);
    if (code != e.runtimeType.toString()) return '（$code）';
    final message = MfaService.errorMessage(e);
    return message == null ? '' : '（$message）';
  }

  Future<void> _completeEnrollment() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '6桁の認証コードを入力してください');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await MfaService().completeEnrollment(
        secret: _enrollment!.secret,
        oneTimePassword: code,
      );
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _enrollment = null;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('二要素認証を設定しました。次回のログインから認証コードが必要になります'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '認証コードが正しくないか、有効期限が切れています。'
            '認証アプリに表示されている最新の6桁を入力してください';
        _submitting = false;
      });
    }
  }

  Future<void> _unenroll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二要素認証を解除しますか？'),
        content: const Text(
          '解除すると、パスワードだけでログインできるようになります。\n'
          '患者情報を扱うため、解除は推奨されません。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除する', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      final factors = await MfaService().enrolledFactors();
      for (final f in factors) {
        await MfaService().unenroll(f.uid);
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 直近のログインから時間が経つと再認証を求められる仕様のため、その旨を案内する
        _error = '解除できませんでした。一度ログアウトして入り直してから、もう一度お試しください';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('二要素認証の設定'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_enrolled)
                    _buildEnrolledView()
                  else if (!_emailVerified)
                    // メールアドレスの確認が済むまでは二要素認証を登録できない
                    _buildEmailVerificationView()
                  else if (_enrollment != null)
                    _buildEnrollmentSteps()
                  else
                    _buildIntro(),
                ],
              ),
            ),
    );
  }

  /// メールアドレス未確認のときの画面。
  /// Firebaseの仕様上、確認が済むまで二要素認証は登録できない。
  Widget _buildEmailVerificationView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_outlined, color: Colors.orange[800]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'はじめに、メールアドレスの確認が必要です',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '二要素認証は「${widget.accountName}」に紐づけて設定します。\n'
          'ご本人のアドレスであることを確認してからでないと設定できません。',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        const SizedBox(height: 20),

        if (!_verificationSent) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _sendVerification,
              icon: const Icon(Icons.send_outlined),
              label: const Text('確認メールを送る'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('確認メールを送りました',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                SizedBox(height: 8),
                Text(
                  'メール内のリンクを開いたあと、下の「確認できたか見る」を押してください。\n'
                  'メールが見当たらない場合は、迷惑メールフォルダもご確認ください。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('確認できたか見る'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _submitting ? null : _sendVerification,
              child: const Text('メールをもう一度送る'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'パスワードに加えて、スマートフォンの認証アプリに表示される6桁の数字でも本人確認を行う仕組みです。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('なぜ必要か', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 6),
              Text(
                '患者さんの症状や服薬の情報は、法律上とくに慎重な取り扱いが求められる情報です。'
                '国のガイドラインでも、医療情報を扱うシステムには二要素認証を採用することが求められています。',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('必要なもの', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'スマートフォンの認証アプリ（Google Authenticator、Microsoft Authenticator など。'
          'いずれも無料です）',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _startEnrollment,
            icon: const Icon(Icons.security),
            label: const Text('設定をはじめる'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnrollmentSteps() {
    final e = _enrollment!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('① 認証アプリに登録する',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        const Text(
          '認証アプリの「＋」から読み取り画面を開き、下のQRコードを写してください。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: e.qrCodeUrl,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'この画面をスマートフォンで見ているなど、カメラで写せないときは、'
          '「キーを手動入力」を選んで下の文字列を貼り付けてください。',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('セットアップキー', style: TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 6),
              SelectableText(
                e.manualEntryKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    // await の前に messenger を掴んでおく(非同期後の context 参照を避ける)
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: e.manualEntryKey));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('キーをコピーしました'), duration: Duration(seconds: 2)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('コピー'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('② 表示された6桁を入力する',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        const Text(
          '認証アプリに6桁の数字が表示されます。30秒ごとに変わるので、'
          '表示されている最新のものを入力してください。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            labelText: '6桁の認証コード',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _enrollment = null;
                        _codeController.clear();
                        _error = null;
                      }),
              child: const Text('やめる'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _submitting ? null : _completeEnrollment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('設定を完了する'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnrolledView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user, color: Colors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '二要素認証が有効です',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'ログイン時にパスワードに加えて、認証アプリの6桁の数字が必要になります。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 8),
        const Text(
          'スマートフォンを機種変更・紛失した場合は、先に解除するか、'
          '管理者に連絡してください。',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.6),
        ),
        const SizedBox(height: 28),
        TextButton.icon(
          onPressed: _submitting ? null : _unenroll,
          icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
          label: const Text('二要素認証を解除する', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
