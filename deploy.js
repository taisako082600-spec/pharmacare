const { getAuth } = require('./auth_helper');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');

const PROJECT_ID = 'pharmacist-app-646df';
const SITE_ID = 'pharmacist-app-646df';
const BUILD_DIR = path.join(__dirname, 'build', 'web');
const TIMESTAMP = Date.now();

// main.dart.js をタイムスタンプ付きファイル名にリネームしてキャッシュをバイパス
function patchBuildFiles() {
  const newJsName = `main.dart.${TIMESTAMP}.js`;
  const mainJsPath = path.join(BUILD_DIR, 'main.dart.js');
  const newJsPath = path.join(BUILD_DIR, newJsName);

  // main.dart.js → main.dart.{timestamp}.js にコピー
  fs.copyFileSync(mainJsPath, newJsPath);

  // flutter_bootstrap.js 内の参照を書き換え
  const bootstrapPath = path.join(BUILD_DIR, 'flutter_bootstrap.js');
  let bootstrap = fs.readFileSync(bootstrapPath, 'utf8');
  bootstrap = bootstrap.replace(/main\.dart(\.\d+)?\.js/g, newJsName);
  fs.writeFileSync(bootstrapPath, bootstrap);

  // index.html の DEPLOY_TIMESTAMP をビルド時タイムスタンプに置換
  const indexPath = path.join(BUILD_DIR, 'index.html');
  let indexHtml = fs.readFileSync(indexPath, 'utf8');
  indexHtml = indexHtml.replace(/DEPLOY_TIMESTAMP/g, TIMESTAMP);
  fs.writeFileSync(indexPath, indexHtml);

  pruneOldBundles(newJsName);

  console.log(`Patched: main.dart.js → ${newJsName}`);
  return newJsName;
}

// 古い main.dart.{timestamp}.js を捨てる。
//
// 毎回コピーを作る一方で消していなかったため、build/web に83個・268MBが溜まり、
// デプロイのたびに全部アップロードしていた(2026-08-22に発見。119ファイル→43ファイル)。
//
// index.html は no-cache 配信なので、読み込みのたびに最新の index.html が取れ、
// そこから最新のバンドルだけが参照される。よって古い分は本来不要。
// ただし既に開いたままのタブが直前のバンドルを掴んでいることはあるので、
// 直前の1世代だけ残す。
const KEEP_GENERATIONS = 1;

function pruneOldBundles(currentName) {
  const bundles = fs.readdirSync(BUILD_DIR)
    .filter((f) => /^main\.dart\.\d+\.js$/.test(f) && f !== currentName)
    .sort()
    .reverse(); // 新しい順

  const stale = bundles.slice(KEEP_GENERATIONS);
  if (stale.length === 0) return;

  let freed = 0;
  for (const f of stale) {
    const p = path.join(BUILD_DIR, f);
    try {
      freed += fs.statSync(p).size;
      fs.unlinkSync(p);
    } catch {
      // 消せなくてもデプロイは続行する(次回また拾う)
    }
  }
  console.log(`Pruned ${stale.length} old bundle(s), freed ${(freed / 1024 / 1024).toFixed(1)} MB`);
}

function httpsRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

function getAllFiles(dir, base = dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...getAllFiles(fullPath, base));
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

async function deploy() {
  // 認証はビルド成果物に触る前に済ませる。順序を逆にすると、認証で失敗したときに
  // build/web だけ書き換わった中途半端な状態が残る(2026-08-16に鍵消失で実際に踏んだ)。
  console.log('Getting auth token...');
  const { token, extraHeaders } = await getAuth([
    'https://www.googleapis.com/auth/firebase',
    'https://www.googleapis.com/auth/cloud-platform',
  ]);
  console.log('Token obtained.');

  console.log('Patching build files...');
  patchBuildFiles();

  // Step 1: Create a new version
  console.log('Creating new version...');
  const createRes = await httpsRequest({
    hostname: 'firebasehosting.googleapis.com',
    path: `/v1beta1/sites/${SITE_ID}/versions`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...extraHeaders
    }
  }, {
    config: {
      rewrites: [{ glob: '**', path: '/index.html' }],
      headers: [
        { glob: '/index.html', headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' } },
        { glob: '/main.dart.js', headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' } },
        { glob: '/flutter_bootstrap.js', headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' } },
        { glob: '/flutter_service_worker.js', headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' } }
      ]
    }
  });

  if (createRes.status !== 200) {
    console.error('Failed to create version:', JSON.stringify(createRes.body, null, 2));
    process.exit(1);
  }
  const versionName = createRes.body.name;
  console.log('Version created:', versionName);

  // Step 2: Collect files and compute hashes
  console.log('Computing file hashes...');
  const allFiles = getAllFiles(BUILD_DIR);
  const fileHashes = {};
  const hashToPath = {};

  for (const filePath of allFiles) {
    const relativePath = '/' + path.relative(BUILD_DIR, filePath).replace(/\\/g, '/');
    const content = fs.readFileSync(filePath);
    const gzipped = zlib.gzipSync(content);
    const hash = crypto.createHash('sha256').update(gzipped).digest('hex');
    fileHashes[relativePath] = hash;
    hashToPath[hash] = filePath;
  }
  console.log(`Found ${allFiles.length} files.`);

  // Step 3: Populate files
  console.log('Populating files...');
  const popRes = await httpsRequest({
    hostname: 'firebasehosting.googleapis.com',
    path: `/v1beta1/${versionName}:populateFiles`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...extraHeaders
    }
  }, { files: fileHashes });

  if (popRes.status !== 200) {
    console.error('Failed to populate files:', JSON.stringify(popRes.body, null, 2));
    process.exit(1);
  }

  const uploadUrl = popRes.body.uploadUrl;
  const requiredHashes = popRes.body.uploadRequiredHashes || [];
  console.log('Upload URL:', uploadUrl);
  console.log(`Need to upload ${requiredHashes.length} files.`);

  // Step 4: Upload required files
  for (const hash of requiredHashes) {
    const filePath = hashToPath[hash];
    const content = fs.readFileSync(filePath);
    const gzipped = zlib.gzipSync(content);

    await new Promise((resolve, reject) => {
      const urlParts = new URL(`${uploadUrl}/${hash}`);
      const req = https.request({
        hostname: urlParts.hostname,
        path: urlParts.pathname + urlParts.search,
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/octet-stream',
          'Content-Length': gzipped.length,
          ...extraHeaders
        }
      }, (res) => {
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          console.log(`Uploaded: ${path.basename(filePath)} (${res.statusCode}) ${body.substring(0,100)}`);
          resolve();
        });
      });
      req.on('error', reject);
      req.write(gzipped);
      req.end();
    });
  }

  // Step 5: Finalize version
  console.log('Finalizing version...');
  const finalRes = await httpsRequest({
    hostname: 'firebasehosting.googleapis.com',
    path: `/v1beta1/${versionName}?update_mask=status`,
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...extraHeaders
    }
  }, { status: 'FINALIZED' });

  if (finalRes.status !== 200) {
    console.error('Failed to finalize:', JSON.stringify(finalRes.body, null, 2));
    process.exit(1);
  }
  console.log('Version finalized.');

  // Step 6: Release
  console.log('Creating release...');
  const releaseRes = await httpsRequest({
    hostname: 'firebasehosting.googleapis.com',
    path: `/v1beta1/sites/${SITE_ID}/releases?versionName=${versionName}`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...extraHeaders
    }
  }, {});

  if (releaseRes.status !== 200) {
    console.error('Failed to release:', JSON.stringify(releaseRes.body, null, 2));
    process.exit(1);
  }

  console.log('\n✅ デプロイ完了！');
  console.log(`🌐 URL: https://${SITE_ID}.web.app`);
}

deploy().catch(e => {
  console.error('Error:', e.message);
  process.exit(1);
});
