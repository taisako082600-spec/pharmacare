import 'package:cloud_firestore/cloud_firestore.dart';
import 'audit_service.dart';

/// ⚠️ このクラスは現在 28メソッド中 3つしか使われていない
/// (`addFacility` / `assignPharmacistToFacility` / `unassignPharmacistFromFacility`、
/// いずれも `admin_facilities_screen.dart` から)。残りは呼び出し元ゼロの死んだコード。
/// 2026-08-16 の全体チェックで判明した注意点:
///
///  1. **複合インデックス未整備**: `getRoomsForFacility`(facilityId== + orderBy updatedAt)、
///     `getEvents`(facilityId== + orderBy date)、`getPharmacistsForFacility`
///     (role== + facilityIds arrayContains)は、本番Firestoreに実際にクエリを投げて
///     FAILED_PRECONDITION になることを確認済み。**そのまま画面に繋ぐと即エラーになる。**
///     このプロジェクトはインデックス定義を持たない方針なので、使うなら単一の where で
///     取得してクライアント側でソート/フィルタする形に書き換えること。
///  2. **削除処理の重複**: `deleteUser` / `deletePatient` は、実際に使われている
///     `admin_users_screen.dart` 側の実装と別物。参照クリーンアップ漏れの修正は
///     そちらにしか入っていない可能性があるため、こちらを復活させる場合は要確認。
///
/// 使う予定がないなら削除してよい。
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---- 施設 ----
  Stream<QuerySnapshot> getFacilities() =>
      _db.collection('facilities').orderBy('name').snapshots();

  Future<DocumentSnapshot> getFacility(String facilityId) =>
      _db.collection('facilities').doc(facilityId).get();

  Future<void> addFacility(Map<String, dynamic> data) async {
    await _db.collection('facilities').add({
      ...data,
      'pharmacistIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateFacility(String id, Map<String, dynamic> data) async {
    await _db.collection('facilities').doc(id).update(data);
  }

  // 薬剤師を施設に紐付け
  Future<void> assignPharmacistToFacility(String facilityId, String pharmacistUid) async {
    await _db.collection('facilities').doc(facilityId).update({
      'pharmacistIds': FieldValue.arrayUnion([pharmacistUid]),
    });
    // 薬剤師のfacilityIdsにも追加
    await _db.collection('users').doc(pharmacistUid).update({
      'facilityIds': FieldValue.arrayUnion([facilityId]),
    });
  }

  // 薬剤師を施設から解除
  Future<void> unassignPharmacistFromFacility(String facilityId, String pharmacistUid) async {
    await _db.collection('facilities').doc(facilityId).update({
      'pharmacistIds': FieldValue.arrayRemove([pharmacistUid]),
    });
    await _db.collection('users').doc(pharmacistUid).update({
      'facilityIds': FieldValue.arrayRemove([facilityId]),
    });
  }

  // 施設に紐付いた薬剤師一覧
  Stream<QuerySnapshot> getPharmacistsForFacility(String facilityId) =>
      _db.collection('users')
          .where('role', isEqualTo: '薬剤師')
          .where('facilityIds', arrayContains: facilityId)
          .snapshots();

  // 全薬剤師一覧
  Stream<QuerySnapshot> getAllPharmacists() =>
      _db.collection('users').where('role', isEqualTo: '薬剤師').snapshots();

  // ---- ユーザー ----
  Stream<QuerySnapshot> getUsersByFacility(String facilityId) =>
      _db.collection('users').where('facilityId', isEqualTo: facilityId).snapshots();

  Stream<QuerySnapshot> getAllUsers() =>
      _db.collection('users').orderBy('createdAt', descending: true).snapshots();

  Future<void> updateUserRole(String uid, String role) async {
    await _db.collection('users').doc(uid).update({'role': role});
  }

  Future<void> deleteUser(String uid) async {
    // 所属する「全て」の施設のpharmacistIds/adminUidsからも取り除く(参照だけが残ると
    // 「担当薬剤師◯名」等の表示が実際の登録人数と食い違う不具合になる)。薬剤師は
    // 複数施設に所属しうる(facilityIds配列)ため、facilityId単体だけでは不十分。
    final userData = (await _db.collection('users').doc(uid).get()).data();
    final singleId = userData?['facilityId'] as String?;
    final multiIds = (userData?['facilityIds'] as List?)?.cast<String>() ?? const [];
    final targetFacilityIds = {
      if (singleId != null && singleId.isNotEmpty) singleId,
      ...multiIds,
    };
    for (final fid in targetFacilityIds) {
      try {
        await _db.collection('facilities').doc(fid).update({
          'pharmacistIds': FieldValue.arrayRemove([uid]),
          'adminUids': FieldValue.arrayRemove([uid]),
        });
      } catch (_) {
        // 施設ドキュメントが既に存在しない等でも、ユーザー削除自体は継続する
      }
    }
    await _db.collection('users').doc(uid).delete();
  }

  // ---- 患者 ----
  Stream<QuerySnapshot> getPatients(String facilityId) =>
      _db.collection('patients')
          .where('facilityId', isEqualTo: facilityId)
          .snapshots();

  Future<DocumentReference> addPatient(Map<String, dynamic> data) async {
    return await _db.collection('patients').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePatient(String id, Map<String, dynamic> data) async {
    await _db.collection('patients').doc(id).update(data);
  }

  Future<void> deletePatient(String id, {String? userId, String? userName}) async {
    // 削除前のデータを取得（監査ログ用）
    final patientDoc = await _db.collection('patients').doc(id).get();
    final patientData = patientDoc.data();

    final batch = _db.batch();

    // 患者ドキュメント削除
    batch.delete(_db.collection('patients').doc(id));

    // 関連する薬剤も削除
    final medicines = await _db.collection('patients').doc(id).collection('medicines').get();
    for (final doc in medicines.docs) {
      batch.delete(doc.reference);
    }

    // 関連する服薬記録も削除
    final records = await _db.collection('patients').doc(id).collection('records').get();
    for (final doc in records.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    // 監査ログに記録
    if (userId != null && userName != null) {
      await AuditService().log(
        userId: userId,
        userName: userName,
        action: AuditService.actionDelete,
        collection: 'patients',
        documentId: id,
        beforeData: patientData,
        reason: '患者削除（関連医薬品・記録も削除）',
      );
    }
  }

  // ---- 薬剤 ----
  Stream<QuerySnapshot> getMedicines(String patientId) =>
      _db.collection('patients')
          .doc(patientId)
          .collection('medicines')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<void> addMedicine(String patientId, Map<String, dynamic> data) async {
    await _db.collection('patients').doc(patientId).collection('medicines').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMedicine(String patientId, String medicineId) async {
    await _db.collection('patients').doc(patientId).collection('medicines').doc(medicineId).delete();
  }

  // ---- チャット ----
  // 施設×薬剤師のペアでルームIDを生成
  String getChatRoomId(String facilityId, String topic) => '${facilityId}_$topic';

  Stream<QuerySnapshot> getMessages(String roomId) =>
      _db.collection('rooms').doc(roomId).collection('messages')
          .orderBy('createdAt')
          .snapshots();

  Future<void> sendMessage(String roomId, String text, String senderUid, String senderName, String role, String facilityId) async {
    await _db.collection('rooms').doc(roomId).collection('messages').add({
      'text': text,
      'senderUid': senderUid,
      'sender': senderName,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('rooms').doc(roomId).set({
      'facilityId': facilityId,
      'lastMessage': text,
      'lastSender': senderName,
      'lastRole': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot> getRoomsForFacility(String facilityId) =>
      _db.collection('rooms')
          .where('facilityId', isEqualTo: facilityId)
          .orderBy('updatedAt', descending: true)
          .snapshots();

  // ---- 服薬記録 ----
  Future<void> recordMedication({
    required String patientId,
    required String timing,
    required bool taken,
    required String recordedBy,
    required String recordedByUid,
  }) async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await _db.collection('patients').doc(patientId).collection('records').add({
      'date': dateStr,
      'timing': timing,
      'taken': taken,
      'recordedBy': recordedBy,
      'recordedByUid': recordedByUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getMedicationRecords(String patientId) =>
      _db.collection('patients').doc(patientId).collection('records')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots();

  // ---- カレンダー ----
  Stream<QuerySnapshot> getEvents(String facilityId) =>
      _db.collection('events')
          .where('facilityId', isEqualTo: facilityId)
          .orderBy('date')
          .snapshots();

  Future<void> addEvent(Map<String, dynamic> data) async {
    await _db.collection('events').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEvent(String id) async {
    await _db.collection('events').doc(id).delete();
  }
}
