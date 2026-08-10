import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';

class AdminChatMonitorScreen extends StatelessWidget {
  final UserModel user;
  const AdminChatMonitorScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: const Text('チャット監視'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.visibility, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('閲覧のみ', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').orderBy('name').snapshots(),
        builder: (context, facSnap) {
          if (!facSnap.hasData) return const Center(child: CircularProgressIndicator());
          final facilities = facSnap.data!.docs;
          if (facilities.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business_outlined, size: 64, color: Colors.black26),
                  SizedBox(height: 16),
                  Text('施設が登録されていません', style: TextStyle(color: Colors.black38)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: facilities.length,
            itemBuilder: (context, i) {
              final fac = facilities[i];
              final facData = fac.data() as Map<String, dynamic>;
              return _FacilitySection(facilityId: fac.id, facilityName: facData['name'] ?? '');
            },
          );
        },
      ),
    );
  }
}

class _FacilitySection extends StatelessWidget {
  final String facilityId;
  final String facilityName;
  const _FacilitySection({required this.facilityId, required this.facilityName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 施設ヘッダー
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF7B1FA2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.business, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(facilityName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ),

        // 全体連絡
        _RoomTile(
          roomId: '${facilityId}_general',
          roomName: '全体連絡',
          icon: Icons.groups_rounded,
          color: const Color(0xFF1976D2),
        ),

        // 担当薬剤師の個別相談
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: '薬剤師')
              .where('facilityIds', arrayContains: facilityId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) debugPrint('担当薬剤師取得エラー: ${snap.error}');
            if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
            return Column(
              children: snap.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _RoomTile(
                  roomId: '${facilityId}_pharmacist_${doc.id}',
                  roomName: '個別相談（${data['name'] ?? '薬剤師'}）',
                  icon: Icons.local_pharmacy_rounded,
                  color: const Color(0xFF1976D2),
                );
              }).toList(),
            );
          },
        ),

        // 入居者別チャット
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('patients')
              .where('facilityId', isEqualTo: facilityId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
            return Column(
              children: snap.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _RoomTile(
                  roomId: '${facilityId}_patient_${doc.id}',
                  roomName: '${data['name'] ?? ''}さん',
                  icon: Icons.person_rounded,
                  color: const Color(0xFF388E3C),
                  subtitle: data['roomNumber'] != null && (data['roomNumber'] as String).isNotEmpty
                      ? data['roomNumber'] as String
                      : null,
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RoomTile extends StatelessWidget {
  final String roomId;
  final String roomName;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const _RoomTile({required this.roomId, required this.roomName, required this.icon, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('rooms').doc(roomId).snapshots(),
      builder: (context, snap) {
        final roomData = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final lastMessage = roomData['lastMessage'] as String? ?? '';
        final lastSender = roomData['lastSender'] as String? ?? '';
        final lastMessageAt = roomData['lastMessageAt'] as Timestamp?;

        String timeStr = '';
        if (lastMessageAt != null) {
          final dt = lastMessageAt.toDate().toLocal();
          final now = DateTime.now();
          if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
            timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } else {
            timeStr = '${dt.month}/${dt.day}';
          }
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _ChatMonitorDetail(roomId: roomId, roomName: roomName)),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  radius: 22,
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(roomName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        lastMessage.isNotEmpty ? '$lastSender: $lastMessage' : (subtitle ?? 'メッセージなし'),
                        style: TextStyle(fontSize: 12, color: lastMessage.isNotEmpty ? Colors.black54 : Colors.black38),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (timeStr.isNotEmpty)
                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.black38))
                else
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatMonitorDetail extends StatelessWidget {
  final String roomId;
  final String roomName;
  const _ChatMonitorDetail({required this.roomId, required this.roomName});

  Color _roleColor(String role) {
    switch (role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      default: return const Color(0xFF7B1FA2);
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: Text(roomName),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.visibility, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('閲覧のみ', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rooms').doc(roomId)
            .collection('messages')
            .orderBy('createdAt')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final messages = snapshot.data!.docs;
          if (messages.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 16),
                  Text('メッセージはありません', style: TextStyle(color: Colors.black38)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final data = messages[index].data() as Map<String, dynamic>;
              final role = data['role'] as String? ?? '';
              final color = _roleColor(role);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: color,
                      radius: 18,
                      child: Text(
                        (data['sender'] ?? '?').toString().isNotEmpty ? data['sender'].toString()[0] : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('${data['sender'] ?? ''}', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text(role, style: TextStyle(fontSize: 10, color: color)),
                              ),
                              const SizedBox(width: 8),
                              Text(_formatTime(data['createdAt'] as Timestamp?), style: const TextStyle(fontSize: 10, color: Colors.black38)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
                            ),
                            child: Text(data['text'] ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
