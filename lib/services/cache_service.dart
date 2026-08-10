import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

/// アプリ内のメモリキャッシング戦略を管理するサービス
class CacheService {
  static final CacheService _instance = CacheService._internal();

  factory CacheService() {
    return _instance;
  }

  CacheService._internal();

  // キャッシュ用メモリ
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// メモリキャッシュにデータを保存
  void setCached(String key, dynamic value) {
    _memoryCache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// メモリキャッシュからデータを取得
  /// 有効期限切れの場合は null を返す
  T? getCached<T>(String key) {
    if (!_memoryCache.containsKey(key)) return null;

    final timestamp = _cacheTimestamps[key];
    if (timestamp != null && DateTime.now().difference(timestamp) > _cacheExpiry) {
      // キャッシュ有効期限切れ
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }

    return _memoryCache[key] as T?;
  }

  /// メモリキャッシュをクリア
  void clearCache(String key) {
    _memoryCache.remove(key);
    _cacheTimestamps.remove(key);
  }

  /// すべてのメモリキャッシュをクリア
  void clearAllCache() {
    _memoryCache.clear();
    _cacheTimestamps.clear();
  }

  /// Firestore オフラインキャッシングを有効化
  /// アプリ起動時に一度だけ呼び出す
  static Future<void> enableOfflinePersistence() async {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024, // 100MB
      );
    } catch (e) {
      // すでに有効化されている場合などのエラーを無視
    }
  }
}

/// キャッシュキー定義
class CacheKeys {
  // ユーザー関連
  static const String userProfile = 'user_profile';

  // 施設関連
  static const String facilityList = 'facility_list';
  static String facilityDetail(String facilityId) => 'facility_detail_$facilityId';

  // 患者関連
  static const String patientList = 'patient_list';
  static String patientDetail(String patientId) => 'patient_detail_$patientId';
  static String patientMedicines(String patientId) => 'patient_medicines_$patientId';

  // イベント関連
  static const String eventList = 'event_list';

  // チャット関連
  static const String roomList = 'room_list';
  static String roomMessages(String roomId) => 'room_messages_$roomId';
}
