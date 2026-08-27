import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// 監査ログを記録する。
  ///
  /// 「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編 17①が
  /// 求める「利用者のログイン時刻、アクセス時間、ログイン中に操作した医療情報」を残すのが目的。
  ///
  /// - `userId` はFirestoreルール側で認証済みUIDと一致することを検証するため、
  ///   呼び出し側は必ずログイン中のユーザー自身のUIDを渡すこと。
  /// - `timestamp` はサーバー時刻を使う。ルールで `request.time` との一致を検証しており、
  ///   クライアント時刻を渡すと書き込みが拒否される(改ざん防止)。
  /// - 記録に失敗しても臨床業務は止めない方針だが、黙って消えると監査要件を
  ///   満たせなくなるため、失敗は必ずログに出す。
  Future<void> log({
    required String userId,
    required String userName,
    required String action,
    required String collection,
    required String documentId,
    String? facilityId,
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
        'facilityId': facilityId,
        'beforeData': beforeData,
        'afterData': afterData,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // 監査ログの失敗で臨床操作を巻き添えにしないため握りつぶすが、
      // 「記録されていないことに誰も気づかない」状態は避ける。
      debugPrint('監査ログの記録に失敗しました($action $collection/$documentId): $e');
    }
  }

  /// ログイン中のユーザー自身の操作を記録する簡易版。
  /// `FirebaseAuth.currentUser` から UID を取るため、呼び出し側で取り違える余地がない。
  Future<void> logCurrentUser({
    required String userName,
    required String action,
    required String collection,
    required String documentId,
    String? facilityId,
    String? reason,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // 未ログインなら記録対象外
    await log(
      userId: uid,
      userName: userName,
      action: action,
      collection: collection,
      documentId: documentId,
      facilityId: facilityId,
      reason: reason,
    );
  }

  // ⚠️ 以下3つの取得メソッドは現在どこからも呼ばれていない。
  // いずれも「where + 別フィールドのorderBy」で複合インデックスを要求するため、
  // 本番Firestoreに実際に投げると FAILED_PRECONDITION になることを確認済み
  // (2026-08-16)。画面に繋ぐ場合は、単一の where で取得してクライアント側で
  // ソートする形に書き換えること(このプロジェクトはインデックス定義を持たない方針)。

  /// ユーザーの監査ログを取得
  Stream<QuerySnapshot> getAuditLogsForUser(String userId) {
    return _db
        .collection('audit_logs')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  /// 施設の監査ログを取得。
  ///
  /// ガイドライン システム運用編 17① は、記録するだけでなく
  /// 「定期的に確認すること」まで求めており、確認する主体は施設。
  /// その画面(facility_audit_log_screen.dart)が使う。
  ///
  /// 以前は `documentId == facilityId` で絞っていたが、documentId に入るのは
  /// 操作対象(患者等)のドキュメントIDで、施設IDとは一致しない。
  /// つまり**常に0件を返す**クエリだった(呼び出し元が無かったため露見していなかった)。
  ///
  /// where + 別フィールドの orderBy は複合インデックスが要る
  /// (firestore.indexes.json に定義済み)。
  Stream<QuerySnapshot> getAuditLogsForFacility(String facilityId, {int limit = 300}) {
    return _db
        .collection('audit_logs')
        .where('facilityId', isEqualTo: facilityId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
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
