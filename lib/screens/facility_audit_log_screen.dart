import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../services/audit_service.dart';
import '../theme/app_theme.dart';

/// 施設が自分のところの操作履歴を確認する画面。
///
/// 「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編 17① は
/// アクセスログを**記録すること**に加えて**定期的に確認すること**まで求めている。
/// 確認する主体は施設であって、提供者ではない。
///
/// 記録の仕組みと権限は揃っていたが閲覧手段が無く、読み取りも管理者限定だったため、
/// 施設は求められていることを果たしようがなかった。ここを開ける
/// (firestore.rules の audit_logs は自施設のログに限って read を許可している)。
///
/// 表示に徹し、書き換えの導線は置かない。ログの改ざん・削除はルールで
/// 全面禁止されており(17②③)、画面にボタンが無いことでその方針を見た目でも示す。
class FacilityAuditLogScreen extends StatelessWidget {
  final UserModel user;
  const FacilityAuditLogScreen({super.key, required this.user});

  static const _actionLabels = {
    'READ': '閲覧',
    'CREATE': '登録',
    'UPDATE': '変更',
    'DELETE': '削除',
    'LOGIN': 'ログイン',
    'LOGOUT': 'ログアウト',
    'EXPORT': '書面出力',
  };

  static const _collectionLabels = {
    'patients': '入居者情報',
    'users': '利用者',
    'medicines': '薬剤',
    'vitals': 'バイタル',
    'visits': '受診',
    'auth': '認証',
  };

  // 意味を持つものだけ色を付ける(app_theme.dart の方針)。
  // 削除は取り返しがつかないので赤、変更は要確認なので黄、閲覧は無彩色。
  static Color _actionColor(String action) {
    switch (action) {
      case 'DELETE':
        return AppTheme.danger;
      case 'UPDATE':
        return AppTheme.warn;
      case 'CREATE':
        return AppTheme.ok;
      default:
        return AppTheme.textSub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('M/d HH:mm');

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        foregroundColor: Colors.white,
        title: const Text('操作履歴'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: const Text(
              '入居者情報に誰がいつ触れたかの記録です。定期的に確認することが'
              'ガイドラインで求められています。\n'
              'この記録は書き足すことしかできず、消したり書き直したりはできません。',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSub, height: 1.6),
            ),
          ),
          const Divider(height: 1, color: AppTheme.line),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: AuditService().getAuditLogsForFacility(user.facilityId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _message(
                    '記録を読み込めませんでした。\n${snapshot.error}',
                    AppTheme.danger,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return _message('まだ記録がありません。', AppTheme.textSub);
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.line),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final action = (data['action'] as String?) ?? '';
                    final timestamp = data['timestamp'];
                    final when = timestamp is Timestamp
                        ? dateFormat.format(timestamp.toDate())
                        : '—';
                    final collection = (data['collection'] as String?) ?? '';

                    return ListTile(
                      dense: true,
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _actionColor(action).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _actionLabels[action] ?? action,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _actionColor(action),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _collectionLabels[collection] ?? collection,
                              style: const TextStyle(fontSize: 14, color: AppTheme.textMain),
                            ),
                          ),
                          Text(
                            when,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          (data['userName'] as String?)?.isNotEmpty == true
                              ? data['userName'] as String
                              : '(氏名なし)',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
        ),
      );
}
