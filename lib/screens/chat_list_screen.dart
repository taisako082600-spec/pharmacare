import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  final UserModel user;
  const ChatListScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        foregroundColor: Colors.white,
        title: const Text('チャット'),
        elevation: 0,
      ),
      body: user.isPharmacist ? _PharmacistChatList(user: user) : _FacilityChatList(user: user),
    );
  }
}

// ---- 施設スタッフ用 ----
class _FacilityChatList extends StatelessWidget {
  final UserModel user;
  const _FacilityChatList({required this.user});

  @override
  Widget build(BuildContext context) {
    if (user.facilityId.isEmpty) {
      return const _EmptyState(message: '施設に参加していません。\nプロフィールから施設に参加してください。');
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('facilities').doc(user.facilityId).snapshots(),
      builder: (context, facSnap) {
        if (facSnap.hasError) {
          return Center(child: Text('エラー: ${facSnap.error}', style: const TextStyle(color: Colors.red)));
        }
        if (!facSnap.hasData) return const Center(child: CircularProgressIndicator());
        final facData = facSnap.data!.data() as Map<String, dynamic>? ?? {};
        final pharmacistIds = List<String>.from(facData['pharmacistIds'] ?? []);

        return ListView(
          children: [
            _SectionHeader(title: '全体'),
            _RoomTile(
              roomId: '${user.facilityId}_general',
              name: '全体連絡',
              subtitle: '施設スタッフ・担当薬剤師',
              icon: Icons.groups_rounded,
              color: AppTheme.accentDeep,
              user: user,
            ),
            if (pharmacistIds.isNotEmpty) ...[
              _SectionHeader(title: '担当薬剤師'),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where(FieldPath.documentId, whereIn: pharmacistIds)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                    );
                  }
                  if (!snap.hasData) return const SizedBox();
                  return Column(
                    children: snap.data!.docs.map((doc) {
                      final pd = doc.data() as Map<String, dynamic>;
                      return _RoomTile(
                        roomId: '${user.facilityId}_pharmacist_${doc.id}',
                        name: pd['name'] ?? '薬剤師',
                        subtitle: '薬剤師との個別相談',
                        icon: Icons.local_pharmacy_rounded,
                        color: AppTheme.accentDeep,
                        user: user,
                      );
                    }).toList(),
                  );
                },
              ),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text('担当薬剤師が未設定です', style: TextStyle(color: Colors.orange, fontSize: 13))),
                    ],
                  ),
                ),
              ),
            _SectionHeader(title: '入居者別'),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('patients')
                  .where('facilityId', isEqualTo: user.facilityId)
                  .limit(100)
                  .snapshots(),
              builder: (context, patSnap) {
                if (patSnap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('読み込みエラー: ${patSnap.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                  );
                }
                if (!patSnap.hasData) return const SizedBox();
                if (patSnap.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('入居者が登録されていません', style: TextStyle(color: Colors.black38, fontSize: 13)),
                  );
                }
                return Column(
                  children: patSnap.data!.docs.map((doc) {
                    final pd = doc.data() as Map<String, dynamic>;
                    return _RoomTile(
                      roomId: '${user.facilityId}_patient_${doc.id}',
                      name: pd['name'] ?? '',
                      subtitle: pd['roomNumber'] != null && (pd['roomNumber'] as String).isNotEmpty
                          ? '${pd['roomNumber']} · 入居者相談'
                          : '入居者相談',
                      icon: Icons.person_rounded,
                      color: AppTheme.accentDeep,
                      user: user,
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

// ---- 薬剤師用 ----
class _PharmacistChatList extends StatelessWidget {
  final UserModel user;
  const _PharmacistChatList({required this.user});

  @override
  Widget build(BuildContext context) {
    final ids = user.facilityIds.isNotEmpty ? user.facilityIds : (user.facilityId.isNotEmpty ? [user.facilityId] : <String>[]);
    if (ids.isEmpty) {
      return const _EmptyState(message: '担当施設が割り当てられていません。\n施設スタッフから招待コードを受け取ってください。');
    }

    return ListView(
      children: [
        ...ids.map((facilityId) => StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('facilities').doc(facilityId).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('読み込みエラー: ${snap.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
              );
            }
            if (!snap.hasData) return const SizedBox();
            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final facilityName = data['name'] ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(title: facilityName, large: true),
                _RoomTile(
                  roomId: '${facilityId}_general',
                  name: '全体連絡',
                  subtitle: '$facilityName スタッフ全員',
                  icon: Icons.groups_rounded,
                  color: AppTheme.accentDeep,
                  user: user,
                ),
                _RoomTile(
                  roomId: '${facilityId}_pharmacist_${user.uid}',
                  name: '個別相談',
                  subtitle: '$facilityName との直接相談',
                  icon: Icons.chat_bubble_rounded,
                  color: AppTheme.accentDeep,
                  user: user,
                ),
                // 入居者別
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('patients')
                      .where('facilityId', isEqualTo: facilityId)
                      .limit(100)
                      .snapshots(),
                  builder: (context, patSnap) {
                    if (patSnap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('読み込みエラー: ${patSnap.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                      );
                    }
                    if (!patSnap.hasData || patSnap.data!.docs.isEmpty) return const SizedBox();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('入居者別', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
                        ),
                        ...patSnap.data!.docs.map((doc) {
                          final pd = doc.data() as Map<String, dynamic>;
                          return _RoomTile(
                            roomId: '${facilityId}_patient_${doc.id}',
                            name: pd['name'] ?? '',
                            subtitle: pd['roomNumber'] != null && (pd['roomNumber'] as String).isNotEmpty
                                ? '${pd['roomNumber']} · 入居者相談'
                                : '入居者相談',
                            icon: Icons.person_rounded,
                            color: AppTheme.accentDeep,
                            user: user,
                          );
                        }),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        )),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---- 共通ウィジェット ----

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool large;
  const _SectionHeader({required this.title, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, large ? 20 : 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: large ? 14 : 11,
          fontWeight: FontWeight.bold,
          color: large ? Colors.black87 : Colors.grey.shade500,
          letterSpacing: large ? 0 : 0.5,
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final String roomId;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final UserModel user;

  const _RoomTile({
    required this.roomId,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.user,
  });

  String _formatLastTime(Timestamp ts) {
    final dt = ts.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 1) return '昨日';
    if (diff < 7) return '${'月火水木金土日'[dt.weekday - 1]}曜';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('rooms').doc(roomId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              title: Text(name),
              subtitle: Text('エラー: ${snap.error}', style: const TextStyle(color: Colors.red, fontSize: 11)),
            ),
          );
        }
        final roomData = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final lastMessage = roomData['lastMessage'] as String? ?? '';
        final lastSender = roomData['lastSender'] as String? ?? '';
        final lastSenderUid = roomData['lastSenderUid'] as String?;
        final lastMessageAt = roomData['lastMessageAt'] as Timestamp?;
        final lastReadMap = roomData['lastRead'] as Map<String, dynamic>?;
        final lastReadAt = lastReadMap?[user.uid] as Timestamp?;

        // 未読判定：最終送信者が自分以外 かつ 未読
        final hasUnread = lastMessage.isNotEmpty &&
            lastSenderUid != user.uid &&
            (lastReadAt == null || (lastMessageAt != null && lastMessageAt.compareTo(lastReadAt) > 0));

        final displayMessage = lastMessage.isNotEmpty
            ? (lastSenderUid == user.uid ? 'あなた: $lastMessage' : '$lastSender: $lastMessage')
            : subtitle;

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(user: user, roomId: roomId, roomName: name)),
          ),
          child: Container(
            color: hasUnread ? color.withValues(alpha: 0.04) : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      radius: 26,
                      child: Icon(icon, color: color, size: 24),
                    ),
                    if (hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600, fontSize: 15),
                            ),
                          ),
                          if (lastMessageAt != null)
                            Text(
                              _formatLastTime(lastMessageAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: hasUnread ? color : Colors.grey.shade400,
                                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasUnread ? Colors.black87 : Colors.grey.shade500,
                          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black38, fontSize: 14, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
