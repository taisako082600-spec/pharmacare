import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 監査ログサービス - 全操作を記録
class AuditService {
  static final AuditService _instance = AuditService._internal();

  factory AuditService() => _instance;
  AuditService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// アクション種別
  static const String actionCreate = 'CREATE';
  static const String actionUpdate = 'UPDATE';
  static const String actionDelete = 'DELETE';
  static const String actionRead = 'READ';
  static const String actionLogin = 'LOGIN';
  static const String actionLogout = 'LOGOUT';

  /// 監査ログを記録
  Future<void> log({
    required String userId,
    required String userName,
    required String action,
    required String collection,
    required String documentId,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    String? reason,
  }) async {
    try {
      await _db.collection('audit_logs').add({
        'userId': userId,
        'userName': userName,
        'action': action,
        'collection': collection,
        'documentId': documentId,
        'beforeData': beforeData,
        'afterData': afterData,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'ipAddress': 'N/A', // 本来はクライアントIPを取得
      });
    } catch (e) {
      // ログ記録失敗時は無視（システムクリティカルではない）
      debugPrint('Audit log failed: $e');
    }
  }

  /// ユーザーの監査ログを取得
  Stream<QuerySnapshot> getAuditLogsForUser(String userId) {
    return _db
        .collection('audit_logs')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  /// 施設の監査ログを取得
  Stream<QuerySnapshot> getAuditLogsForFacility(String facilityId) {
    return _db
        .collection('audit_logs')
        .where('collection', isEqualTo: 'patients')
        .where('documentId', isEqualTo: facilityId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// 全監査ログ（管理者のみ）
  Stream<QuerySnapshot> getAllAuditLogs() {
    return _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(500)
        .snapshots();
  }
}
