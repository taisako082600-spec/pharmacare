import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

class AdminFacilitiesScreen extends StatelessWidget {
  final UserModel user;
  const AdminFacilitiesScreen({super.key, required this.user});

  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('施設を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '施設名*', border: OutlineInputBorder()), autofocus: true),
            const SizedBox(height: 10),
            TextField(controller: addressController, decoration: const InputDecoration(labelText: '住所', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: '電話番号', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await FirestoreService().addFacility({'name': name, 'address': addressController.text.trim(), 'phone': phoneController.text.trim()});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  void _showPharmacistAssignDialog(BuildContext context, String facilityId, String facilityName, List<String> currentPharmacistIds) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$facilityName\n担当薬剤師'),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: '薬剤師').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final pharmacists = snapshot.data!.docs;
              if (pharmacists.isEmpty) return const Text('薬剤師が登録されていません');
              return ListView.builder(
                shrinkWrap: true,
                itemCount: pharmacists.length,
                itemBuilder: (context, index) {
                  final doc = pharmacists[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isAssigned = currentPharmacistIds.contains(doc.id);
                  return CheckboxListTile(
                    title: Text(data['name'] ?? ''),
                    subtitle: Text(data['email'] ?? ''),
                    value: isAssigned,
                    onChanged: (val) async {
                      if (val == true) {
                        await FirestoreService().assignPharmacistToFacility(facilityId, doc.id);
                      } else {
                        await FirestoreService().unassignPharmacistFromFacility(facilityId, doc.id);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        title: const Text('施設管理'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final facilities = snapshot.data!.docs;
          if (facilities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.business_outlined, size: 64, color: Colors.black26),
                  const SizedBox(height: 16),
                  const Text('施設が登録されていません', style: TextStyle(color: Colors.black38)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('施設を追加'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: facilities.length,
            itemBuilder: (context, index) {
              final doc = facilities[index];
              final data = doc.data() as Map<String, dynamic>;
              final pharmacistIds = List<String>.from(data['pharmacistIds'] ?? []);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    ListTile(
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
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('施設を削除'),
                            content: Text('「${data['name']}」を削除しますか？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                              ElevatedButton(
                                onPressed: () async {
                                  // スタッフ・患者が残っている施設を削除すると、それらのfacilityId参照が
                                  // 全て宙に浮いてしまう(チャット・カレンダー等も含む)。安全のため、
                                  // 所属者がいる間は削除させない(2026-07-19、施設削除に無条件の
                                  // カスケード処理が一切ないことが判明したため追加したガード)。
                                  final messenger = ScaffoldMessenger.of(context);
                                  final staffSnap = await FirebaseFirestore.instance
                                      .collection('users').where('facilityId', isEqualTo: doc.id).limit(1).get();
                                  final patientSnap = await FirebaseFirestore.instance
                                      .collection('patients').where('facilityId', isEqualTo: doc.id).limit(1).get();
                                  if (staffSnap.docs.isNotEmpty || patientSnap.docs.isNotEmpty) {
                                    if (context.mounted) Navigator.pop(context);
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('スタッフまたは患者が登録されている施設は削除できません。先に全員を削除・移動してください。'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }
                                  await doc.reference.delete();
                                  if (context.mounted) Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                child: const Text('削除'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // 担当薬剤師エリア
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_pharmacy, size: 14, color: Color(0xFF1976D2)),
                                  const SizedBox(width: 6),
                                  Text('担当薬剤師 ${pharmacistIds.length}名', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: () => _showPharmacistAssignDialog(context, doc.id, data['name'] ?? '', pharmacistIds),
                                icon: const Icon(Icons.edit, size: 14),
                                label: const Text('編集', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          if (pharmacistIds.isEmpty)
                            const Text('担当薬剤師が未設定です', style: TextStyle(fontSize: 12, color: Colors.orange))
                          else
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('users')
                                  .where('role', isEqualTo: '薬剤師')
                                  .where('facilityIds', arrayContains: doc.id)
                                  .snapshots(),
                              builder: (context, pharSnap) {
                                if (pharSnap.hasError) debugPrint('担当薬剤師一覧取得エラー: ${pharSnap.error}');
                                if (!pharSnap.hasData) return const SizedBox();
                                return Wrap(
                                  spacing: 6,
                                  children: pharSnap.data!.docs.map((p) {
                                    final pd = p.data() as Map<String, dynamic>;
                                    return Chip(
                                      avatar: const CircleAvatar(backgroundColor: Color(0xFF1976D2), child: Icon(Icons.person, size: 12, color: Colors.white)),
                                      label: Text(pd['name'] ?? '', style: const TextStyle(fontSize: 12)),
                                      backgroundColor: const Color(0xFFE3F2FD),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                          // スタッフ数
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('users').where('facilityId', isEqualTo: doc.id).snapshots(),
                            builder: (context, staffSnap) {
                              final count = staffSnap.data?.docs.length ?? 0;
                              return Row(
                                children: [
                                  const Icon(Icons.people, size: 14, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text('スタッフ $count名', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              );
                            },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        backgroundColor: const Color(0xFF7B1FA2),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('施設を追加', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
