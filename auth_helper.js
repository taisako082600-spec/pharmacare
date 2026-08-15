// デプロイスクリプト共通の認証ヘルパー。
//
// 経緯: 以前は Downloads 配下のサービスアカウントJSONを直接参照していたが、
// Windowsのストレージセンサーが「ダウンロードフォルダー内の14日間開かれていない
// ファイルを自動削除する」設定になっており、鍵が消えてデプロイが一切できなくなった
// (2026-08-16に発覚)。ダウンロードフォルダーに置く限り再発するため、
//
//   1. 鍵は .secrets/ (プロジェクト配下・gitignore済み・自動削除の対象外) に置く
//   2. 鍵が無ければ gcloud のログイン情報にフォールバックする
//
// の二段構えにしてある。鍵が無くてもデプロイできるので、鍵の管理自体が任意。
//
// 本番のCloud Run側はSecret Managerに別途鍵を保持しているため、この鍵ファイルの
// 有無はCloud Runの稼働には影響しない。

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ID = 'pharmacist-app-646df';

// 推奨の置き場所。ストレージセンサーの自動削除対象外で、gitignore済み。
const SECRETS_DIR = path.join(__dirname, '.secrets');
const PREFERRED_KEY_FILE = path.join(SECRETS_DIR, 'firebase-adminsdk.json');

// 旧: ダウンロードフォルダー。ここに置くと自動削除で消えるため非推奨だが、
// 既存環境との互換のため、あれば使う(使うときは警告を出す)。
const LEGACY_KEY_FILE =
  'C:/Users/OWNER/Downloads/pharmacist-app-646df-firebase-adminsdk-fbsvc-814ff25523.json';

// gcloud は環境によってPATHが通っていないため、既知のインストール先も探す
const GCLOUD_CANDIDATES = [
  'gcloud',
  'C:/Users/OWNER/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd',
  'C:/Program Files (x86)/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd',
  'C:/Program Files/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd',
];

function tokenFromGcloud() {
  for (const cmd of GCLOUD_CANDIDATES) {
    try {
      // 引数はすべてこのファイル内の固定値で、外部入力は混ざらない
      const out = execSync(`"${cmd}" auth print-access-token`, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      const token = out.trim();
      if (token) return token;
    } catch (_) {
      // このパスでは見つからなかっただけなので次を試す
    }
  }
  return null;
}

/** 使えるサービスアカウント鍵のパスを返す。無ければ null。 */
function findKeyFile() {
  if (fs.existsSync(PREFERRED_KEY_FILE)) return PREFERRED_KEY_FILE;
  if (fs.existsSync(LEGACY_KEY_FILE)) {
    console.warn(
      '⚠ サービスアカウント鍵がダウンロードフォルダーにあります。\n' +
        '  Windowsのストレージセンサーが14日で自動削除するため、いずれ消えます。\n' +
        `  ${PREFERRED_KEY_FILE} へ移動してください。`
    );
    return LEGACY_KEY_FILE;
  }
  return null;
}

/**
 * アクセストークンと、リクエストに付けるべき追加ヘッダーを取得する。
 *
 * gcloud のログイン情報(ユーザー認証情報)を使う場合、Firebase系APIは
 * 「どのプロジェクトのクォータを消費するか」を x-goog-user-project ヘッダーで
 * 明示するよう要求してくる。サービスアカウントの場合は不要。
 *
 * @param {string[]} scopes 鍵ファイル経由の場合に要求するスコープ
 * @returns {Promise<{token: string, extraHeaders: Object}>}
 */
async function getAuth(scopes) {
  const keyFile = findKeyFile();
  if (keyFile) {
    const { GoogleAuth } = require('./node_modules/google-auth-library');
    const auth = new GoogleAuth({ keyFile, scopes });
    console.log('認証: サービスアカウントキーを使用');
    return { token: await auth.getAccessToken(), extraHeaders: {} };
  }

  const token = tokenFromGcloud();
  if (token) {
    console.log('認証: gcloud のログイン情報を使用');
    return { token, extraHeaders: { 'x-goog-user-project': PROJECT_ID } };
  }

  throw new Error(
    'デプロイ用の認証情報が見つかりません。次のいずれかを行ってください:\n' +
      '  1) gcloud auth login  を実行する（推奨。既にログイン済みならそのまま使えます）\n' +
      `  2) サービスアカウントキーを ${PREFERRED_KEY_FILE} に配置する`
  );
}

module.exports = { getAuth, PREFERRED_KEY_FILE, LEGACY_KEY_FILE };
