# キャッシング戦略ガイド

## 概要
本アプリケーションは3層のキャッシング戦略を採用し、ネットワーク負荷を削減しUXを向上させています。

---

## 1️⃣ Firestore オフラインキャッシング（自動）

**特徴:**
- Firebase が自動的に manage
- ローカルディスク（SQLite）に保存
- オフライン時もデータ閲覧可能
- **設定場所:** `lib/main.dart` (line 23-26)

**キャッシュサイズ:** 100MB（無制限設定可能）

**自動有効化対象:**
- すべての Firestore read/write
- StreamBuilder で使用されるすべてのクエリ

**利点:**
- 初回ロード後、2回目以降は極めて高速
- ネットワーク遅延の影響を最小化

---

## 2️⃣ メモリキャッシング（CacheService）

**特徴:**
- アプリ実行中のみ有効
- メモリに展開（高速アクセス）
- 有効期限: 5分（カスタマイズ可能）

**使用場所:**
```dart
// 設定
CacheService().setCached(CacheKeys.facilityList, data);

// 取得
final cached = CacheService().getCached<List>(CacheKeys.facilityList);

// クリア
CacheService().clearCache(CacheKeys.facilityList);
CacheService().clearAllCache(); // すべてクリア
```

**推奨用途:**
- 頻繁にアクセスされるマスターデータ（施設一覧、患者一覧）
- ユーザー設定値
- フィルター結果

**キャッシュキー定義:** `lib/services/cache_service.dart`

---

## 3️⃣ ローカルストレージキャッシング（今後実装推奨）

**推奨パッケージ:**
```yaml
dependencies:
  shared_preferences: ^2.2.0  # ユーザー設定用
  hive: ^2.2.0               # 構造化データ用
```

**推奨用途:**
- ユーザー選択した施設ID
- UI 状態（展開/収納状態など）
- ソート順序・フィルター条件

**実装例:**
```dart
// shared_preferences で最後に選んだ施設を保存
final prefs = await SharedPreferences.getInstance();
await prefs.setString('last_facility_id', facilityId);
final saved = prefs.getString('last_facility_id');
```

---

## パフォーマンス目標

| データ | キャッシュ層 | 初回 | 2回目以降 |
|-------|-----------|-----|---------|
| 患者リスト | Firestore | ~500ms | ~50ms |
| イベント | Firestore | ~300ms | ~30ms |
| チャット履歴 | Firestore | ~400ms | ~40ms |
| 施設マスター | Memory | ~100ms | ~5ms |

---

## ベストプラクティス

### ✅ DO
- StreamBuilder で Firestore streaming を使う
- 頻繁にアクセスされるデータは Memory キャッシュに保存
- キャッシュ有効期限を適切に設定
- オフラインでも動作確認を行う

### ❌ DON'T
- すべてのデータをメモリキャッシュに保存しない（メモリリーク）
- キャッシュ無効化を忘れない（古い情報表示）
- 手動キャッシュと Firestore を同期せずに更新しない

---

## トラブルシューティング

**古い情報が表示される場合:**
```dart
// キャッシュを明示的にクリア
CacheService().clearCache(key);
// または Firestore キャッシュをクリア
await FirebaseFirestore.instance.clearPersistence();
```

**オフライン時にデータが見えない場合:**
- Firestore オフラインキャッシング有効化確認（main.dart）
- ネットワーク接続を待つ

---

## 参考資料
- [Firebase Offline Persistence](https://firebase.flutter.dev/docs/firestore/usage#offline-persistence)
- [Firestore Best Practices](https://firebase.google.com/docs/firestore/best-practices)
