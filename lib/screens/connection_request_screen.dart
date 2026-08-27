import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

// 薬剤師用：施設を検索して申請する画面
class PharmacistConnectionScreen extends StatefulWidget {
  final UserModel user;
  const PharmacistConnectionScreen({super.key, required this.user});

  @override
  State<PharmacistConnectionScreen> createState() => _PharmacistConnectionScreenState();
}

class _PharmacistConnectionScreenState extends State<PharmacistConnectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 招待コードで施設と連携
  Future<void> _connectWithCode(String code) async {
    if (code.length != 6) return;
    final now = Timestamp.now();

    // ドキュメントIDがコード文字列そのものなので、クエリではなくID指定で引く。
    // firestore.rules は invite_codes を get のみ許可し list は施設関係者に限っている
    // (コードを知らない人がクエリで一覧できないようにするため)。
    final doc = await FirebaseFirestore.instance.collection('invite_codes').doc(code).get();
    final data = doc.data();

    if (!doc.exists || data == null || data['used'] == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コードが見つかりません'), backgroundColor: Colors.red),
      );
      return;
    }

    final expiresAt = data['expiresAt'] as Timestamp;

    if (now.compareTo(expiresAt) > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コードの有効期限が切れています'), backgroundColor: Colors.orange),
      );
      return;
    }

    final facilityId = data['facilityId'] as String;
    final facilityName = data['facilityName'] as String;

    // すでに連携済みか確認
    if (widget.user.facilityIds.contains(facilityId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$facilityName とは既に連携しています')),
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();

    // コードを使用済みに
    batch.update(doc.reference, {'used': true, 'usedBy': widget.user.uid, 'usedAt': FieldValue.serverTimestamp()});


    // 施設のpharmacistIdsに追加
    batch.update(
      FirebaseFirestore.instance.collection('facilities').doc(facilityId),
      {'pharmacistIds': FieldValue.arrayUnion([widget.user.uid])},
    );

    // 薬剤師のfacilityIdsに追加
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(widget.user.uid),
      {
        'facilityIds': FieldValue.arrayUnion([facilityId]),
        'facilityId': facilityId,
        'facilityName': facilityName,
        // 所属を変える書き込みなので、根拠として使ったコードを残す。
        // firestore.rules がこれを get() で照合し、実在・施設一致・未期限を確かめる。
        'joinedWithCode': code,
      },
    );

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「$facilityName」と連携しました！'), backgroundColor: Colors.green),
    );
    _tabController.animateTo(2); // 連携済みタブへ
  }

  Future<void> _sendRequest(String facilityId, String facilityName) async {
    // 既存の申請確認
    final existing = await FirebaseFirestore.instance
        .collection('connection_requests')
        .where('pharmacistId', isEqualTo: widget.user.uid)
        .where('facilityId', isEqualTo: facilityId)
        .get();

    if (existing.docs.isNotEmpty) {
      final status = existing.docs.first['status'];
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'pending' ? '申請中です' : status == 'approved' ? '既に繋がっています' : '申請を再送しますか？')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('connection_requests').add({
      'pharmacistId': widget.user.uid,
      'pharmacistName': widget.user.name,
      'pharmacistEmail': widget.user.email,
      'facilityId': facilityId,
      'facilityName': facilityName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「$facilityName」に申請を送りました'), backgroundColor: Colors.green),
    );
  }

  Future<void> _cancelRequest(String requestId) async {
    await FirebaseFirestore.instance.collection('connection_requests').doc(requestId).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('申請を取り消しました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        title: const Text('施設との連携'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'コードで連携'),
            Tab(text: '施設を探す'),
            Tab(text: '申請状況'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 招待コード入力タブ
          _InviteCodeInputTab(onConnect: _connectWithCode),
          // 施設一覧・申請タブ
          _FacilitySearchTab(user: widget.user, onRequest: _sendRequest),
          // 申請状況タブ
          _RequestStatusTab(user: widget.user, onCancel: _cancelRequest),
        ],
      ),
    );
  }
}

// 招待コード入力タブ
class _InviteCodeInputTab extends StatefulWidget {
  final Future<void> Function(String code) onConnect;
  const _InviteCodeInputTab({required this.onConnect});

  @override
  State<_InviteCodeInputTab> createState() => _InviteCodeInputTabState();
}

class _InviteCodeInputTabState extends State<_InviteCodeInputTab> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.lock_open_outlined, size: 64, color: Color(0xFF1976D2)),
          const SizedBox(height: 16),
          const Text('招待コードで連携', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            '施設管理者から受け取った\n6桁のコードを入力してください',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 12),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 32, letterSpacing: 12),
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
              ),
            ),
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _controller.text.length == 6 && !_loading
                  ? () async {
                      setState(() => _loading = true);
                      await widget.onConnect(_controller.text);
                      if (mounted) setState(() => _loading = false);
                      _controller.clear();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('連携する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: const Row(
              children: [
                Icon(Icons.security_outlined, size: 16, color: Colors.black38),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'コードは対面で受け取ることで、なりすましを防止します。有効期限は発行から24時間です。',
                    style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FacilitySearchTab extends StatefulWidget {
  final UserModel user;
  final Future<void> Function(String facilityId, String facilityName) onRequest;
  const _FacilitySearchTab({required this.user, required this.onRequest});

  @override
  State<_FacilitySearchTab> createState() => _FacilitySearchTabState();
}

class _FacilitySearchTabState extends State<_FacilitySearchTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: '施設名で検索',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('facilities').orderBy('name').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((d) {
                final name = (d.data() as Map<String, dynamic>)['name'] ?? '';
                return _search.isEmpty || name.contains(_search);
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('施設が見つかりません', style: TextStyle(color: Colors.black38)));
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('connection_requests')
                    .where('pharmacistId', isEqualTo: widget.user.uid)
                    .snapshots(),
                builder: (context, reqSnap) {
                  final myRequests = <String, String>{};
                  if (reqSnap.hasData) {
                    for (final doc in reqSnap.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      myRequests[data['facilityId']] = data['status'];
                    }
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final facilityId = doc.id;
                      final status = myRequests[facilityId];
                      final isConnected = widget.user.facilityIds.contains(facilityId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFF3E5F5),
                            child: Icon(Icons.business, color: Color(0xFF7B1FA2)),
                          ),
                          title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((data['address'] ?? '').isNotEmpty) Text(data['address'], style: const TextStyle(fontSize: 12)),
                              if ((data['phone'] ?? '').isNotEmpty) Text(data['phone'], style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          trailing: isConnected
                              ? const Chip(label: Text('連携中', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFE8F5E9))
                              : status == 'pending'
                                  ? const Chip(label: Text('申請中', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFFFF9C4))
                                  : ElevatedButton(
                                      onPressed: () => widget.onRequest(facilityId, data['name'] ?? ''),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1976D2),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(64, 32),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                      child: const Text('申請'),
                                    ),
                        ),
                      );
                    },
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

class _RequestStatusTab extends StatelessWidget {
  final UserModel user;
  final Future<void> Function(String requestId) onCancel;
  const _RequestStatusTab({required this.user, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // pharmacistId+createdAtの複合インデックスが未作成だとエラーのまま無限ローディングになるため、
      // where1件のみに絞りソートはクライアント側で行う(2026-07-19に実際に発生した不具合と同じパターン)。
      stream: FirebaseFirestore.instance
          .collection('connection_requests')
          .where('pharmacistId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = List<QueryDocumentSnapshot>.from(snap.data!.docs)
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
                Icon(Icons.send_outlined, size: 64, color: Colors.black26),
                SizedBox(height: 16),
                Text('申請はありません\n「施設を探す」から申請してください', textAlign: TextAlign.center, style: TextStyle(color: Colors.black38)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final status = data['status'] as String;
            Color statusColor;
            String statusLabel;
            switch (status) {
              case 'pending':
                statusColor = Colors.orange;
                statusLabel = '承認待ち';
                break;
              case 'approved':
                statusColor = Colors.green;
                statusLabel = '承認済み';
                break;
              case 'rejected':
                statusColor = Colors.red;
                statusLabel = '拒否';
                break;
              default:
                statusColor = Colors.grey;
                statusLabel = status;
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  child: Icon(Icons.business, color: statusColor),
                ),
                title: Text(data['facilityName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('申請日: ${_formatDate(data['createdAt'])}', style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(statusLabel, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)),
                    ),
                    if (status == 'pending') ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                        onPressed: () => onCancel(docs[i].id),
                        tooltip: '取り消す',
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.year}/${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}
