# デプロイメント手順

本番環境へのデプロイ方法

## 事前確認

### チェックリスト

- [ ] すべてのテストが通っている
- [ ] コードレビュー完了
- [ ] セキュリティルールをレビュー
- [ ] Firestore バックアップ設定完了
- [ ] 管理者がテスト実施済み
- [ ] ユーザーに告知済み（ダウンタイムがある場合）

---

## 本番デプロイ（Web - Firebase Hosting）

### 1. ビルド

```bash
# 依存関係確認
flutter pub get

# ビルド
flutter build web --release

# 出力: build/web/
```

### 2. Firestore ルール デプロイ

```bash
# ルール確認
cat firestore.rules

# デプロイ
firebase deploy --only firestore:rules --project pharmacist-app-646df
```

### 3. Web アプリ デプロイ

```bash
# Firebase にデプロイ
firebase deploy --project pharmacist-app-646df

# または Web のみ
firebase deploy --only hosting --project pharmacist-app-646df
```

### 4. デプロイ確認

```bash
# ログ確認
firebase deploy:list --project pharmacist-app-646df

# アプリにアクセス
https://pharmacist-app-646df.web.app
```

### ロールバック

デプロイ後に問題が発生した場合：

```bash
# 前のバージョンに戻す
firebase hosting:channels:deploy <channel-name> --project pharmacist-app-646df

# または、Firebase Console → Hosting から手動で戻す
```

---

## Android APK ビルド・デプロイ

### 1. キーストア作成（初回のみ）

```bash
keytool -genkey -v -keystore pharmacist-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias pharmacist
```

### 2. APK ビルド

```bash
flutter build apk --release
# 出力: build/app/outputs/flutter-app.apk
```

### 3. Google Play への申請

1. Google Play Console にログイン
2. 新しいバージョンアップロード
3. APK ファイル選択
4. リリースノート入力
5. 本番公開

---

## iOS アプリ ビルド（Mac 必須）

### 1. 証明書設定

```bash
flutter pub get
cd ios
pod install
cd ..
```

### 2. ビルド

```bash
flutter build ios --release
```

### 3. App Store への申請

```bash
# Xcode で Package
open ios/Runner.xcworkspace

# または
flutter build ios --release
# Xcode の Organizer から Archive → Distribute
```

---

## Database 初期化（新規環境）

新しい環境や復旧時の初期セットアップ：

### 1. Firestore コレクション作成

```bash
# Cloud Shell で実行
firebase firestore:delete --all --project pharmacist-app-646df
```

### 2. セキュリティルール デプロイ

```bash
firebase deploy --only firestore:rules --project pharmacist-app-646df
```

### 3. 初期ユーザー作成

Firebase Console → Authentication → ユーザーを追加

### 4. テストデータ投入

Web アプリ → 管理者ログイン → 「テストデータを投入」

---

## 環境ごとの設定

### 開発環境

```dart
// lib/main.dart
const projectId = "pharmacist-app-dev";
```

### ステージング環境

```dart
const projectId = "pharmacist-app-staging";
```

### 本番環境

```dart
const projectId = "pharmacist-app-646df";
```

---

## CI/CD パイプライン（推奨）

GitHub Actions で自動デプロイ：

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-java@v2
        with:
          java-version: '11'
      - run: flutter pub get
      - run: flutter test
      - run: flutter build web --release
      - uses: w9jds/firebase-action@master
        with:
          args: deploy --project pharmacist-app-646df
        env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
```

---

## デプロイ後のテスト

### 機能テスト

- [ ] ログイン・ログアウト
- [ ] 患者追加・削除
- [ ] 薬剤追加・削除
- [ ] チャット送受信
- [ ] カレンダー予定表示

### パフォーマンステスト

```bash
# Load Testing（Apache JMeter など）
# - 同時ユーザー 100 で負荷テスト
# - レスポンスタイム < 2秒
```

### セキュリティテスト

- [ ] 権限のないユーザーがデータにアクセスできないか確認
- [ ] SQL/XSS インジェクション対策
- [ ] HTTPS 通信確認

---

## トラブル時のロールバック

### Web（Firebase Hosting）

```bash
# デプロイ履歴確認
firebase hosting:releases:list --project pharmacist-app-646df

# 前のバージョンに戻す
firebase hosting:channels:deploy <release-id> --project pharmacist-app-646df
```

### Android/iOS

```bash
# Google Play / App Store で前バージョンに戻す設定
# または、デバイスで前バージョンをインストール
```

---

## バージョン管理

### バージョン番号

`MAJOR.MINOR.PATCH-TYPE`

例: `1.0.0-stable`, `1.1.0-beta`, `1.0.1-hotfix`

### タグ付け

```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

---

## リリースノート

各バージョンのリリースノートテンプレート：

```markdown
# Version X.X.X - YYYY/MM/DD

## 新機能
- ...

## 改善
- ...

## バグ修正
- ...

## 破壊的変更
- ...

## 既知の問題
- ...

## アップグレード手順
1. ...
2. ...
```

---

## 緊急対応（ホットフィックス）

重大なバグ発見時：

1. `hotfix/` ブランチ作成
2. 修正・テスト
3. `main` にマージ
4. デプロイ
5. パッチバージョンアップ

```bash
git checkout -b hotfix/critical-bug
# 修正...
git commit -m "Fix: critical bug"
git checkout main
git merge --no-ff hotfix/critical-bug
git tag v1.0.1
firebase deploy --project pharmacist-app-646df
```

---

## モニタリング・アラート

### Firebase コンソール

- Firestore 読み書き数
- エラーログ
- ユーザーアクティビティ

### Google Cloud Monitoring

```bash
# アラート設定例
# - 読み取り 100k/日 超過時に通知
# - エラー数 10件/時間 超過時に通知
```

---

**最終更新**: 2026年6月23日
