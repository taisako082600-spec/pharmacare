class FacilityModel {
  final String id;
  final String name;
  final String address;
  final String phone;
  final List<String> pharmacistIds; // 担当薬剤師のUID一覧

  FacilityModel({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.pharmacistIds = const [],
  });

  factory FacilityModel.fromMap(String id, Map<String, dynamic> map) {
    return FacilityModel(
      id: id,
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      pharmacistIds: List<String>.from(map['pharmacistIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'address': address,
    'phone': phone,
    'pharmacistIds': pharmacistIds,
  };
}
