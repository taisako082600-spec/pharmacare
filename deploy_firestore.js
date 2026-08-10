const fs = require('fs');
const https = require('https');
const { GoogleAuth } = require('google-auth-library');

const PROJECT_ID = 'pharmacist-app-646df';
const KEY_FILE = 'C:/Users/OWNER/Downloads/pharmacist-app-646df-firebase-adminsdk-fbsvc-814ff25523.json';

function request(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// ruleset を作成するだけでは有効化されない。cloud.firestore という名前の
// release がそのrulesetを指すようPATCHして初めて実際のセキュリティルールに反映される。
// (以前のスクリプトはここが欠けており、rulesetを作るだけで反映されていなかった)
async function deployFirestoreRules() {
  const rulesContent = fs.readFileSync('./firestore.rules', 'utf8');

  const auth = new GoogleAuth({
    keyFile: KEY_FILE,
    scopes: ['https://www.googleapis.com/auth/firebase', 'https://www.googleapis.com/auth/cloud-platform']
  });
  const token = await auth.getAccessToken();

  console.log('1/2 rulesetを作成中...');
  const createBody = JSON.stringify({ source: { files: [{ name: 'firestore.rules', content: rulesContent }] } });
  const createRes = await request({
    hostname: 'firebaserules.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/rulesets`,
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }
  }, createBody);

  if (createRes.status !== 200) {
    console.error('ruleset作成に失敗:', createRes.status, createRes.data);
    process.exit(1);
  }
  const rulesetName = JSON.parse(createRes.data).name;
  console.log('  作成完了:', rulesetName);

  console.log('2/2 cloud.firestore リリースに反映中...');
  const releaseBody = JSON.stringify({
    release: { name: `projects/${PROJECT_ID}/releases/cloud.firestore`, rulesetName },
    updateMask: 'rulesetName'
  });
  const releaseRes = await request({
    hostname: 'firebaserules.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/releases/cloud.firestore?updateMask=rulesetName`,
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }
  }, releaseBody);

  console.log(`  Status: ${releaseRes.status}`);
  console.log('  Response:', releaseRes.data);

  if (releaseRes.status !== 200) {
    console.error('リリース反映に失敗しました。ruleset自体は作成済みですが、まだ有効化されていません。');
    process.exit(1);
  }
  console.log('✅ Firestoreルールのデプロイ・反映が完了しました');
}

deployFirestoreRules().catch(e => { console.error('Error:', e.message); process.exit(1); });
