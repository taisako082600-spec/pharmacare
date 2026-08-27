import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/invite_code.dart';

class FacilityAdminRequestsScreen extends StatelessWidget {
  final UserModel user;
  const FacilityAdminRequestsScreen({super.key, required this.user});

  Future<void> _issueInviteCode(BuildContext context) async {
    final code = InviteCode.generate();
    final expiresAt = DateTime.now().add(const Duration(minutes: 30));

    // ドキュメントIDはコード文字列そのもの。firestore.rules の users が
    // get() でこのドキュメントを引いて所属の正当性を確かめるため、自動採番IDにしない。
    await FirebaseFirestore.instance.collection('invite_codes').doc(code).set({
      'code': code,
      'facilityId': user.facilityId,
      'facilityName': user.facilityName,
      'createdBy': user.uid,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
    });

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('招待コード発行'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('このコードを薬剤師に対面で伝えてください', style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                InviteCode.formatForDisplay(code),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 3, color: Color(0xFF1976D2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                const Text('有効期限：30分', style: TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コードをコピーしました')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('コピー'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, String requestId, String pharmacistId, String pharmacistName) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(
      FirebaseFirestore.instance.collection('connection_requests').doc(requestId),
      {'status': 'approved', 'approvedAt': FieldValue.serverTimestamp()},
    );
    batch.update(
      FirebaseFirestore.instance.collection('facilities').doc(user.facilityId),
      {'pharmacistIds': FieldValue.arrayUnion([pharmacistId])},
    );
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(pharmacistId),
      {
        'facilityIds': FieldValue.arrayUnion([user.facilityId]),
        'facilityId': user.facilityId,
        'facilityName': user.facilityName,
      },
    );
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$pharmacistName さんを承認しました'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _reject(BuildContext context, String requestId, String pharmacistName) async {
    await FirebaseFirestore.instance.collection('connection_requests').doc(requestId)
        .update({'status': 'rejected', 'rejectedAt': FieldValue.serverTimestamp()});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$pharmacistName さんの申請を拒否しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF7B1FA2),
          foregroundColor: Colors.white,
          title: const Text('薬剤師との連携'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: '招待コード'),
              Tab(text: '申請一覧'),
              Tab(text: '連携中'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 招待コードタブ
            _InviteCodeTab(user: user, onIssue: () => _issueInviteCode(context)),
            // 申請一覧タブ
            _PendingRequestsTab(user: user, onApprove: _approve, onReject: _reject),
            // 連携中タブ
            _ConnectedPharmacistsTab(user: user),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeTab extends StatelessWidget {
  final UserModel user;
  final VoidCallback onIssue;
  const _InviteCodeTab({required this.user, required this.onIssue});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 説明カード
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 18),
                SizedBox(width: 8),
                Text('招待コードの使い方', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
              ]),
              SizedBox(height: 8),
              Text('① 「コードを発行」ボタンを押す\n② 薬剤師と対面してコードを伝える\n③ 薬剤師がアプリでコードを入力\n④ 自動的に連携が完了します',
                  style: TextStyle(fontSize: 13, color: Color(0xFF1976D2), height: 1.8)),
            ],
          ),
        ),
        // 発行ボタン
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onIssue,
              icon: const Icon(Icons.qr_code, color: Colors.white),
              label: const Text('招待コードを発行', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1FA2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 発行済みコード一覧
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('発行済みコード', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // expiresAtでのorderByは複合インデックスが必要になり、未作成だと
            // クエリがエラーのまま無限ローディングになるため使わない(2026-07-19に実際に発生した不具合と同じパターン)。
            stream: FirebaseFirestore.instance
                .collection('invite_codes')
                .where('facilityId', isEqualTo: user.facilityId)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red)));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = List<QueryDocumentSnapshot>.from(snap.data!.docs)
                ..sort((a, b) {
                  final at = (a.data() as Map<String, dynamic>)['expiresAt'] as Timestamp?;
                  final bt = (b.data() as Map<String, dynamic>)['expiresAt'] as Timestamp?;
                  if (at == null || bt == null) return 0;
                  return bt.compareTo(at);
                });
              final limitedDocs = docs.take(10).toList();
              if (limitedDocs.isEmpty) return const Center(child: Text('発行済みコードはありません', style: TextStyle(color: Colors.black38)));
              final now = DateTime.now();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: limitedDocs.length,
                itemBuilder: (context, i) {
                  final data = limitedDocs[i].data() as Map<String, dynamic>;
                  final expiresAt = (data['expiresAt'] as Timestamp).toDate();
                  final isExpired = now.isAfter(expiresAt);
                  final isUsed = data['used'] == true;
                  String statusLabel;
                  Color statusColor;
                  if (isUsed) { statusLabel = '使用済み'; statusColor = Colors.green; }
                  else if (isExpired) { statusLabel = '期限切れ'; statusColor = Colors.grey; }
                  else { statusLabel = '有効'; statusColor = Colors.orange; }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Text(InviteCode.formatForDisplay(data['code'] ?? ''), style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: 2,
                          color: isExpired || isUsed ? Colors.grey : const Color(0xFF1976D2),
                        )),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 2),
                            Text('${expiresAt.hour.toString().padLeft(2,'0')}:${expiresAt.minute.toString().padLeft(2,'0')} まで',
                                style: const TextStyle(fontSize: 10, color: Colors.black38)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PendingRequestsTab extends StatelessWidget {
  final UserModel user;
  final Function(BuildContext, String, String, String) onApprove;
  final Function(BuildContext, String, String) onReject;
  const _PendingRequestsTab({required this.user, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // status+createdAtの複合インデックスが未作成だとエラーのまま無限ローディングになるため、
      // where1件のみに絞りソートはクライアント側で行う(2026-07-19に実際に発生した不具合と同じパターン)。
      stream: FirebaseFirestore.instance
          .collection('connection_requests')
          .where('facilityId', isEqualTo: user.facilityId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs
            .where((d) => (d.data() as Map<String, dynamic>)['status'] == 'pending')
            .toList()
          ..sort((a, b) {
            final at = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bt = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (at == null || bt == null) return 0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.black26),
                SizedBox(height: 16),
                Text('新しい申請はありません', style: TextStyle(color: Colors.black38)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final pharmacistName = data['pharmacistName'] as String? ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFE3F2FD),
                          child: Icon(Icons.local_pharmacy, color: Color(0xFF1976D2)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pharmacistName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text(data['pharmacistEmail'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black38)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: const Text('承認待ち', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onReject(context, docs[i].id, pharmacistName),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('拒否'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => onApprove(context, docs[i].id, data['pharmacistId'], pharmacistName),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('承認する'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ConnectedPharmacistsTab extends StatelessWidget {
  final UserModel user;
  const _ConnectedPharmacistsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // role+facilityIds(arrayContains)の複合インデックスが未作成だとエラーのまま
      // 無限ローディングになるため、facilityIdsのみで取得しroleはクライアント側でフィルタする
      // (2026-07-19に実際に発生した不具合と同じパターン)。
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('facilityIds', arrayContains: user.facilityId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs
            .where((d) => (d.data() as Map<String, dynamic>)['role'] == '薬剤師')
            .toList();
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.black26),
                SizedBox(height: 16),
                Text('連携中の薬剤師はいません\n招待コードを発行して薬剤師と繋がりましょう', textAlign: TextAlign.center, style: TextStyle(color: Colors.black38)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.local_pharmacy, color: Color(0xFF1976D2)),
                ),
                title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(data['email'] ?? '', style: const TextStyle(fontSize: 12)),
                trailing: const Chip(label: Text('連携中', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFE8F5E9)),
              ),
            );
          },
        );
      },
    );
  }
}
