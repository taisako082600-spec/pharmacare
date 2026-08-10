import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';

class AdminUsersScreen extends StatefulWidget {
  final UserModel user;
  const AdminUsersScreen({super.key, required this.user});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _filterRole = '全員';
  final List<String> _roles = ['全員', '薬剤師', '介護士', '看護師', '管理者'];

  Color _roleColor(String role) {
    switch (role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      default: return const Color(0xFF7B1FA2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: const Text('ユーザー管理'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _roles.map((r) {
                  final selected = _filterRole == r;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(r),
                      selected: selected,
                      onSelected: (_) => setState(() => _filterRole = r),
                      selectedColor: const Color(0xFF7B1FA2).withValues(alpha: 0.15),
                      checkmarkColor: const Color(0xFF7B1FA2),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snapshot.data!.docs;
                if (_filterRole != '全員') {
                  docs = docs.where((d) => (d.data() as Map<String, dynamic>)['role'] == _filterRole).toList();
                }
                if (docs.isEmpty) return const Center(child: Text('ユーザーが見つかりません', style: TextStyle(color: Colors.black38)));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final role = data['role'] as String? ?? '';
                    final color = _roleColor(role);
                    final isAdmin = data['isAdmin'] as bool? ?? false;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            radius: 22,
                            child: Text(
                              (data['name'] ?? '?').toString().isNotEmpty ? data['name'].toString()[0] : '?',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (isAdmin) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('管理者', style: TextStyle(fontSize: 10, color: Color(0xFF7B1FA2))),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(data['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black38)),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(role, style: TextStyle(fontSize: 11, color: color)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(data['facilityName'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'make_admin') {
                                await doc.reference.update({'isAdmin': true, 'role': '管理者'});
                              } else if (value == 'remove_admin') {
                                await doc.reference.update({'isAdmin': false});
                              } else if (value == 'delete') {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('ユーザーを削除'),
                                    content: Text('「${data['name']}」を削除しますか？'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                                      ElevatedButton(
                                        onPressed: () async {
                                          // ユーザー削除時、所属する「全て」の施設のpharmacistIds/adminUidsから
                                          // このUIDを取り除いておかないと参照だけが残り、
                                          // 「担当薬剤師◯名」等の表示が実際の登録人数と食い違う
                                          // (2026-07-19に実際に発生・発見)。薬剤師は複数施設に所属しうる
                                          // (facilityIds配列)ため、facilityId単体だけでなくfacilityIds全件を対象にする。
                                          final singleId = data['facilityId'] as String?;
                                          final multiIds = (data['facilityIds'] as List?)?.cast<String>() ?? const [];
                                          final targetFacilityIds = {
                                            if (singleId != null && singleId.isNotEmpty) singleId,
                                            ...multiIds,
                                          };
                                          for (final fid in targetFacilityIds) {
                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('facilities')
                                                  .doc(fid)
                                                  .update({
                                                'pharmacistIds': FieldValue.arrayRemove([doc.id]),
                                                'adminUids': FieldValue.arrayRemove([doc.id]),
                                              });
                                            } catch (_) {
                                              // 施設ドキュメントが既に存在しない等でも、ユーザー削除自体は継続する
                                            }
                                          }
                                          await doc.reference.delete();
                                          if (context.mounted) Navigator.pop(context);
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                        child: const Text('削除'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              if (!isAdmin)
                                const PopupMenuItem(value: 'make_admin', child: Text('管理者に昇格')),
                              if (isAdmin)
                                const PopupMenuItem(value: 'remove_admin', child: Text('管理者権限を削除')),
                              const PopupMenuItem(value: 'delete', child: Text('削除', style: TextStyle(color: Colors.red))),
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
      ),
    );
  }
}
