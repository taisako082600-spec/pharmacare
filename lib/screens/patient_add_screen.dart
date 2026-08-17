import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/audit_service.dart';

class PatientAddScreen extends StatefulWidget {
  final UserModel user;
  const PatientAddScreen({super.key, required this.user});

  @override
  State<PatientAddScreen> createState() => _PatientAddScreenState();
}

class _PatientAddScreenState extends State<PatientAddScreen> {
  final nameCtrl = TextEditingController();
  final roomCtrl = TextEditingController();
  final condCtrl = TextEditingController();
  DateTime? _birthDate;
  bool _loading = false;
  String? _error;
  bool _noRoom = false;

  int _calcAge(DateTime birth) {
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
    return age;
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1950, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: '生年月日を選択',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<String> _generateRoomId() async {
    final snap = await FirebaseFirestore.instance
        .collection('patients')
        .where('facilityId', isEqualTo: widget.user.facilityId)
        .get();
    // P番号が付いているものの最大値を探す
    int maxNum = 0;
    for (final doc in snap.docs) {
      final room = (doc.data()['roomNumber'] ?? '') as String;
      final match = RegExp(r'^P(\d+)$').firstMatch(room);
      if (match != null) {
        final n = int.tryParse(match.group(1)!) ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    return 'P${(maxNum + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _addPatient() async {
    final name = nameCtrl.text.trim();
    final roomInput = roomCtrl.text.trim();

    if (name.isEmpty || _birthDate == null) {
      setState(() => _error = '氏名と生年月日は必須です');
      return;
    }
    if (!_noRoom && roomInput.isEmpty) {
      setState(() => _error = '部屋番号を入力してください。部屋番号がない場合は「部屋番号なし」を選択してください');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final conditions = condCtrl.text.trim().isEmpty
          ? <String>[]
          : condCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      final birthStr = '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}';
      final roomNumber = _noRoom ? await _generateRoomId() : roomInput;

      final created = await FirebaseFirestore.instance.collection('patients').add({
        'name': name,
        'birthDate': birthStr,
        'age': _calcAge(_birthDate!),
        'roomNumber': roomNumber,
        'conditions': conditions,
        'facilityId': widget.user.facilityId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 医療情報の新規作成の証跡(ガイドライン システム運用編 17①)
      await AuditService().log(
        userId: widget.user.uid,
        userName: widget.user.name,
        action: AuditService.actionCreate,
        collection: 'patients',
        documentId: created.id,
        facilityId: widget.user.facilityId,
        reason: '入居者の新規登録',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_noRoom ? '「$name」を追加しました（ID: $roomNumber）' : '「$name」を追加しました'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'エラーが発生しました: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = _birthDate != null ? _calcAge(_birthDate!) : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF388E3C),
        foregroundColor: Colors.white,
        title: const Text('入居者を追加'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildField(
              controller: nameCtrl,
              label: '氏名*',
              hint: '例: 田中 太郎',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),

            // 生年月日
            GestureDetector(
              onTap: _pickBirthDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cake_outlined, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _birthDate != null
                            ? '${_birthDate!.year}年${_birthDate!.month}月${_birthDate!.day}日'
                            : '生年月日を選択*',
                        style: TextStyle(
                          fontSize: 16,
                          color: _birthDate != null ? Colors.black87 : Colors.grey.shade500,
                        ),
                      ),
                    ),
                    if (age != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                        child: Text('$age歳', style: const TextStyle(fontSize: 13, color: Color(0xFF388E3C), fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.black38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 部屋番号（必須）
            if (!_noRoom)
              _buildField(
                controller: roomCtrl,
                label: '部屋番号*',
                hint: '例: 101号室',
                icon: Icons.meeting_room_outlined,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1976D2).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tag, color: Color(0xFF1976D2), size: 20),
                    const SizedBox(width: 12),
                    const Text('登録時にIDを自動発番します（例: P001）',
                        style: TextStyle(fontSize: 14, color: Color(0xFF1976D2))),
                  ],
                ),
              ),
            const SizedBox(height: 6),

            // 部屋番号なしトグル
            GestureDetector(
              onTap: () {
                setState(() {
                  _noRoom = !_noRoom;
                  if (_noRoom) roomCtrl.clear();
                });
              },
              child: Row(
                children: [
                  Checkbox(
                    value: _noRoom,
                    onChanged: (v) {
                      setState(() {
                        _noRoom = v ?? false;
                        if (_noRoom) roomCtrl.clear();
                      });
                    },
                    activeColor: const Color(0xFF1976D2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Text('部屋番号なし（IDを自動発番）', style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildField(
              controller: condCtrl,
              label: '既往歴・疾患 (カンマ区切り)',
              hint: '例: 高血圧, 糖尿病, 心疾患',
              icon: Icons.health_and_safety_outlined,
              maxLines: 2,
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _addPatient,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF388E3C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('追加する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    roomCtrl.dispose();
    condCtrl.dispose();
    super.dispose();
  }
}
