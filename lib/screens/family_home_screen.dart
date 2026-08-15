import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/patient_model.dart';

/// セクション単位の読み込み失敗表示。
/// エラー時に何も出さずに畳んでしまうと「データが無い」のか「読めていない」のか
/// 家族側から区別できないため、セクション名を添えて明示する。
Widget _sectionError(String sectionLabel) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      '$sectionLabel を読み込めませんでした',
      style: const TextStyle(fontSize: 12, color: Colors.red),
    ),
  );
}

class FamilyHomeScreen extends StatelessWidget {
  final UserModel user;
  const FamilyHomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final patientId = user.linkedPatientId;
    if (patientId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          title: const Text('ファーマケア'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_off, size: 64, color: Colors.black26),
              SizedBox(height: 16),
              Text('患者情報が紐付けられていません', style: TextStyle(color: Colors.black38)),
              SizedBox(height: 8),
              Text('施設スタッフに確認してください', style: TextStyle(fontSize: 12, color: Colors.black26)),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('patients').doc(patientId).snapshots(),
      builder: (context, snap) {
        // hasError を hasData より先に見る。逆にすると権限エラー等が起きたときに
        // ローディング表示のまま止まり、家族側からは原因が分からなくなる(プロジェクト標準)。
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '情報を読み込めませんでした。\n通信状況をご確認のうえ、画面を開き直してください。\n\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('患者情報が見つかりません')));
        }
        final patient = PatientModel.fromMap(snap.data!.id, snap.data!.data() as Map<String, dynamic>);

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            backgroundColor: const Color(0xFF6A1B9A),
            foregroundColor: Colors.white,
            title: Text('${patient.roomNumber.isNotEmpty ? "${patient.roomNumber} " : ""}の服薬情報'),
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ご家族へのメッセージ
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.family_restroom, color: Colors.white, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('家族閲覧モード', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(
                            '${patient.age > 0 ? "${patient.age}歳" : ""}の服薬状況',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 最新の受診・薬情報
              _FamilyVisitSection(patientId: patientId),
              const SizedBox(height: 16),

              // 最新バイタル
              _FamilyVitalsSection(patientId: patientId),
              const SizedBox(height: 16),

              // 次回受診予定
              _FamilyNextVisitSection(patientId: patientId, facilityId: user.facilityId),
            ],
          ),
        );
      },
    );
  }
}

// ─── 最新受診・薬情報 ─────────────────────────────────────────────────

class _FamilyVisitSection extends StatelessWidget {
  final String patientId;
  const _FamilyVisitSection({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients').doc(patientId)
          .collection('visits')
          .orderBy('visitDate', descending: true)
          .limit(3)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _sectionError('現在の処方');
        final visits = snap.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, decoration: BoxDecoration(color: const Color(0xFF6A1B9A), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                const Text('現在の処方', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            if (visits.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: const Text('受診記録がありません', style: TextStyle(color: Colors.black38)),
              )
            else
              ...visits.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final visitDate = (data['visitDate'] as Timestamp?)?.toDate();
                final department = data['department'] as String? ?? '';
                final mainSymptom = data['mainSymptom'] as String? ?? '';
                final days = data['days'] as int? ?? 0;
                final endDate = days > 0 && visitDate != null ? visitDate.add(Duration(days: days)) : null;
                final daysLeft = endDate?.difference(DateTime.now()).inDays;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: daysLeft != null && daysLeft <= 3
                        ? Border.all(color: Colors.red.shade200)
                        : null,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_hospital, size: 15, color: Color(0xFF6A1B9A)),
                          const SizedBox(width: 6),
                          Text(
                            visitDate != null ? '${visitDate.year}年${visitDate.month}月${visitDate.day}日' : '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (department.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF6A1B9A), borderRadius: BorderRadius.circular(6)),
                              child: Text(department, style: const TextStyle(fontSize: 10, color: Colors.white)),
                            ),
                          ],
                          if (daysLeft != null) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: daysLeft <= 3 ? Colors.red.shade50 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                daysLeft > 0 ? '残$daysLeft日' : daysLeft == 0 ? '本日終了' : '終了',
                                style: TextStyle(fontSize: 11, color: daysLeft <= 3 ? Colors.red : Colors.black54, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (mainSymptom.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('症状: $mainSymptom', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                      const SizedBox(height: 8),
                      // 薬剤リスト
                      StreamBuilder<QuerySnapshot>(
                        stream: doc.reference.collection('medicines').orderBy('createdAt').snapshots(),
                        builder: (ctx, medSnap) {
                          if (medSnap.hasError) {
                            return const Text('薬剤情報を読み込めませんでした',
                                style: TextStyle(fontSize: 12, color: Colors.red));
                          }
                          final meds = medSnap.data?.docs ?? [];
                          if (meds.isEmpty) return const SizedBox.shrink();
                          return Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: meds.map((m) {
                              final med = m.data() as Map<String, dynamic>;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E5F5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${med['name'] ?? ''}${(med['frequency'] ?? '').isNotEmpty ? "（${med['frequency']}）" : ""}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF6A1B9A)),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// ─── 最新バイタル ─────────────────────────────────────────────────────

class _FamilyVitalsSection extends StatelessWidget {
  final String patientId;
  const _FamilyVitalsSection({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients').doc(patientId)
          .collection('vitals')
          .orderBy('recordedAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _sectionError('最新のバイタル');
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final data = snap.data!.docs.first.data() as Map<String, dynamic>;
        final recordedAt = (data['recordedAt'] as Timestamp?)?.toDate();
        final systolic = data['systolic'] as int?;
        final diastolic = data['diastolic'] as int?;
        final weight = data['weight'] as num?;
        final spO2 = data['spO2'] as int?;
        final temperature = data['temperature'] as num?;
        final bloodSugar = data['bloodSugar'] as int?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                const Text('最新バイタル', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                if (recordedAt != null)
                  Text('${recordedAt.month}/${recordedAt.day}', style: const TextStyle(fontSize: 12, color: Colors.black38)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (systolic != null && diastolic != null)
                    _FamilyVitalItem(label: '血圧', value: '$systolic/$diastolic', unit: 'mmHg',
                        color: systolic >= 140 ? Colors.red : Colors.pink, icon: Icons.favorite_outline),
                  if (bloodSugar != null)
                    _FamilyVitalItem(label: '血糖値', value: '$bloodSugar', unit: 'mg/dL',
                        color: bloodSugar > 200 ? Colors.orange : Colors.blue, icon: Icons.water_drop_outlined),
                  if (weight != null)
                    _FamilyVitalItem(label: '体重', value: weight.toStringAsFixed(1), unit: 'kg',
                        color: Colors.brown, icon: Icons.scale_outlined),
                  if (spO2 != null)
                    _FamilyVitalItem(label: 'SpO2', value: '$spO2', unit: '%',
                        color: spO2 < 95 ? Colors.red : Colors.teal, icon: Icons.air_outlined),
                  if (temperature != null)
                    _FamilyVitalItem(label: '体温', value: temperature.toStringAsFixed(1), unit: '℃',
                        color: (temperature as double) >= 37.5 ? Colors.orange : Colors.green, icon: Icons.thermostat_outlined),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FamilyVitalItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;
  const _FamilyVitalItem({required this.label, required this.value, required this.unit, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text('$value $unit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ─── 次回受診予定 ─────────────────────────────────────────────────────

class _FamilyNextVisitSection extends StatelessWidget {
  final String patientId;
  final String facilityId;
  const _FamilyNextVisitSection({required this.patientId, required this.facilityId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final in30 = now.add(const Duration(days: 30));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('facilityId', isEqualTo: facilityId)
          .where('type', isEqualTo: '次回受診')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _sectionError('次回の受診予定');
        if (!snap.hasData) return const SizedBox.shrink();
        final upcomingEvents = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final date = (data['date'] as Timestamp?)?.toDate();
          if (date == null) return false;
          return date.isAfter(now) && date.isBefore(in30);
        }).toList()
          ..sort((a, b) {
            final da = ((a.data() as Map)['date'] as Timestamp).toDate();
            final db = ((b.data() as Map)['date'] as Timestamp).toDate();
            return da.compareTo(db);
          });

        if (upcomingEvents.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                const Text('次回受診予定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            ...upcomingEvents.take(3).map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['date'] as Timestamp).toDate();
              final daysUntil = date.difference(now).inDays;
              final title = data['title'] as String? ?? '次回受診';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${date.month}月', style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                          Text('${date.day}日', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('あと$daysUntil日', style: TextStyle(fontSize: 12, color: daysUntil <= 7 ? Colors.orange : Colors.black54)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
