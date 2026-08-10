import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';
import '../main_shell.dart';

class AdminDashboardScreen extends StatefulWidget {
  final UserModel user;
  const AdminDashboardScreen({super.key, required this.user});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Stream<({int facilities, int users, int patients})> _statsStream;

  @override
  void initState() {
    super.initState();
    _statsStream = _getCombinedStatsStream();
  }

  Stream<({int facilities, int users, int patients})> _getCombinedStatsStream() {
    return Stream.multi((controller) async {
      final db = FirebaseFirestore.instance;

      int facilityCount = 0;
      int userCount = 0;
      int patientCount = 0;

      final subscriptions = <dynamic>[];

      try {
        subscriptions.add(db.collection('facilities').snapshots().listen(
          (snap) {
            facilityCount = snap.docs.length;
            controller.add((facilities: facilityCount, users: userCount, patients: patientCount));
          },
          onError: (e) {
            controller.addError(e);
          },
        ));

        subscriptions.add(db.collection('users').snapshots().listen(
          (snap) {
            userCount = snap.docs.length;
            controller.add((facilities: facilityCount, users: userCount, patients: patientCount));
          },
          onError: (e) {
            controller.addError(e);
          },
        ));

        subscriptions.add(db.collection('patients').snapshots().listen(
          (snap) {
            patientCount = snap.docs.length;
            controller.add((facilities: facilityCount, users: userCount, patients: patientCount));
          },
          onError: (e) {
            controller.addError(e);
          },
        ));

        controller.onCancel = () {
          for (var sub in subscriptions) {
            sub.cancel();
          }
        };
      } catch (e) {
        controller.addError(e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: const Color(0xFF7B1FA2),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await AuthService().signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        const Text('管理者モード', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${widget.user.name} さん', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 統計カード（複合ストリーム使用）
                  StreamBuilder<({int facilities, int users, int patients})>(
                    stream: _statsStream,
                    builder: (context, snap) {
                      final data = snap.data ?? (facilities: 0, users: 0, patients: 0);
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.8,
                        children: [
                          _StatCard(label: '登録施設', value: '${data.facilities}', icon: Icons.business, color: const Color(0xFF7B1FA2)),
                          _StatCard(label: 'ユーザー数', value: '${data.users}', icon: Icons.people, color: const Color(0xFF1976D2)),
                          _StatCard(label: '入居者数', value: '${data.patients}', icon: Icons.elderly, color: const Color(0xFF388E3C)),
                          _StatCard(label: '今日のメッセージ', value: '-', icon: Icons.chat_bubble, color: Colors.orange),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // 通常モードで確認
                  const Text('施設ユーザーとして確認', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Text('施設が登録されていません', style: TextStyle(color: Colors.black38));
                      }
                      return Column(
                        children: snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              tileColor: Colors.white,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFF3E5F5),
                                child: Icon(Icons.business, color: Color(0xFF7B1FA2)),
                              ),
                              title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('この施設の画面を確認する'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                              onTap: () {
                                final dummyUser = UserModel(
                                  uid: widget.user.uid,
                                  name: widget.user.name,
                                  role: '管理者',
                                  facilityName: data['name'] ?? '',
                                  facilityId: doc.id,
                                  email: widget.user.email,
                                  isAdmin: true,
                                );
                                Navigator.push(context, MaterialPageRoute(builder: (_) => MainShell(user: dummyUser)));
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // 最新ユーザー登録
                  const Text('最近登録したユーザー', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).limit(5).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                      }
                      if (!snapshot.hasData) return const SizedBox();
                      return Column(
                        children: snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final nameStr = data['name'] as String? ?? '';
                          final initial = nameStr.isNotEmpty ? nameStr[0] : '?';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFFF3E5F5),
                                  radius: 18,
                                  child: Text(initial, style: const TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text('${data['role']} · ${data['facilityName']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black38)),
            ],
          ),
        ],
      ),
    );
  }
}
