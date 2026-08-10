import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final UserModel user;
  final String roomId;
  final String roomName;
  const ChatScreen({super.key, required this.user, required this.roomId, required this.roomName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _firstLoad = true;

  // roomIdは常に{facilityId}_general / {facilityId}_patient_{id} / {facilityId}_pharmacist_{uid}
  // の形式なので、そこから取り出すのが正しい。widget.user.facilityId(単一の主施設)を使うと、
  // 複数施設に所属する薬剤師が自分の主施設以外のルームを開いた瞬間、そのルームのfacilityIdが
  // 間違った施設IDで上書きされ、本来の施設スタッフ全員がそのルームにアクセスできなくなる
  // 重大なデータ破損バグになっていた(2026-07-19に発見)。
  String get _roomFacilityId => widget.roomId.split('_').first;

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markAsRead() {
    // facilityIdも必ず含める。メッセージを一度も送信していないルームをこの
    // 既読記録だけで作成した場合にfacilityIdが欠落し、Firestoreルールの
    // belongsToFacility(resource.data.facilityId)判定が恒久的に失敗する不具合があったため。
    _db.collection('rooms').doc(widget.roomId).set({
      'facilityId': _roomFacilityId,
      'lastRead': {widget.user.uid: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(max, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(max);
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    final batch = _db.batch();
    final msgRef = _db.collection('rooms').doc(widget.roomId).collection('messages').doc();
    batch.set(msgRef, {
      'text': text,
      'sender': widget.user.name,
      'senderUid': widget.user.uid,
      'role': widget.user.role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final roomRef = _db.collection('rooms').doc(widget.roomId);
    batch.set(roomRef, {
      'facilityId': _roomFacilityId,
      'lastMessage': text,
      'lastSender': widget.user.name,
      'lastSenderUid': widget.user.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastRead': {widget.user.uid: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
    await batch.commit();

    Future.delayed(const Duration(milliseconds: 150), () => _scrollToBottom(animate: true));
  }

  Color _roleColor(String role) {
    switch (role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      default: return const Color(0xFF607D8B);
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return '今日';
    if (diff == 1) return '昨日';
    return '${dt.month}月${dt.day}日（${'月火水木金土日'[dt.weekday - 1]}）';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              radius: 18,
              child: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.roomName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Text('リアルタイム', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('rooms')
                  .doc(widget.roomId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!.docs;

                if (!snapshot.hasData || messages.isEmpty) {
                  return snapshot.hasData && messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                                child: Icon(Icons.chat_bubble_outline, size: 40, color: Colors.grey.shade400),
                              ),
                              const SizedBox(height: 16),
                              const Text('最初のメッセージを送りましょう', style: TextStyle(color: Colors.black38, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: 5,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: index % 2 == 0 ? MainAxisAlignment.start : MainAxisAlignment.end,
                              children: [
                                if (index % 2 == 0) ...[
                                  Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  width: 200,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                if (index % 2 != 0) const SizedBox(width: 44),
                              ],
                            ),
                          ),
                        );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markAsRead();
                  if (_firstLoad) {
                    _firstLoad = false;
                    _scrollToBottom();
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final isMe = data['senderUid'] == widget.user.uid ||
                        (data['senderUid'] == null && data['sender'] == widget.user.name);
                    final sender = data['sender'] as String? ?? '';
                    final role = data['role'] as String? ?? '';
                    final color = _roleColor(role);
                    final time = _formatTime(data['createdAt'] as Timestamp?);
                    final ts = data['createdAt'] as Timestamp?;
                    final msgDate = ts?.toDate().toLocal();

                    bool showDateSeparator = false;
                    if (msgDate != null) {
                      if (index == 0) {
                        showDateSeparator = true;
                      } else {
                        final prevTs = (messages[index - 1].data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                        if (prevTs != null && !_isSameDay(prevTs.toDate().toLocal(), msgDate)) {
                          showDateSeparator = true;
                        }
                      }
                    }

                    return Column(
                      children: [
                        if (showDateSeparator && msgDate != null)
                          _DateSeparator(label: _formatDateLabel(msgDate)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 2),
                          child: Row(
                            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                CircleAvatar(
                                  backgroundColor: color,
                                  radius: 18,
                                  child: Text(
                                    sender.isNotEmpty ? sender[0] : '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else
                                const SizedBox(width: 44),
                              Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4, left: 4),
                                      child: Row(
                                        children: [
                                          Text(sender, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                            child: Text(role, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (isMe) ...[
                                        Text(time, style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                        const SizedBox(width: 4),
                                      ],
                                      ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFF1976D2) : Colors.white,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: Radius.circular(isMe ? 18 : 4),
                                              bottomRight: Radius.circular(isMe ? 4 : 18),
                                            ),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))],
                                          ),
                                          child: Text(
                                            data['text'] ?? '',
                                            style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15, height: 1.45),
                                          ),
                                        ),
                                      ),
                                      if (!isMe) ...[
                                        const SizedBox(width: 4),
                                        Text(time, style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'メッセージを入力...',
                        hintStyle: const TextStyle(color: Colors.black38),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(color: Color(0xFF1976D2), shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
      ),
    );
  }
}
