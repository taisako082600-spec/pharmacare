import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  Color get _themeColor {
    switch (user.role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      default: return const Color(0xFF1976D2);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user.isPharmacist) return _PharmacistHome(user: user, themeColor: _themeColor);
    return _CareWorkerHome(user: user, themeColor: _themeColor);
  }
}

void _showNotifications(BuildContext context, String facilityId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(children: [
              Icon(Icons.notifications, color: Color(0xFF1976D2)),
              SizedBox(width: 8),
              Text('アラート一覧（14日以内）', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('events')
                  .where('facilityId', isEqualTo: facilityId)
                  .limit(100)
                  .snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final now = DateTime.now().subtract(const Duration(days: 1));
                var docs = snap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final date = (data['date'] as Timestamp?)?.toDate();
                  return date != null && date.isAfter(now);
                }).toList();
                // クライアント側でソート
                docs.sort((a, b) {
                  final dateA = ((a.data() as Map)['date'] as Timestamp?)?.toDate();
                  final dateB = ((b.data() as Map)['date'] as Timestamp?)?.toDate();
                  return (dateA ?? DateTime.now()).compareTo(dateB ?? DateTime.now());
                });
                docs = docs.take(30).toList();
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('現在アラートはありません', style: TextStyle(color: Colors.black38)),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final date = (d['date'] as Timestamp?)?.toDate();
                    final type = d['type'] as String? ?? '';
                    final isExpiry = type == '薬切れ';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isExpiry ? Colors.red.shade50 : Colors.orange.shade50,
                        child: Icon(isExpiry ? Icons.medication_outlined : Icons.event,
                            color: isExpiry ? Colors.red : Colors.orange, size: 20),
                      ),
                      title: Text(d['title'] as String? ?? type,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(d['subtitle'] as String? ?? '',
                          style: const TextStyle(fontSize: 12)),
                      trailing: date != null
                          ? Text('${date.month}/${date.day}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isExpiry ? Colors.red : Colors.orange,
                                  fontWeight: FontWeight.bold))
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class _PharmacistHome extends StatelessWidget {
  final UserModel user;
  final Color themeColor;
  const _PharmacistHome({required this.user, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final facilityIds = user.facilityIds.isNotEmpty ? user.facilityIds : (user.facilityId.isNotEmpty ? [user.facilityId] : <String>[]);

    // 介護士ホームと同じ組み方に揃える。
    // 薬剤師にとって一番急ぐのは薬切れなので、それを最上段に置く。
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 132,
            pinned: true,
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                onPressed: () => _showNotifications(context, user.facilityId),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppTheme.ink,
                padding: const EdgeInsets.fromLTRB(22, 62, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _CareWorkerHome._todayLabel(now),
                      style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8FA0BA),
                        letterSpacing: 1.4, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      facilityIds.length == 1 ? '担当施設 1件' : '担当施設 ${facilityIds.length}件',
                      style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 3),
                    Text('${user.name}さん · 薬剤師',
                        style: const TextStyle(fontSize: 13, color: Color(0xFFAFBED4))),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (facilityIds.isEmpty)
                    _EmptyConnectionCard()
                  else ...[
                    // 薬切れアラート（7日以内）。急ぐものが最初に目に入るようにする。
                    _MedExpiryAlertCard(facilityIds: facilityIds),
                    const SizedBox(height: 30),
                    const _SectionLabel('担当施設'),
                    ...facilityIds.map((fid) => _FacilityCard(facilityId: fid, user: user, themeColor: themeColor)),
                    const SizedBox(height: 30),
                    const _SectionLabel('直近の予定'),
                    _UpcomingEventsCard(facilityIds: facilityIds, themeColor: themeColor),
                    const SizedBox(height: 30),
                    const _SectionLabel('最新メッセージ'),
                    _RecentChatsCard(user: user, themeColor: themeColor),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareWorkerHome extends StatelessWidget {
  final UserModel user;
  final Color themeColor;
  const _CareWorkerHome({required this.user, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // 情報の並び順を「今日 → 数字 → 詳細」に組み替えている。
    // 以前はグラデーションの挨拶が画面上部160pxを占め、その下に同じ重みの
    // セクションが等間隔で続いていたため、何を先に見ればよいか分からなかった。
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: CustomScrollView(
        slivers: [
          // 見出しは濃紺の面。グラデーションをやめ、施設名を主役にする。
          SliverAppBar(
            expandedHeight: 132,
            pinned: true,
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                onPressed: () => _showNotifications(context, user.facilityId),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppTheme.ink,
                padding: const EdgeInsets.fromLTRB(22, 62, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _todayLabel(now),
                      style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8FA0BA),
                        letterSpacing: 1.4, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.facilityName.isNotEmpty ? user.facilityName : '施設未設定',
                      style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: -0.3),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text('${user.name}さん · ${user.displayRole}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFFAFBED4))),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user.facilityId.isEmpty)
                    _EmptyConnectionCard()
                  else ...[
                    // 数字を最初に、大きく。ひと目で規模と要対応がつかめる。
                    _CareWorkerSummary(user: user, themeColor: themeColor),
                    const SizedBox(height: 30),
                    const _SectionLabel('直近の予定'),
                    _UpcomingEventsCard(facilityIds: [user.facilityId], themeColor: themeColor),
                    const SizedBox(height: 30),
                    const _SectionLabel('最新メッセージ'),
                    _RecentChatsCard(user: user, themeColor: themeColor),
                    const SizedBox(height: 30),
                    const _SectionLabel('担当薬剤師'),
                    _AssignedPharmacistsCard(facilityId: user.facilityId, themeColor: themeColor),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _todayLabel(DateTime now) {
    const w = ['月', '火', '水', '木', '金', '土', '日'];
    return '${now.month}月${now.day}日（${w[now.weekday - 1]}）';
  }
}

/// 節の見出し。アイコンと色を外し、小さく静かな文字だけにした。
/// 見出しが主張すると、その下の中身と重みが競合して視線が定まらない。
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSub,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyConnectionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
      child: const Row(
        children: [
          Icon(Icons.link_off, color: Colors.orange),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '施設との連携が設定されていません。\nマイページから施設と連携してください。',
              style: TextStyle(fontSize: 13, color: Colors.orange, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacilityCard extends StatefulWidget {
  final String facilityId;
  final UserModel user;
  final Color themeColor;
  const _FacilityCard({required this.facilityId, required this.user, required this.themeColor});

  @override
  State<_FacilityCard> createState() => _FacilityCardState();
}

class _FacilityCardState extends State<_FacilityCard> {
  late Stream<({Map<String, dynamic> facData, int patCount})> _combinedStream;

  @override
  void initState() {
    super.initState();
    _combinedStream = Stream.multi((controller) async {
      final db = FirebaseFirestore.instance;
      final subscriptions = <dynamic>[];
      Map<String, dynamic> facData = {};
      int patCount = 0;

      try {
        subscriptions.add(db.collection('facilities').doc(widget.facilityId).snapshots().listen(
          (snap) {
            facData = snap.data() ?? {};
            controller.add((facData: facData, patCount: patCount));
          },
          onError: (e) => controller.addError(e),
        ));

        subscriptions.add(db.collection('patients').where('facilityId', isEqualTo: widget.facilityId).snapshots().listen(
          (snap) {
            patCount = snap.docs.length;
            controller.add((facData: facData, patCount: patCount));
          },
          onError: (e) => controller.addError(e),
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
    return StreamBuilder<({Map<String, dynamic> facData, int patCount})>(
      stream: _combinedStream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final data = snap.data!;
        final facData = data.facData;
        final patCount = data.patCount;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: widget.themeColor, width: 4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: widget.themeColor.withValues(alpha: 0.1),
                child: Icon(Icons.business, color: widget.themeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(facData['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if ((facData['address'] ?? '').isNotEmpty)
                      Text(facData['address'], style: const TextStyle(fontSize: 12, color: Colors.black38)),
                  ],
                ),
              ),
              Column(
                children: [
                  Text('$patCount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.themeColor)),
                  const Text('名', style: TextStyle(fontSize: 11, color: Colors.black38)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CareWorkerSummary extends StatefulWidget {
  final UserModel user;
  final Color themeColor;
  const _CareWorkerSummary({required this.user, required this.themeColor});

  @override
  State<_CareWorkerSummary> createState() => _CareWorkerSummaryState();
}

class _CareWorkerSummaryState extends State<_CareWorkerSummary> {
  late Stream<({int patCount, int eventCount, int pharCount})> _summaryStream;

  @override
  void initState() {
    super.initState();
    _summaryStream = Stream.multi((controller) async {
      final db = FirebaseFirestore.instance;
      final subscriptions = <dynamic>[];
      int patCount = 0;
      int eventCount = 0;
      int pharCount = 0;

      try {
        subscriptions.add(db.collection('patients').where('facilityId', isEqualTo: widget.user.facilityId).snapshots().listen(
          (snap) {
            patCount = snap.docs.length;
            controller.add((patCount: patCount, eventCount: eventCount, pharCount: pharCount));
          },
          onError: (e) => controller.addError(e),
        ));

        subscriptions.add(db.collection('events')
            .where('facilityId', isEqualTo: widget.user.facilityId)
            .limit(100)
            .snapshots().listen(
          (snap) {
            final now = DateTime.now();
            eventCount = snap.docs.where((d) {
              final data = d.data();
              final date = (data['date'] as Timestamp?)?.toDate();
              return date != null && date.isAfter(now);
            }).length;
            controller.add((patCount: patCount, eventCount: eventCount, pharCount: pharCount));
          },
          onError: (e) => controller.addError(e),
        ));

        subscriptions.add(db.collection('users')
            .where('role', isEqualTo: '薬剤師')
            .snapshots().listen(
          (snap) {
            pharCount = snap.docs.where((d) {
              final data = d.data();
              final facilityIds = List<String>.from(data['facilityIds'] ?? []);
              return facilityIds.contains(widget.user.facilityId);
            }).length;
            controller.add((patCount: patCount, eventCount: eventCount, pharCount: pharCount));
          },
          onError: (e) => controller.addError(e),
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
    return StreamBuilder<({int patCount, int eventCount, int pharCount})>(
      stream: _summaryStream,
      builder: (context, snap) {
        final data = snap.data ?? (patCount: 0, eventCount: 0, pharCount: 0);
        return Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: '入居者',
                value: '${data.patCount}名',
                icon: Icons.people,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: '今後の予定',
                value: '${data.eventCount}件',
                icon: Icons.event,
                color: AppTheme.accentDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: '担当薬剤師',
                value: '${data.pharCount}名',
                icon: Icons.local_pharmacy,
                color: AppTheme.ink,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    // 数字を主役にする。以前はアイコン・数値・ラベルが近い大きさで並んでいて、
    // 一番読みたい数字が埋もれていた。単位はラベル側に逃がして数字だけ大きくする。
    final n = value.replaceAll(RegExp(r'[^0-9]'), '');
    final unit = value.replaceAll(RegExp(r'[0-9]'), '');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                n.isEmpty ? value : n,
                style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700,
                  color: color, letterSpacing: -0.8, height: 1.0),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.75))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSub, height: 1.3)),
        ],
      ),
    );
  }
}

class _AssignedPharmacistsCard extends StatelessWidget {
  final String facilityId;
  final Color themeColor;
  const _AssignedPharmacistsCard({required this.facilityId, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: '薬剤師')
          .where('facilityIds', arrayContains: facilityId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) debugPrint('担当薬剤師取得エラー: ${snap.error}');
        if (!snap.hasData) return const SizedBox();
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Text('担当薬剤師が未設定です', style: TextStyle(color: Colors.black38, fontSize: 13)),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: themeColor.withValues(alpha: 0.1),
                    child: Text(
                      (data['name'] ?? '?').toString().isNotEmpty ? data['name'].toString()[0] : '?',
                      style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(data['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black38)),
                      ],
                    ),
                  ),
                  const Chip(label: Text('連携中', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFE8F5E9)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _UpcomingEventsCard extends StatelessWidget {
  final List<String> facilityIds;
  final Color themeColor;
  const _UpcomingEventsCard({required this.facilityIds, required this.themeColor});

  Color _typeColor(String type) {
    switch (type) {
      case '訪問': return Colors.purple;
      case '処方': return Colors.blue;
      case '受診': return Colors.teal;
      case 'フォロー': return Colors.orange;
      case '薬切れ': return Colors.red;
      case '次回受診': return Colors.indigo;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (facilityIds.isEmpty) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('facilityId', whereIn: facilityIds)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        var docs = snap.data!.docs
            .where((d) {
              final data = d.data() as Map<String, dynamic>;
              final date = (data['date'] as Timestamp?)?.toDate();
              return date != null && date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
            })
            .toList();
        // クライアント側でソート
        docs.sort((a, b) {
          final dateA = ((a.data() as Map)['date'] as Timestamp?)?.toDate();
          final dateB = ((b.data() as Map)['date'] as Timestamp?)?.toDate();
          return (dateA ?? DateTime.now()).compareTo(dateB ?? DateTime.now());
        });
        docs = docs.take(3).toList();
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Text('予定はありません', style: TextStyle(color: Colors.black38, fontSize: 13)),
          );
        }
        const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp).toDate();
            final color = _typeColor(data['type'] ?? '');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: color, width: 3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Column(
                      children: [
                        Text('${date.month}/${date.day}', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                        Text(weekdays[date.weekday - 1], style: TextStyle(fontSize: 10, color: color)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        if ((data['subtitle'] ?? '').isNotEmpty)
                          Text(data['subtitle'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(data['type'] ?? '', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _RecentChatsCard extends StatelessWidget {
  final UserModel user;
  final Color themeColor;
  const _RecentChatsCard({required this.user, required this.themeColor});

  String _formatTime(Timestamp ts) {
    final dt = ts.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 1) return '昨日';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final facilityId = user.facilityId.isNotEmpty ? user.facilityId : (user.facilityIds.isNotEmpty ? user.facilityIds.first : '');
    if (facilityId.isEmpty) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: '${facilityId}_')
          .where(FieldPath.documentId, isLessThan: '${facilityId}_')
          .orderBy(FieldPath.documentId)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['lastMessage'] as String? ?? '').isNotEmpty;
        }).toList();

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Text('まだメッセージがありません', style: TextStyle(color: Colors.black38, fontSize: 13)),
          );
        }
        return Column(
          children: docs.take(3).map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final lastMessage = data['lastMessage'] as String? ?? '';
            final lastSender = data['lastSender'] as String? ?? '';
            final lastSenderUid = data['lastSenderUid'] as String?;
            final lastMessageAt = data['lastMessageAt'] as Timestamp?;
            final lastReadMap = data['lastRead'] as Map<String, dynamic>?;
            final lastReadAt = lastReadMap?[user.uid] as Timestamp?;
            final hasUnread = lastMessage.isNotEmpty &&
                lastSenderUid != user.uid &&
                (lastReadAt == null || (lastMessageAt != null && lastMessageAt.compareTo(lastReadAt) > 0));

            final roomId = doc.id;
            String roomName = '全体連絡';
            if (roomId.contains('_pharmacist_')) {
              roomName = '個別相談';
            } else if (roomId.contains('_patient_')) {
              roomName = '入居者相談';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasUnread ? themeColor.withValues(alpha: 0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: themeColor.withValues(alpha: 0.12),
                        radius: 20,
                        child: Icon(Icons.chat_bubble_rounded, color: themeColor, size: 18),
                      ),
                      if (hasUnread)
                        Positioned(
                          right: 0, top: 0,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(roomName, style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          lastSender.isNotEmpty ? '$lastSender: $lastMessage' : lastMessage,
                          style: TextStyle(fontSize: 12, color: hasUnread ? Colors.black87 : Colors.black54, fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (lastMessageAt != null)
                    Text(_formatTime(lastMessageAt), style: TextStyle(fontSize: 11, color: hasUnread ? themeColor : Colors.grey.shade400)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// 薬切れアラートカード（7日以内に切れる薬）
class _MedExpiryAlertCard extends StatelessWidget {
  final List<String> facilityIds;
  const _MedExpiryAlertCard({required this.facilityIds});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 7));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('type', isEqualTo: '薬切れ')
          .where('facilityId', whereIn: facilityIds.take(10).toList())
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final expiring = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final date = (data['date'] as Timestamp?)?.toDate();
          if (date == null) return false;
          return date.isAfter(now.subtract(const Duration(days: 1))) && date.isBefore(soon);
        }).toList();

        if (expiring.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medication_outlined, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '薬切れアラート（7日以内: ${expiring.length}件）',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...expiring.take(5).map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['date'] as Timestamp).toDate();
                final daysLeft = date.difference(now).inDays;
                final title = data['title'] as String? ?? '薬切れ';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: daysLeft <= 2 ? Colors.red : Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text(title, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                      Text(
                        daysLeft == 0 ? '本日' : '残$daysLeft日',
                        style: TextStyle(fontSize: 11, color: daysLeft <= 2 ? Colors.red.shade700 : Colors.orange.shade800, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
