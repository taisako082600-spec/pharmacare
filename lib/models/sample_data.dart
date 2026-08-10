import 'patient_model.dart';

final List<PatientModel> samplePatients = [
  PatientModel(
    id: '001',
    name: '田中 花子',
    birthDate: '1945/03/15',
    age: 80,
    roomNumber: '101号室',
    conditions: ['高血圧', '糖尿病', '高コレステロール'],
    medicines: [
      MedicineModel(name: 'アムロジピン錠 5mg', dosage: '1錠', frequency: '1日1回 朝食後', purpose: '高血圧', startDate: '2025/04/01'),
      MedicineModel(name: 'メトホルミン錠 500mg', dosage: '1錠', frequency: '1日2回 朝夕食後', purpose: '糖尿病', startDate: '2025/01/15'),
      MedicineModel(name: 'アトルバスタチン錠 10mg', dosage: '1錠', frequency: '1日1回 夕食後', purpose: '高コレステロール', startDate: '2025/03/10'),
    ],
  ),
  PatientModel(
    id: '002',
    name: '佐藤 一郎',
    birthDate: '1938/07/22',
    age: 87,
    roomNumber: '205号室',
    conditions: ['心不全', '慢性腎臓病'],
    medicines: [
      MedicineModel(name: 'フロセミド錠 20mg', dosage: '1錠', frequency: '1日1回 朝食後', purpose: '心不全', startDate: '2024/11/01'),
      MedicineModel(name: 'スピロノラクトン錠 25mg', dosage: '1錠', frequency: '1日1回 朝食後', purpose: '心不全', startDate: '2024/11/01'),
    ],
  ),
  PatientModel(
    id: '003',
    name: '鈴木 幸子',
    birthDate: '1950/11/08',
    age: 75,
    roomNumber: '302号室',
    conditions: ['骨粗鬆症', '関節リウマチ'],
    medicines: [
      MedicineModel(name: 'アレンドロン酸錠 35mg', dosage: '1錠', frequency: '週1回 起床時', purpose: '骨粗鬆症', startDate: '2025/02/01'),
      MedicineModel(name: 'メトトレキサート錠 2mg', dosage: '2錠', frequency: '週1回', purpose: '関節リウマチ', startDate: '2024/09/15'),
    ],
  ),
  PatientModel(
    id: '004',
    name: '山田 太郎',
    birthDate: '1942/05/30',
    age: 83,
    roomNumber: '410号室',
    conditions: ['アルツハイマー型認知症', '高血圧'],
    medicines: [
      MedicineModel(name: 'ドネペジル錠 5mg', dosage: '1錠', frequency: '1日1回 夕食後', purpose: '認知症', startDate: '2024/06/01'),
      MedicineModel(name: 'カンデサルタン錠 8mg', dosage: '1錠', frequency: '1日1回 朝食後', purpose: '高血圧', startDate: '2025/01/20'),
    ],
  ),
];
