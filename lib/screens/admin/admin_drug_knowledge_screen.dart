import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../services/ai_drug_service.dart';

/// 薬剤知識ベース管理画面（②医薬品注意点表示 B案）。
/// 3つのキューをタブで管理する:
///   1. 名寄せ待ち (unmatched_drug_names) — 自由入力の薬剤名を一般名に確定する
///   2. 添付文書取得待ち (drug_knowledge_base status=manual_needed) — 自動取得に失敗した分を手動整備する
///   3. 取得待ちリスト (drug_fetch_requests) — 患者が実際に登録した薬剤のうち、
///      drug_knowledge_baseにまだ1件もエントリがないもの。「取得実行」でPMDA自動取得を起動する
/// あいまいな名寄せ・取得失敗の判断はLLMに任せず、taiさんがここで確定する
/// (medication_caution_b_plan_design.md の3層フォールバック構造の「管理者レビュー」部分)。
class AdminDrugKnowledgeScreen extends StatefulWidget {
  final UserModel user;
  const AdminDrugKnowledgeScreen({super.key, required this.user});

  @override
  State<AdminDrugKnowledgeScreen> createState() => _AdminDrugKnowledgeScreenState();
}

class _AdminDrugKnowledgeScreenState extends State<AdminDrugKnowledgeScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('薬剤知識ベース管理'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '薬剤名 確認待ち'),
            Tab(text: '添付文書取得待ち'),
            Tab(text: '取得待ちリスト'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UnmatchedDrugNamesTab(),
          _ManualLabelNeededTab(),
          _FetchPendingTab(),
        ],
      ),
    );
  }
}

// ─── 名寄せ待ちタブ ───────────────────────────────────────────────

class _UnmatchedDrugNamesTab extends StatelessWidget {
  Future<void> _resolve(BuildContext context, String docId, String rawInput) async {
    final controller = TextEditingController();
    final generic = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('一般名を確定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('入力文字列: "$rawInput"', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '正しい一般名（有効成分名）',
                hintText: '例: ロキソプロフェンナトリウム水和物',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (generic == null || generic.isEmpty) return;

    // drug_name_aliases に永続保存（正規化済み入力文字列がキー）→ 以後同じ表記は二度と聞かれない
    await FirebaseFirestore.instance.collection('drug_name_aliases').doc(docId).set({
      'genericName': generic,
      'resolvedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('unmatched_drug_names').doc(docId).update({
      'status': 'resolved',
      'resolvedGenericName': generic,
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$rawInput」→「$generic」として確定しました'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // createdAtでのorderByは複合インデックスが必要になり、未作成だとクエリがエラーのまま
      // 無限ローディングになる(snapshot.hasErrorを見ていなかったため気づけなかった不具合)。
      // 取得後にクライアント側でソートする。
      stream: FirebaseFirestore.instance
          .collection('unmatched_drug_names')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs)
          ..sort((a, b) {
            final at = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bt = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (at == null || bt == null) return 0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('確認待ちの薬剤名はありません', style: TextStyle(color: Colors.black54)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final rawInput = data['rawInput'] as String? ?? '';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.orange),
                title: Text(rawInput),
                subtitle: Text('正規化後: ${data['normalizedInput'] ?? ''}'),
                trailing: ElevatedButton(
                  onPressed: () => _resolve(context, doc.id, rawInput),
                  child: const Text('確定する'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── 添付文書取得待ちタブ ─────────────────────────────────────────

class _ManualLabelNeededTab extends StatelessWidget {
  static const _categoryLabels = {
    'renal_impairment': '9.2 腎機能障害患者',
    'hepatic_impairment': '9.3 肝機能障害患者',
    'elderly': '9.8 高齢者',
    'important_precautions': '8 重要な基本的注意',
    'major_adverse_reactions': '11.1 重大な副作用',
  };

  Future<void> _resolveManually(BuildContext context, String genericName) async {
    final controllers = {
      for (final key in _categoryLabels.keys) key: TextEditingController(),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('「$genericName」の添付文書を手動登録'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '添付文書の該当セクションをそのまま貼り付けてください（空欄のセクションは「記載なし」として扱われます）',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                for (final entry in _categoryLabels.entries) ...[
                  Text(entry.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: controllers[entry.key],
                    maxLines: 3,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (confirmed != true) return;

    final sections = <String, dynamic>{};
    for (final entry in controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      sections[entry.key] = {
        'sectionNumber': '',
        'sectionTitle': _categoryLabels[entry.key],
        'text': text,
      };
    }

    if (sections.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('少なくとも1項目は入力してください'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('drug_knowledge_base').doc(genericName).set({
      'genericName': genericName,
      'status': 'complete',
      'formatVersion': 'manual',
      'sections': sections,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$genericName」の添付文書情報を登録しました'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drug_knowledge_base')
          .where('status', isEqualTo: 'manual_needed')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('添付文書取得待ちの薬剤はありません', style: TextStyle(color: Colors.black54)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final genericName = data['genericName'] as String? ?? doc.id;
            final lastError = data['lastFetchError'] as String? ?? '';
            final attempts = data['fetchAttempts'] ?? 0;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined, color: Colors.deepOrange),
                title: Text(genericName),
                subtitle: Text('自動取得 $attempts 回失敗${lastError.isNotEmpty ? '\n理由: $lastError' : ''}'),
                isThreeLine: lastError.isNotEmpty,
                trailing: ElevatedButton(
                  onPressed: () => _resolveManually(context, genericName),
                  child: const Text('手動登録'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── 取得待ちリストタブ ───────────────────────────────────────────
//
// drug_fetch_requests: 名寄せには成功したが drug_knowledge_base に
// エントリが1件もない薬剤(=患者が実際に登録したが、まだ添付文書が整備されていない)。
// 「取得実行」でGoプロキシの /v1/admin/fetch-drug-label を呼び、PMDA自動取得を起動する。
// 失敗した場合はGoプロキシ側が自動的に「添付文書取得待ち」タブ(manual_needed)に記録する。

class _FetchPendingTab extends StatefulWidget {
  @override
  State<_FetchPendingTab> createState() => _FetchPendingTabState();
}

class _FetchPendingTabState extends State<_FetchPendingTab> {
  final Set<String> _loading = {};

  Future<void> _runFetch(String genericName, String? searchName) async {
    setState(() => _loading.add(genericName));

    final result = await AiDrugService().adminFetchDrugLabel(
      genericName: genericName,
      searchName: searchName,
    );

    if (!mounted) return;
    setState(() => _loading.remove(genericName));

    final success = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '「$genericName」を取得しました（${result['sectionCount'] ?? 0}セクション）'
              : '「$genericName」の取得に失敗しました: ${result['reason'] ?? '不明なエラー'}\n'
                  '→「添付文書取得待ち」タブから手動登録してください',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // requestCount での orderBy は複合インデックスが必要になるため使わず、
      // 取得後にクライアント側でソートする(unmatched_drug_names等の既存インデックス構成を増やさないため)。
      stream: FirebaseFirestore.instance
          .collection('drug_fetch_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('読み込みエラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs)
          ..sort((a, b) {
            final ac = (a.data() as Map<String, dynamic>)['requestCount'] as int? ?? 0;
            final bc = (b.data() as Map<String, dynamic>)['requestCount'] as int? ?? 0;
            return bc.compareTo(ac);
          });
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('取得待ちの薬剤はありません', style: TextStyle(color: Colors.black54)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final genericName = data['genericName'] as String? ?? doc.id;
            final requestCount = data['requestCount'] ?? 1;
            final examples = (data['exampleInputNames'] as List?)?.cast<String>() ?? const [];
            final isLoading = _loading.contains(genericName);
            return Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_outlined, color: Colors.indigo),
                title: Text(genericName),
                subtitle: Text(
                  '実需要 $requestCount 件${examples.isNotEmpty ? '\n入力例: ${examples.join('、')}' : ''}',
                ),
                isThreeLine: examples.isNotEmpty,
                trailing: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () => _runFetch(genericName, examples.isNotEmpty ? examples.first : null),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('取得実行'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
