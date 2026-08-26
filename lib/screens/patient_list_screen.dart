import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/user_model.dart';
import '../models/patient_model.dart';
import '../theme/app_theme.dart';
import 'patient_detail_screen.dart';
import 'patient_add_screen.dart';
import 'qr_scanner_screen.dart';

class PatientListScreen extends StatefulWidget {
  final UserModel user;
  const PatientListScreen({super.key, required this.user});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

enum _SortMode { name, room, age }

class _PatientListScreenState extends State<PatientListScreen> {
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.room;
  Timer? _searchDebounce;

  void _showAddPatientDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientAddScreen(user: widget.user)),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final facilityId = widget.user.facilityId;
    return StreamBuilder<Set<String>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('side_effect_checks')
          .where('facilityId', isEqualTo: facilityId)
          .where('hasSideEffect', isEqualTo: true)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => d.get('patientId') as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()),
      builder: (context, sideEffectSnap) {
        final sideEffectPatientIds = sideEffectSnap.data ?? {};
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        foregroundColor: Colors.white,
        title: const Text('入居者一覧'),
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: '並び替え: ${_sortMode == _SortMode.room ? "部屋番号" : _sortMode == _SortMode.name ? "名前" : "年齢"}',
            initialValue: _sortMode,
            onSelected: (v) => setState(() => _sortMode = v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _SortMode.room,
                child: Row(children: [
                  Icon(Icons.meeting_room_outlined, size: 16, color: _sortMode == _SortMode.room ? Colors.green : Colors.black54),
                  const SizedBox(width: 8),
                  Text('部屋番号順', style: TextStyle(fontWeight: _sortMode == _SortMode.room ? FontWeight.bold : FontWeight.normal)),
                  if (_sortMode == _SortMode.room) ...[const Spacer(), const Icon(Icons.check, size: 16, color: Colors.green)],
                ]),
              ),
              PopupMenuItem(
                value: _SortMode.name,
                child: Row(children: [
                  Icon(Icons.sort_by_alpha, size: 16, color: _sortMode == _SortMode.name ? Colors.green : Colors.black54),
                  const SizedBox(width: 8),
                  Text('名前順', style: TextStyle(fontWeight: _sortMode == _SortMode.name ? FontWeight.bold : FontWeight.normal)),
                  if (_sortMode == _SortMode.name) ...[const Spacer(), const Icon(Icons.check, size: 16, color: Colors.green)],
                ]),
              ),
              PopupMenuItem(
                value: _SortMode.age,
                child: Row(children: [
                  Icon(Icons.elderly, size: 16, color: _sortMode == _SortMode.age ? Colors.green : Colors.black54),
                  const SizedBox(width: 8),
                  Text('年齢順', style: TextStyle(fontWeight: _sortMode == _SortMode.age ? FontWeight.bold : FontWeight.normal)),
                  if (_sortMode == _SortMode.age) ...[const Spacer(), const Icon(Icons.check, size: 16, color: Colors.green)],
                ]),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddPatientDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppTheme.canvas,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _searchQuery = v);
                });
              },
              decoration: InputDecoration(
                hintText: '名前・部屋番号で検索',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSub, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('patients')
                  .where('facilityId', isEqualTo: facilityId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final allDocs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final ad = a.data() as Map<String, dynamic>;
                    final bd = b.data() as Map<String, dynamic>;
                    switch (_sortMode) {
                      case _SortMode.name:
                        return ((ad['name'] ?? '') as String).compareTo((bd['name'] ?? '') as String);
                      case _SortMode.age:
                        return ((bd['age'] ?? 0) as int).compareTo((ad['age'] ?? 0) as int);
                      case _SortMode.room:
                        return ((ad['roomNumber'] ?? '') as String).compareTo((bd['roomNumber'] ?? '') as String);
                    }
                  });
                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '') as String;
                  final room = (data['roomNumber'] ?? '') as String;
                  return name.contains(_searchQuery) || room.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline, size: 64, color: Colors.black26),
                        const SizedBox(height: 16),
                        const Text('入居者が登録されていません', style: TextStyle(color: Colors.black38)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showAddPatientDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('入居者を追加'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF388E3C), foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .where('facilityId', isEqualTo: facilityId)
                      .where('type', isEqualTo: '薬切れ')
                      .limit(500)
                      .snapshots(),
                  builder: (context, expirySnap) {
                    if (expirySnap.hasError) {
                      debugPrint('薬切れイベント取得エラー: ${expirySnap.error}');
                    }
                    final expiryEvents = expirySnap.data?.docs ?? [];
                    final now = DateTime.now();
                    final soon = now.add(const Duration(days: 7));

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final patient = PatientModel.fromMap(doc.id, data);
                        final conditions = List<String>.from(data['conditions'] ?? []);
                        final patientName = (data['name'] ?? '') as String;

                        final hasExpiringSoon = expiryEvents.any((ev) {
                          final evData = ev.data() as Map<String, dynamic>;
                          if (!((evData['title'] as String? ?? '').contains(patientName))) return false;
                          final date = (evData['date'] as Timestamp?)?.toDate();
                          if (date == null) return false;
                          return date.isAfter(now.subtract(const Duration(days: 1))) && date.isBefore(soon);
                        });

                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('patients').doc(doc.id)
                              .collection('medicines').snapshots(),
                          builder: (context, medSnap) {
                            final medCount = medSnap.data?.docs.length ?? 0;
                            final isPharmacist = widget.user.isPharmacist;
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient, user: widget.user)),
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.line),
                            ),
                            // 以前は右側に「服薬数・薬切れ・副作用・アレルギー」を縦積みし、
                            // さらにQRボタンと矢印が並んでいて、どれが警告なのか判別できなかった。
                            // 警告は下段に1行でまとめ、色を持つのは警告だけにする。
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppTheme.canvas,
                                  radius: 24,
                                  child: isPharmacist
                                      ? const Icon(Icons.person_outline, color: AppTheme.textSub, size: 22)
                                      : Text(
                                          patient.name.isNotEmpty ? patient.name[0] : '?',
                                          style: const TextStyle(
                                            fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              isPharmacist
                                                  ? (patient.roomNumber.isNotEmpty ? patient.roomNumber : '部屋未設定')
                                                  : patient.name,
                                              style: const TextStyle(
                                                fontSize: 16.5, fontWeight: FontWeight.w700,
                                                color: AppTheme.textMain, letterSpacing: -0.2),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (patient.age > 0) ...[
                                            const SizedBox(width: 8),
                                            Text('${patient.age}歳',
                                                style: const TextStyle(fontSize: 13, color: AppTheme.textSub)),
                                          ],
                                          const SizedBox(width: 10),
                                          // 服薬数は情報であって警告ではないので、色を持たせない
                                          Text('薬 $medCount種',
                                              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSub)),
                                        ],
                                      ),
                                      if (!isPharmacist && patient.roomNumber.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(patient.roomNumber,
                                            style: const TextStyle(fontSize: 12.5, color: AppTheme.textSub)),
                                      ],
                                      if (conditions.isNotEmpty) ...[
                                        const SizedBox(height: 7),
                                        Text(conditions.join('・'),
                                            style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                      if (hasExpiringSoon ||
                                          sideEffectPatientIds.contains(doc.id) ||
                                          patient.allergies.isNotEmpty) ...[
                                        const SizedBox(height: 9),
                                        Wrap(
                                          spacing: 6, runSpacing: 6,
                                          children: [
                                            if (hasExpiringSoon) _AlertTag('薬切れ間近', AppTheme.danger),
                                            if (sideEffectPatientIds.contains(doc.id))
                                              _AlertTag('副作用報告', AppTheme.warn),
                                            if (patient.allergies.isNotEmpty)
                                              _AlertTag('アレルギー', AppTheme.danger),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // カード全体が開くので矢印は外し、別の操作であるQRだけ残す
                                IconButton(
                                  icon: const Icon(Icons.qr_code_2, color: AppTheme.textSub),
                                  tooltip: 'QRコード読み取り',
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => QRScannerScreen(
                                        patientId: doc.id,
                                        patientName: patient.name,
                                        user: widget.user,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPatientDialog(context),
        backgroundColor: const Color(0xFF388E3C),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
      },
    );
  }
}

/// 注意を促すためのタグ。
///
/// 一覧の中で色を持つのはこれだけにしている。服薬数や既往のように
/// 「ただの情報」まで色を付けると、本当に見てほしい警告が埋もれるため。
class _AlertTag extends StatelessWidget {
  final String text;
  final Color color;
  const _AlertTag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
