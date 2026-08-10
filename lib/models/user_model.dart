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
