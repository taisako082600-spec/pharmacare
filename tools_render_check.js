// 資料HTMLの描画スクリプトを最小限のDOM代替で実際に走らせ、
// セクション04(チャート)と05(症候別一覧)に要素が生成されるかを確かめる。
// JSON.parse だけの検証では「JSは壊れているがJSONは正しい」状態を見逃したため。
const fs = require('fs');
const path = process.argv[2];
const html = fs.readFileSync(path, 'utf8');

const code = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)]
  .map((m) => m[1])
  .find((s) => s.includes('const DATA'));
if (!code) {
  console.error('DATAを含む<script>が見つかりません');
  process.exit(1);
}

const made = { 'bar-chart': 0, 'symptom-accordion': 0 };

function el(id) {
  return {
    id,
    children: [],
    style: {},
    appendChild(c) {
      this.children.push(c);
      if (id in made) made[id]++;
    },
    addEventListener() {},
    querySelector() {
      return { addEventListener() {}, style: {} };
    },
    set innerHTML(v) {
      this._html = v;
    },
    get innerHTML() {
      return this._html || '';
    },
  };
}

const nodes = { 'bar-chart': el('bar-chart'), 'symptom-accordion': el('symptom-accordion'), tooltip: el('tooltip') };

global.document = {
  getElementById: (id) => nodes[id] || el(id),
  createElement: () => el('_new'),
};

try {
  new Function(code)();
} catch (e) {
  console.error('描画スクリプトが実行時エラー:', e.message);
  process.exit(1);
}

console.log('04 チャートの行数        :', made['bar-chart']);
console.log('05 症候アコーディオン件数:', made['symptom-accordion']);

if (made['bar-chart'] === 0 || made['symptom-accordion'] === 0) {
  console.error('→ 空欄になります。失敗。');
  process.exit(1);
}
console.log('→ 両セクションとも描画されます。');
