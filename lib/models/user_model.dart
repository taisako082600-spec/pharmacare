class UserModel {
  final String uid;
  final String name;
  final String role;
  final String facilityName;
  final String facilityId;
  final String email;
  final bool isAdmin;
  final List<String> facilityIds;
  final String linkedPatientId; // 家族ロール用

  /// 二要素認証の登録を必須とするアカウントか。
  ///
  /// アカウント作成時に職員ロールへ立てる。true の場合、登録が済むまで
  /// アプリ本体に入れない(`login_screen` と `register_screen` が判定)。
  ///
  /// 既存アカウントにこのフラグは無く(=false)、締め出されない。
  /// 全員の登録が済んだ時点で、既存ユーザーにも一括で立てて一律必須に切り替える。
  /// Firebase は未登録者のサインイン自体は通す仕様で、必須化はアプリ側の責任、と
  /// 公式ドキュメントに明記されている。
  final bool mfaRequired;

  UserModel({
    required this.uid,
    required this.name,
    required this.role,
    required this.facilityName,
    required this.facilityId,
    required this.email,
    this.isAdmin = false,
    this.facilityIds = const [],
    this.linkedPatientId = '',
    this.mfaRequired = false,
  });

  bool get isPharmacist => role == '薬剤師';
  bool get isCareWorker => role == '介護士' || role == '看護師';
  bool get isFamily => role == '家族';

  String get displayRole {
    switch (role) {
      case '薬剤師': return '薬剤師';
      case '介護士': return '介護士';
      case '看護師': return '看護師';
      case '家族': return '家族';
      default: return role;
    }
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      facilityName: map['facilityName'] ?? '',
      facilityId: map['facilityId'] ?? '',
      email: map['email'] ?? '',
      isAdmin: map['isAdmin'] ?? false,
      facilityIds: List<String>.from(map['facilityIds'] ?? [map['facilityId'] ?? '']),
      linkedPatientId: map['linkedPatientId'] ?? '',
      mfaRequired: map['mfaRequired'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'role': role,
    'facilityName': facilityName,
    'facilityId': facilityId,
    'facilityIds': facilityIds,
    'email': email,
    'isAdmin': isAdmin,
    if (linkedPatientId.isNotEmpty) 'linkedPatientId': linkedPatientId,
  };
}
