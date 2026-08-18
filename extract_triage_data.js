// トリアージ資料(OTC_TRIAGE_OVERVIEW_VISUAL.html)に埋め込む DATA を、
// 実装 lib/screens/otc_triage_form_screen.dart から機械的に生成する。
// 資料と実装がずれないよう、資料を更新するときは必ずこれを通すこと。
//
//   node extract_triage_data.js         → 差分チェックのみ(HTMLは書き換えない)
//   node extract_triage_data.js --write → HTML内のDATAブロックを実装から更新
const fs = require('fs');
const path = require('path');

const DART = path.join(__dirname, 'lib', 'screens', 'otc_triage_form_screen.dart');
const HTML = path.join(__dirname, 'OTC_TRIAGE_OVERVIEW_VISUAL.html');

const src = fs.readFileSync(DART, 'utf8');

// `static const Map<...> name = { ... };` の中身を取り出す
function block(name) {
  const start = src.indexOf(name + ' = {');
  if (start < 0) throw new Error('見つかりません: ' + name);
  const from = src.indexOf('{', start);
  let depth = 0;
  for (let i = from; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(from + 1, i);
    }
  }
  throw new Error('閉じ括弧が見つかりません: ' + name);
}

// コメント行を落とす(// で始まる行、および行末コメント)
function stripComments(s) {
  return s.split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
}

function parseListMap(name) {
  const body = stripComments(block(name));
  const out = {};
  const re = /'([A-Za-z0-9_]+)'\s*:\s*\[([^\]]*)\]/g;
  let m;
  while ((m = re.exec(body))) {
    out[m[1]] = [...m[2].matchAll(/'([A-Za-z0-9_]+)'/g)].map((x) => x[1]);
  }
  return out;
}

function parseStringMap(name) {
  const body = stripComments(block(name));
  const out = {};
  // 値側は日本語・記号を含むので ' で囲まれた残り全部を取る
  const re = /'([A-Za-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'/g;
  let m;
  while ((m = re.exec(body))) out[m[1]] = m[2].replace(/\\'/g, "'");
  return out;
}

const data = {
  redFlagOptions: parseListMap('redFlagOptions'),
  redFlagLabels: parseStringMap('redFlagLabels'),
  categoryLabels: parseStringMap('categoryLabels'),
  consultationFlagOptions: parseListMap('consultationFlagOptions'),
  consultationFlagLabels: parseStringMap('consultationFlagLabels'),
};

// 整合性チェック: ラベルのないキー、使われないラベルがあれば止める
const problems = [];
for (const [cat, keys] of Object.entries(data.redFlagOptions)) {
  for (const k of keys) {
    if (!data.redFlagLabels[k]) problems.push(`ラベルなし: ${cat}.${k}`);
  }
}
const used = new Set(Object.values(data.redFlagOptions).flat());
for (const k of Object.keys(data.redFlagLabels)) {
  if (!used.has(k)) problems.push(`未使用のラベル: ${k}`);
}
for (const [cat, keys] of Object.entries(data.consultationFlagOptions)) {
  for (const k of keys) {
    if (!data.consultationFlagLabels[k]) problems.push(`受診目安ラベルなし: ${cat}.${k}`);
  }
}
if (problems.length) {
  console.error('整合性エラー:\n  ' + problems.join('\n  '));
  process.exit(1);
}

const total = used.size === 0 ? 0 : Object.values(data.redFlagOptions).flat().length;
console.log(`危険信号 ${total}項目 / ${Object.keys(data.redFlagOptions).length}カテゴリー`);
console.log(`受診の目安 ${Object.values(data.consultationFlagOptions).flat().length}項目`);

if (!process.argv.includes('--write')) {
  console.log('(--write を付けるとHTMLのDATAブロックを更新します)');
  process.exit(0);
}

const html = fs.readFileSync(HTML, 'utf8');
const marker = '  const DATA = ';
const start = html.indexOf(marker);
if (start < 0) throw new Error('HTML内に DATA ブロックが見つかりません');
const end = html.indexOf('\n  };', start);
if (end < 0) throw new Error('DATA ブロックの終端が見つかりません');
const next = marker + JSON.stringify(data, null, 2).replace(/\n/g, '\n  ');
fs.writeFileSync(HTML, html.slice(0, start) + next + html.slice(end), 'utf8');
console.log('HTMLのDATAを更新しました');
