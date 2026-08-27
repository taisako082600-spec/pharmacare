import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/invite_code.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'mfa_screens.dart';
import 'connection_request_screen.dart';

class ProfileScreen extends StatelessWidget {
  final UserModel user;
  const ProfileScreen({super.key, required this.user});

  Color get _roleColor {
    switch (user.role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      default: return const Color(0xFF388E3C);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _roleColor,
        foregroundColor: Colors.white,
        title: const Text('マイページ'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: _roleColor,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white,
                    child: Text(user.name.isNotEmpty ? user.name[0] : '?', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _roleColor)),
                  ),
                  const SizedBox(height: 12),
                  Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Text(user.role, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  Text(user.displayRole, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (user.facilityName.isNotEmpty)
                    Text(user.facilityName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(user.email, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    if (user.isPharmacist) ...[
                      _MenuItem(
                        icon: Icons.business_center_outlined,
                        label: '施設との連携',
                        value: '${user.facilityIds.length}施設',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PharmacistConnectionScreen(user: user))),
                      ),
                      const Divider(height: 1, indent: 56),
                    ],
                    if (user.isCareWorker && user.facilityId.isNotEmpty) ...[
                      _InviteCodeTile(user: user),
                      const Divider(height: 1, indent: 56),
                    ],
                    _MenuItem(icon: Icons.notifications_outlined, label: '通知設定', onTap: () {}),
                    const Divider(height: 1, indent: 56),
                    _MenuItem(icon: Icons.business_outlined, label: '施設', value: user.facilityName.isNotEmpty ? user.facilityName : '未設定', onTap: () {}),
                    const Divider(height: 1, indent: 56),
                    _MenuItem(icon: Icons.lock_outline, label: 'パスワード変更', onTap: () {}),
                    const Divider(height: 1, indent: 56),
                    // 二要素認証(ガイドライン システム運用編 14⑤)。
                    // 現状は任意設定。全員必須にする場合は Identity Platform 側の
                    // mfa.state を MANDATORY へ変更する。
                    _MenuItem(
                      icon: Icons.security_outlined,
                      label: '二要素認証',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MfaSettingsScreen(accountName: user.email),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    _MenuItem(icon: Icons.help_outline, label: 'ヘルプ・お問い合わせ', onTap: () {}),
                    const Divider(height: 1, indent: 56),
                    _MenuItem(icon: Icons.info_outline, label: 'バージョン情報', value: 'v0.2.0', onTap: () {}),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('ログアウト'),
                        content: const Text('ログアウトしてもよろしいですか？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                          ElevatedButton(
                            onPressed: () async {
                              await AuthService().signOut();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (_) => false,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            child: const Text('ログアウト'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('ログアウト', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// 介護士・看護師用：招待コード発行
class _InviteCodeTile extends StatelessWidget {
  final UserModel user;
  const _InviteCodeTile({required this.user});

  Future<void> _issueCode(BuildContext context) async {
    final code = InviteCode.generate();
    // ドキュメントIDはコード文字列そのもの(firestore.rules が get() で照合するため)。
    await FirebaseFirestore.instance.collection('invite_codes').doc(code).set({
      'code': code,
      'facilityId': user.facilityId,
      'facilityName': user.facilityName,
      'createdBy': user.uid,
      'used': false,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('招待コードを発行しました'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('このコードをスタッフに共有してください。', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
              child: Text(InviteCode.formatForDisplay(code),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 3, color: Color(0xFF1976D2))),
            ),
            const SizedBox(height: 8),
            const Text('有効期限：24時間', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('コードをコピー'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.vpn_key_outlined, color: Colors.blueGrey),
      title: const Text('スタッフ招待コードを発行'),
      subtitle: Text(user.facilityName, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: () => _issueCode(context),
    );
  }
}


class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) Text(value!, style: const TextStyle(color: Colors.black38, fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}
