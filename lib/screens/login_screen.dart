import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/audit_service.dart';
import '../services/mfa_service.dart';
import '../models/user_model.dart';
import 'mfa_screens.dart';
import 'main_shell.dart';
import 'admin/admin_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'メールアドレスとパスワードを入力してください');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final cred = await _authService.signIn(email, password);
      await _afterSignIn(cred);
    } on FirebaseAuthMultiFactorException catch (e) {
      // 二要素認証を登録済みのユーザー。パスワードは正しいので、認証アプリの
      // 6桁を入力してもらってサインインを完了させる(ガイドライン システム運用編 14⑤)。
      if (!mounted) return;
      setState(() => _loading = false);
      final code = await showTotpChallengeDialog(context);
      if (code == null) return; // 利用者がキャンセル

      setState(() { _loading = true; _error = null; });
      try {
        final cred = await MfaService().resolveSignIn(
          resolver: e.resolver,
          oneTimePassword: code,
        );
        await _afterSignIn(cred);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = '認証コードが正しくありません。認証アプリに表示されている6桁を入力してください';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ログインに失敗しました。メールアドレスまたはパスワードが正しくありません';
        _loading = false;
      });
    }
  }

  /// サインイン成功後の共通処理。
  /// パスワードのみで通った場合と、二要素認証を経た場合の両方から呼ばれる。
  Future<void> _afterSignIn(UserCredential cred) async {
    final data = await _authService.getUserData(cred.user!.uid);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _error = 'ユーザー情報が見つかりません';
        _loading = false;
      });
      return;
    }
    final user = UserModel.fromMap(cred.user!.uid, data);

    // ログイン時刻の記録(ガイドライン システム運用編 17① で求められる証跡)。
    // 記録に失敗してもログイン自体は継続させる。
    await AuditService().log(
      userId: user.uid,
      userName: user.name,
      action: AuditService.actionLogin,
      collection: 'users',
      documentId: user.uid,
      facilityId: user.facilityId,
    );

    if (!mounted) return;
    if (user.isAdmin) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminShell(user: user)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainShell(user: user)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.local_pharmacy, size: 56, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text('ファーマケア', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('薬剤師・介護施設の連携プラットフォーム', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 15))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ログイン', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_loading,
                          decoration: InputDecoration(
                            labelText: 'メールアドレス',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          enabled: !_loading,
                          decoration: InputDecoration(
                            labelText: 'パスワード',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _loading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('ログイン', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                            child: const Text('アカウントを作成する'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
