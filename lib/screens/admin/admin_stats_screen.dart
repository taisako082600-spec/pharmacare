import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';

class AdminStatsScreen extends StatelessWidget {
  final UserModel user;
  const AdminStatsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: const Text('統計・レポート'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('施設別状況', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                }
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final facilities = snapshot.data!.docs;
                if (facilities.isEmpty) return const Text('施設が登録されていません', style: TextStyle(color: Colors.black38));
                return Column(
                  children: facilities.map((fac) {
                    final data = fac.data() as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance.collection('users').where('facilityId', isEqualTo: fac.id).snapshots(),
                                  builder: (context, userSnap) {
                                    return _MiniStat(label: 'スタッフ', value: '${userSnap.data?.docs.length ?? 0}名', color: const Color(0xFF1976D2));
                                  },
                                ),
                              ),
                              Expanded(
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance.collection('patients').where('facilityId', isEqualTo: fac.id).snapshots(),
                                  builder: (context, patSnap) {
                                    return _MiniStat(label: '入居者', value: '${patSnap.data?.docs.length ?? 0}名', color: const Color(0xFF388E3C));
                                  },
                                ),
                              ),
                              const Expanded(child: _MiniStat(label: 'チャット数', value: '-', color: Colors.orange)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('役職別ユーザー構成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                }
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final docs = snapshot.data!.docs;
                final roleCounts = <String, int>{};
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final role = data['role'] as String? ?? '不明';
                  roleCounts[role] = (roleCounts[role] ?? 0) + 1;
                }
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: roleCounts.entries.map((e) {
                      final total = docs.length;
                      final ratio = total > 0 ? e.value / total : 0.0;
                      final colors = {
                        '薬剤師': const Color(0xFF1976D2),
                        '介護士': const Color(0xFF388E3C),
                        '看護師': const Color(0xFFD32F2F),
                        '管理者': const Color(0xFF7B1FA2),
                      };
                      final color = colors[e.key] ?? Colors.grey;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text('${e.value}名 (${(ratio * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 13, color: color)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black38)),
      ],
    );
  }
}
