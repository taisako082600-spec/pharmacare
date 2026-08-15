// デプロイスクリプト共通の認証ヘルパー。
//
// 経緯: 以前は Downloads 配下のサービスアカウントJSONを直接参照していたが、
// そのファイルが削除されるとデプロイが一切できなくなる状態だった(2026-08-16に発覚)。
// 鍵ファイルがあれば従来通りそれを使い、無ければ gcloud のログイン情報に
// フォールバックすることで、どちらの環境でもデプロイできるようにしている。
//
// 本番のCloud Run側はSecret Managerに別途鍵を保持しているため、この鍵ファイルの
// 有無はCloud Runの稼働には影響しない。

const fs = require('fs');
const { execSync } = require('child_process');

// 従来の鍵ファイル(存在すれば優先して使う)
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

const PROJECT_ID = 'pharmacist-app-646df';

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
  if (fs.existsSync(LEGACY_KEY_FILE)) {
    const { GoogleAuth } = require('./node_modules/google-auth-library');
    const auth = new GoogleAuth({ keyFile: LEGACY_KEY_FILE, scopes });
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
      `  2) サービスアカウントキーを ${LEGACY_KEY_FILE} に配置する`
  );
}

module.exports = { getAuth, LEGACY_KEY_FILE };
