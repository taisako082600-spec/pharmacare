// デプロイの前提条件をまとめて確認する。
//
// Flutterのビルドは数十分〜数時間かかるため、「ビルドし終えてからデプロイで初めて
// 認証エラーに気づく」のが一番つらい。ビルド前にこれを実行して先に潰しておく。
//
//   node check_deploy_ready.js
//
// 使いどころ: 久しぶりにデプロイするとき、環境を変えたとき、
// デプロイが失敗した原因を切り分けたいとき。

const fs = require('fs');
const path = require('path');
const https = require('https');
const { getAuth, PREFERRED_KEY_FILE, LEGACY_KEY_FILE } = require('./auth_helper');

const SITE_ID = 'pharmacist-app-646df';
const CLOUD_RUN_PING = 'https://pharmacore-llm-proxy-p6j6p3dn5q-an.a.run.app/ping';

let ng = 0;
const ok = (m) => console.log(`  OK   ${m}`);
const bad = (m) => { ng++; console.log(`  NG   ${m}`); };
const info = (m) => console.log(`       ${m}`);

function get(url, headers = {}) {
  return new Promise((resolve) => {
    https.get(url, { headers }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    }).on('error', (e) => resolve({ status: 0, body: e.message }));
  });
}

(async () => {
  console.log('\n=== デプロイ前チェック ===\n');

  // 1. 認証
  console.log('[1] 認証');
  let auth = null;
  try {
    auth = await getAuth([
      'https://www.googleapis.com/auth/firebase',
      'https://www.googleapis.com/auth/cloud-platform',
    ]);
    ok('アクセストークンを取得できました');
  } catch (e) {
    bad('認証情報がありません');
    info(e.message.split('\n').join('\n       '));
  }

  // 2. 鍵ファイルの置き場所(任意。無くてもgcloudで動く)
  console.log('\n[2] サービスアカウント鍵の置き場所');
  if (fs.existsSync(PREFERRED_KEY_FILE)) {
    ok(`推奨の場所にあります: ${PREFERRED_KEY_FILE}`);
  } else if (fs.existsSync(LEGACY_KEY_FILE)) {
    bad('ダウンロードフォルダーにあります(14日で自動削除されます)');
    info(`${PREFERRED_KEY_FILE} へ移動してください`);
  } else {
    ok('鍵ファイルなし → gcloud のログイン情報を使います(問題ありません)');
  }

  // 3. Firebase Hosting API に実際に到達できるか
  console.log('\n[3] Firebase Hosting API への疎通');
  if (auth) {
    const res = await get(
      `https://firebasehosting.googleapis.com/v1beta1/sites/${SITE_ID}/releases?pageSize=1`,
      { Authorization: `Bearer ${auth.token}`, ...auth.extraHeaders }
    );
    if (res.status === 200) ok('デプロイ先に到達でき、権限もあります');
    else {
      bad(`HTTP ${res.status}`);
      info(res.body.slice(0, 200));
    }
  } else {
    bad('認証できていないため未確認');
  }

  // 4. ビルド成果物
  console.log('\n[4] ビルド成果物');
  const buildDir = path.join(__dirname, 'build', 'web');
  if (fs.existsSync(path.join(buildDir, 'main.dart.js'))) {
    ok('build/web/main.dart.js があります');
  } else {
    bad('build/web/main.dart.js がありません');
    info('先に flutter build web --release --pwa-strategy=none を実行してください');
  }

  // 5. LLMプロキシ(落ちていてもアプリは動くが、AI解説は出ない)
  console.log('\n[5] Cloud Run の LLMプロキシ');
  const ping = await get(CLOUD_RUN_PING);
  if (ping.status === 200) ok('/ping が応答しています');
  else info(`応答なし (HTTP ${ping.status}) — トリアージ判定自体はアプリ側で動くため致命的ではありません`);

  console.log(ng === 0 ? '\n✅ デプロイ可能です\n' : `\n⚠ ${ng}件の問題があります。上記を解消してください\n`);
  process.exit(ng === 0 ? 0 : 1);
})();
