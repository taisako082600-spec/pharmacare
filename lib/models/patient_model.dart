class PatientModel {
  final String id;
  final String name;
  final String birthDate;
  final int age;
  final String roomNumber;
  final String facilityId;
  final List<String> conditions;
  final List<MedicineModel> medicines;
  final double? egfr;
  final String egfrStatus;
  final String egfrNotes;
  final String liverStatus;
  final String liverNotes;
  final List<String> allergies;
  final String medicalNotes;

  PatientModel({
    required this.id,
    required this.name,
    required this.birthDate,
    required this.age,
    required this.roomNumber,
    this.facilityId = '',
    this.conditions = const [],
    this.medicines = const [],
    this.egfr,
    this.egfrStatus = '',
    this.egfrNotes = '',
    this.liverStatus = '',
    this.liverNotes = '',
    this.allergies = const [],
    this.medicalNotes = '',
  });

  factory PatientModel.fromMap(String id, Map<String, dynamic> map) {
    return PatientModel(
      id: id,
      name: map['name'] ?? '',
      birthDate: map['birthDate'] ?? '',
      age: map['age'] ?? 0,
      roomNumber: map['roomNumber'] ?? '',
      facilityId: map['facilityId'] ?? '',
      conditions: List<String>.from(map['conditions'] ?? []),
      medicines: [],
      egfr: (map['egfr'] as num?)?.toDouble(),
      egfrStatus: map['egfrStatus'] ?? '',
      egfrNotes: map['egfrNotes'] ?? '',
      liverStatus: map['liverStatus'] ?? '',
      liverNotes: map['liverNotes'] ?? '',
      allergies: List<String>.from(map['allergies'] ?? []),
      medicalNotes: map['medicalNotes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'birthDate': birthDate,
    'age': age,
    'roomNumber': roomNumber,
    'facilityId': facilityId,
    'conditions': conditions,
    if (egfr != null) 'egfr': egfr,
    if (egfrStatus.isNotEmpty) 'egfrStatus': egfrStatus,
    if (egfrNotes.isNotEmpty) 'egfrNotes': egfrNotes,
    if (liverStatus.isNotEmpty) 'liverStatus': liverStatus,
    if (liverNotes.isNotEmpty) 'liverNotes': liverNotes,
    'allergies': allergies,
    if (medicalNotes.isNotEmpty) 'medicalNotes': medicalNotes,
  };

  /// 薬剤師向けに氏名を匿名化（苗字のみ + ●●）
  String get maskedName {
    if (name.isEmpty) return '●●';
    // スペース（全角/半角）で区切る
    final parts = name.split(RegExp(r'[\s　]+'));
    if (parts.length >= 2) return '${parts[0]} ●●';
    // スペースなし: 最初の1文字（苗字）のみ残す（日本語は苗字2文字が多いが安全のため1文字）
    return '${name[0]}●●';
  }
}

class MedicineModel {
  final String id;
  final String name;
  final String dosage;
  final String frequency;
  final String purpose;
  final String startDate;

  MedicineModel({
    this.id = '',
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.purpose,
    required this.startDate,
  });

  factory MedicineModel.fromMap(String id, Map<String, dynamic> map) {
    return MedicineModel(
      id: id,
      name: map['name'] ?? '',
      dosage: map['dosage'] ?? '',
      frequency: map['frequency'] ?? '',
      purpose: map['purpose'] ?? '',
      startDate: map['startDate'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'purpose': purpose,
    'startDate': startDate,
  };
}
