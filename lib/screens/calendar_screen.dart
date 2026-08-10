import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class CalendarScreen extends StatefulWidget {
  final UserModel user;
  const CalendarScreen({super.key, required this.user});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ValueNotifier<DateTime?> _selectedDayNotifier;
  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDayNotifier = ValueNotifier<DateTime?>(null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _selectedDayNotifier.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.user.isPharmacist || widget.user.isCareWorker;

  List<String> get _facilityIds {
    if (widget.user.facilityIds.isNotEmpty) return widget.user.facilityIds;
    if (widget.user.facilityId.isNotEmpty) return [widget.user.facilityId];
    return [];
  }

  void _showAddEventDialog({DateTime? initialDate}) {
    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();
    DateTime selectedDate = initialDate ?? _selectedDayNotifier.value ?? DateTime.now();
    String selectedType = '訪問';
    // 薬剤師が複数施設の場合はドロップダウンで選択、そうでなければ user.facilityId を使用
    String selectedFacilityId = widget.user.facilityId;
    String selectedFacilityName = widget.user.facilityName;

    final typeOptions = [
      {'value': '訪問', 'label': '薬剤師訪問', 'color': Colors.purple},
      {'value': '処方', 'label': '処方・調剤', 'color': Colors.blue},
      {'value': '受診', 'label': '受診', 'color': Colors.teal},
      {'value': 'フォロー', 'label': 'フォローアップ', 'color': Colors.orange},
      {'value': '薬切れ', 'label': '薬切れ予定', 'color': Colors.red},
      {'value': 'その他', 'label': 'その他', 'color': Colors.grey},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('予定を追加', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2028),
                    );
                    if (picked != null) setModal(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Color(0xFFE65100)),
                        const SizedBox(width: 10),
                        Text(
                          '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('種別', style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: typeOptions.map((t) => ChoiceChip(
                    label: Text(t['label'] as String),
                    selected: selectedType == t['value'],
                    onSelected: (_) => setModal(() => selectedType = t['value'] as String),
                    selectedColor: t['color'] as Color,
                    labelStyle: TextStyle(
                      color: selectedType == t['value'] ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                if (widget.user.isPharmacist && _facilityIds.length > 1) ...[
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('facilities')
                        .where(FieldPath.documentId, whereIn: _facilityIds)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
                      final facilities = snap.data!.docs;
                      return DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: selectedFacilityId.isNotEmpty ? selectedFacilityId : null,
                        decoration: const InputDecoration(labelText: '対象施設', border: OutlineInputBorder()),
                        items: facilities.map((d) {
                          final data = d.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: d.id,
                            child: Text(data['name'] ?? ''),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null && v.isNotEmpty) {
                            setModal(() => selectedFacilityId = v);
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'タイトル*', border: OutlineInputBorder()),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subtitleCtrl,
                  decoration: const InputDecoration(labelText: 'メモ（場所・時間など）', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('タイトルを入力してください'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      if (selectedFacilityId.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('施設を選択してください'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      try {
                        await FirebaseFirestore.instance.collection('events').add({
                          'title': titleCtrl.text.trim(),
                          'subtitle': subtitleCtrl.text.trim(),
                          'type': selectedType,
                          'date': Timestamp.fromDate(DateTime(selectedDate.year, selectedDate.month, selectedDate.day)),
                          'facilityId': selectedFacilityId,
                          'facilityName': selectedFacilityName,
                          'createdBy': widget.user.uid,
                          'createdByName': widget.user.name,
                          'createdByRole': widget.user.role,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('予定を追加しました'), backgroundColor: Colors.green),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('追加する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case '訪問': return Colors.purple;
      case '処方': return Colors.blue;
      case '受診': return Colors.teal;
      case 'フォロー': return Colors.orange;
      case '薬切れ': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_facilityIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFE65100), foregroundColor: Colors.white, title: const Text('カレンダー')),
        body: const Center(child: Text('施設が設定されていません', style: TextStyle(color: Colors.black38))),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('facilityId', whereIn: _facilityIds)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: AppBar(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              title: const Text('カレンダー'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('エラーが発生しました', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${snap.error}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('リトライ'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: AppBar(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              title: const Text('カレンダー'),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // クライアント側でソート（複合インデックスが不要）
        final allEventsDocs = snap.data!.docs.toList();
        allEventsDocs.sort((a, b) {
          final dateA = (a.data() as Map<String, dynamic>)['date'] as Timestamp;
          final dateB = (b.data() as Map<String, dynamic>)['date'] as Timestamp;
          return dateA.compareTo(dateB);
        });
        final allEvents = allEventsDocs;

        List<QueryDocumentSnapshot> eventsForDay(DateTime day) => allEvents.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final date = (data['date'] as Timestamp).toDate();
          return date.year == day.year && date.month == day.month && date.day == day.day;
        }).toList();

        final upcoming = allEvents.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final date = (data['date'] as Timestamp).toDate();
          return date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
        }).toList();

        final daysInMonth = DateUtils.getDaysInMonth(_focusedDay.year, _focusedDay.month);
        final firstWeekday = DateTime(_focusedDay.year, _focusedDay.month, 1).weekday % 7;

        final soon = DateTime.now().add(const Duration(days: 7));
        final expiringMeds = allEvents.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['type'] != '薬切れ') return false;
          final date = (data['date'] as Timestamp).toDate();
          return date.isAfter(DateTime.now().subtract(const Duration(days: 1))) &&
              date.isBefore(soon);
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            backgroundColor: const Color(0xFFE65100),
            foregroundColor: Colors.white,
            title: const Text('カレンダー'),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [Tab(text: 'カレンダー'), Tab(text: '一覧')],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // カレンダービュー
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (expiringMeds.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
                                    const Icon(Icons.warning_amber, color: Colors.red, size: 16),
                                    const SizedBox(width: 6),
                                    Text('7日以内に薬切れ（${expiringMeds.length}件）',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ...expiringMeds.take(3).map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final date = (data['date'] as Timestamp).toDate();
                                  final diff = date.difference(DateTime.now()).inDays;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text('・${data['subtitle'] ?? ''} (${diff == 0 ? '本日' : '$diff日後'})',
                                        style: const TextStyle(fontSize: 12, color: Colors.red)),
                                  );
                                }),
                              ],
                            ),
                          ),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)),
                                  ),
                                  Text('${_focusedDay.year}年${_focusedDay.month}月',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: ['日', '月', '火', '水', '木', '金', '土'].asMap().entries.map((e) => Expanded(
                                  child: Center(
                                    child: Text(e.value, style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.bold,
                                      color: e.key == 0 ? Colors.red.shade400 : e.key == 6 ? Colors.blue.shade400 : Colors.black54,
                                    )),
                                  ),
                                )).toList(),
                              ),
                              const SizedBox(height: 8),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.9),
                                itemCount: daysInMonth + firstWeekday,
                                itemBuilder: (context, index) {
                                  if (index < firstWeekday) return const SizedBox();
                                  final day = index - firstWeekday + 1;
                                  final date = DateTime(_focusedDay.year, _focusedDay.month, day);
                                  final isToday = DateUtils.isSameDay(date, DateTime.now());
                                  final dayEvents = eventsForDay(date);
                                  return ValueListenableBuilder<DateTime?>(
                                    valueListenable: _selectedDayNotifier,
                                    builder: (context, selectedDay, _) {
                                      final isSelected = DateUtils.isSameDay(date, selectedDay);
                                      return GestureDetector(
                                        onTap: () => _selectedDayNotifier.value = date,
                                        onLongPress: _canEdit ? () {
                                          _selectedDayNotifier.value = date;
                                          _showAddEventDialog(initialDate: date);
                                        } : null,
                                    child: Container(
                                      margin: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFFE65100) : isToday ? const Color(0xFFFBE9E7) : null,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text('$day', style: TextStyle(
                                            fontSize: 13,
                                            color: isSelected ? Colors.white : isToday ? const Color(0xFFE65100) : Colors.black87,
                                            fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                                          )),
                                          if (dayEvents.isNotEmpty)
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: dayEvents.take(3).map((doc) {
                                                final data = doc.data() as Map<String, dynamic>;
                                                return Container(
                                                  width: 5, height: 5, margin: const EdgeInsets.only(right: 1),
                                                  decoration: BoxDecoration(
                                                    color: isSelected ? Colors.white : _typeColor(data['type'] ?? ''),
                                                    shape: BoxShape.circle,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverFillRemaining(
                    child: ValueListenableBuilder<DateTime?>(
                      valueListenable: _selectedDayNotifier,
                      builder: (context, selectedDay, _) {
                        return selectedDay == null
                            ? const Center(child: Text('日付を選択してください', style: TextStyle(color: Colors.black38)))
                            : _SelectedDayEventsWidget(
                                allEvents: allEvents,
                                selectedDay: selectedDay,
                                canEdit: _canEdit,
                                typeColor: _typeColor,
                                onAddEvent: () => _showAddEventDialog(initialDate: selectedDay),
                              );
                      },
                    ),
                  ),
                ],
              ),
              // 一覧ビュー
              upcoming.isEmpty
                  ? const Center(child: Text('予定はありません', style: TextStyle(color: Colors.black38)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: upcoming.length,
                      itemBuilder: (context, i) {
                        final data = upcoming[i].data() as Map<String, dynamic>;
                        final date = (data['date'] as Timestamp).toDate();
                        final showHeader = i == 0 || (() {
                          final prev = (upcoming[i - 1].data() as Map<String, dynamic>)['date'] as Timestamp;
                          final prevDate = prev.toDate();
                          return !(prevDate.year == date.year && prevDate.month == date.month && prevDate.day == date.day);
                        })();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  '${date.month}月${date.day}日（${['月', '火', '水', '木', '金', '土', '日'][date.weekday - 1]}）',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
                                ),
                              ),
                            _EventCard(doc: upcoming[i], canEdit: _canEdit, typeColor: _typeColor),
                            const SizedBox(height: 6),
                          ],
                        );
                      },
                    ),
            ],
          ),
          floatingActionButton: _canEdit
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddEventDialog(),
                  backgroundColor: const Color(0xFFE65100),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('予定を追加', style: TextStyle(color: Colors.white)),
                )
              : null,
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final bool canEdit;
  final Color Function(String) typeColor;
  const _EventCard({required this.doc, required this.canEdit, required this.typeColor});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final color = typeColor(data['type'] ?? '');
    return Dismissible(
      key: Key(doc.id),
      direction: canEdit ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('予定を削除'),
            content: Text('「${data['title']}」を削除しますか？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('削除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => doc.reference.delete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  if ((data['subtitle'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(data['subtitle'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 12, color: Colors.black38),
                      const SizedBox(width: 3),
                      Text(data['createdByName'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                      if ((data['facilityName'] ?? '').isNotEmpty) ...[
                        const Text(' · ', style: TextStyle(fontSize: 11, color: Colors.black38)),
                        Text(data['facilityName'], style: const TextStyle(fontSize: 11, color: Colors.black38)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(data['type'] ?? '', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDayEventsWidget extends StatelessWidget {
  final List<QueryDocumentSnapshot> allEvents;
  final DateTime selectedDay;
  final bool canEdit;
  final Color Function(String) typeColor;
  final VoidCallback onAddEvent;

  const _SelectedDayEventsWidget({
    required this.allEvents,
    required this.selectedDay,
    required this.canEdit,
    required this.typeColor,
    required this.onAddEvent,
  });

  @override
  Widget build(BuildContext context) {
    final selectedEvents = allEvents.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final date = (data['date'] as Timestamp).toDate();
      return date.year == selectedDay.year &&
          date.month == selectedDay.month &&
          date.day == selectedDay.day;
    }).toList();

    return selectedEvents.isEmpty
        ? const Center(child: Text('この日の予定はありません', style: TextStyle(color: Colors.black38)))
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${selectedDay.month}月${selectedDay.day}日', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (canEdit)
                        GestureDetector(
                          onTap: onAddEvent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: const Color(0xFFE65100), borderRadius: BorderRadius.circular(6)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 16, color: Colors.white),
                                SizedBox(width: 4),
                                Text('追加', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ...selectedEvents.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final color = typeColor(data['type'] ?? '');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(left: BorderSide(color: color, width: 4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          if ((data['subtitle'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(data['subtitle'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(data['type'] ?? '', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(data['createdByName'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  ],
                                ),
                              ),
                              if (canEdit)
                                GestureDetector(
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('予定を削除'),
                                        content: Text('「${data['title']}」を削除しますか？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                            child: const Text('削除'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      doc.reference.delete();
                                    }
                                  },
                                  child: const Icon(Icons.close, size: 18, color: Colors.black38),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),
          );
  }
}
