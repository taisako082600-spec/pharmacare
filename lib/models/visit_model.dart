import 'package:cloud_firestore/cloud_firestore.dart';

class VisitModel {
  final String id;
  final DateTime visitDate;
  final String department;
  final String mainSymptom;
  final String pharmacistNote;
  final int days;
  final DateTime? nextVisitDate;
  final String addedBy;
  final String addedByName;
  final DateTime? createdAt;

  VisitModel({
    required this.id,
    required this.visitDate,
    this.department = '',
    this.mainSymptom = '',
    this.pharmacistNote = '',
    this.days = 0,
    this.nextVisitDate,
    this.addedBy = '',
    this.addedByName = '',
    this.createdAt,
  });

  factory VisitModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VisitModel(
      id: doc.id,
      visitDate: (data['visitDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      department: data['department'] as String? ?? '',
      mainSymptom: data['mainSymptom'] as String? ?? '',
      pharmacistNote: data['pharmacistNote'] as String? ?? '',
      days: data['days'] as int? ?? 0,
      nextVisitDate: (data['nextVisitDate'] as Timestamp?)?.toDate(),
      addedBy: data['addedBy'] as String? ?? '',
      addedByName: data['addedByName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  DateTime? get endDate =>
      days > 0 ? visitDate.add(Duration(days: days)) : null;

  int? get daysRemaining {
    final end = endDate;
    if (end == null) return null;
    return end.difference(DateTime.now()).inDays;
  }
}
