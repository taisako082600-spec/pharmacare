// 紹介用スライド生成スクリプト。
//   node build_deck.js
// 出力: PharmaCare_紹介資料.pptx
//
// 方針:
//   - 読ませる資料ではなく、見せる資料。1スライド1メッセージ。
//   - 第1部はアプリ、第2部は「健診データをどうプライマリケアに活かすか」。
//     BRI研究はそのテーマの事例として置く。

const pptxgen = require('pptxgenjs');

// ── 配色 ───────────────────────────────────────────────
// 介護施設 × 薬剤師 という主題に合わせ、臨床的すぎない深い青緑を主色に。
// トリアージの信号色(緑/黄/赤)は「意味のある色」として該当箇所だけで使う。
const C = {
  deep: '14504B',
  mid: '3E8E84',
  soft: 'A8CFC9',
  amber: 'D98A2B',
  ink: '16211F',
  inkSub: '5C6B68',
  paper: 'FFFFFF',
  wash: 'F1F6F5',
  ok: '2E7D4F',
  warn: 'C99A22',
  danger: 'B23A2F',
};

const F = { jp: 'Yu Gothic' };

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE';
pres.author = 'PharmaCare';
pres.title = 'ファーマケア 紹介資料';

// ── 部品 ───────────────────────────────────────────────
const dark = () => { const s = pres.addSlide(); s.background = { color: C.deep }; return s; };
const light = () => { const s = pres.addSlide(); s.background = { color: C.paper }; return s; };

function heading(s, text, sub) {
  s.addText(text, {
    x: 0.8, y: 0.5, w: 11.7, h: 0.75,
    fontFace: F.jp, fontSize: 32, bold: true, color: C.deep, margin: 0,
  });
  if (sub) {
    s.addText(sub, {
      x: 0.8, y: 1.28, w: 11.7, h: 0.4,
      fontFace: F.jp, fontSize: 14, color: C.inkSub, margin: 0,
    });
  }
}

// 円形バッジ。この資料の視覚モチーフとして全体で反復する。
function badge(s, label, x, y, size, fill, fontSize) {
  s.addShape(pres.ShapeType.ellipse, {
    x, y, w: size, h: size, fill: { color: fill }, line: { color: fill },
  });
  s.addText(label, {
    x, y, w: size, h: size,
    fontFace: F.jp, fontSize: fontSize || 16, bold: true,
    color: 'FFFFFF', align: 'center', valign: 'middle', margin: 0,
  });
}

function card(s, x, y, w, h, fill, outline) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.08,
    fill: { color: fill },
    line: { color: outline || fill },
  });
}

function arrow(s, x, y, w) {
  s.addShape(pres.ShapeType.rightArrow, {
    x, y, w, h: 0.26, fill: { color: C.soft }, line: { color: C.soft },
  });
}

// ══════════════════════════════════ 表紙
{
  const s = dark();
  s.addShape(pres.ShapeType.ellipse, { x: 9.8, y: -1.6, w: 5.6, h: 5.6, fill: { color: '1B635C' }, line: { color: '1B635C' } });
  s.addShape(pres.ShapeType.ellipse, { x: 11.4, y: 4.4, w: 3.2, h: 3.2, fill: { color: '1B635C' }, line: { color: '1B635C' } });

  s.addText('現場のデータを、\n次の一手につなげる', {
    x: 1.0, y: 1.9, w: 8.4, h: 1.9,
    fontFace: F.jp, fontSize: 40, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addShape(pres.ShapeType.rect, { x: 1.0, y: 4.35, w: 0.03, h: 1.35, fill: { color: C.amber }, line: { color: C.amber } });
  s.addText('第1部　ファーマケア — 介護施設と薬剤師をつなぐ服薬管理', {
    x: 1.3, y: 4.4, w: 8.4, h: 0.4, fontFace: F.jp, fontSize: 14.5, color: 'FFFFFF', margin: 0,
  });
  s.addText('第2部　健診データをプライマリケアにどう活かすか', {
    x: 1.3, y: 5.0, w: 8.4, h: 0.4, fontFace: F.jp, fontSize: 14.5, color: 'FFFFFF', margin: 0,
  });
  s.addText('薬剤師　迫口 大晟', {
    x: 1.0, y: 6.2, w: 6, h: 0.4, fontFace: F.jp, fontSize: 13, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 第1部 扉
{
  const s = dark();
  badge(s, '1', 1.0, 2.7, 1.0, C.amber, 22);
  s.addText('ファーマケア', {
    x: 2.4, y: 2.75, w: 9, h: 0.95,
    fontFace: F.jp, fontSize: 40, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText('介護施設と薬剤師をつなぐ、服薬管理プラットフォーム', {
    x: 2.4, y: 3.75, w: 9, h: 0.45, fontFace: F.jp, fontSize: 16, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 課題
{
  const s = light();
  heading(s, '施設と薬局のあいだが、電話とFAXで止まっている');

  const before = ['薬が変わっても施設に伝わらない', '相談したいが電話がつながらない', '夜間・休日は判断材料がない'];
  const after = ['薬の情報がその場で共有される', 'チャットで時間を選ばず相談', '症状から対応の目安がすぐ出る'];

  card(s, 0.8, 2.1, 5.4, 3.6, 'F0EEEA');
  s.addText('これまで', { x: 1.2, y: 2.4, w: 3, h: 0.4, fontFace: F.jp, fontSize: 17, bold: true, color: '8A6F52', margin: 0 });
  before.forEach((t, i) => {
    s.addText(t, { x: 1.2, y: 3.15 + i * 0.78, w: 4.7, h: 0.5, fontFace: F.jp, fontSize: 14, color: '5A5044', margin: 0 });
  });

  card(s, 7.15, 2.1, 5.35, 3.6, C.wash);
  s.addText('ファーマケア', { x: 7.55, y: 2.4, w: 4, h: 0.4, fontFace: F.jp, fontSize: 17, bold: true, color: C.deep, margin: 0 });
  after.forEach((t, i) => {
    s.addText(t, { x: 7.55, y: 3.15 + i * 0.78, w: 4.6, h: 0.5, fontFace: F.jp, fontSize: 14, color: C.ink, margin: 0 });
  });

  s.addShape(pres.ShapeType.rightArrow, { x: 6.35, y: 3.7, w: 0.5, h: 0.44, fill: { color: C.amber }, line: { color: C.amber } });
  s.addText('Webブラウザだけで利用でき、アプリのインストールは不要', {
    x: 0.8, y: 6.1, w: 11.7, h: 0.4, fontFace: F.jp, fontSize: 13, color: C.inkSub, italic: true, margin: 0,
  });
}

// ══════════════════════════════════ 登録の流れ
{
  const s = light();
  heading(s, '施設をつくり、招待コードでつながる');

  const steps = [
    ['1', '施設をつくる', C.deep],
    ['2', '招待コード発行', C.mid],
    ['3', '職員が参加', C.mid],
    ['4', '入居者を登録', C.mid],
    ['5', '家族を招待', C.amber],
  ];
  steps.forEach(([n, t, col], i) => {
    const x = 0.8 + i * 2.45;
    card(s, x, 2.3, 2.1, 1.85, C.wash);
    badge(s, n, x + 0.75, 2.55, 0.6, col, 18);
    s.addText(t, {
      x: x + 0.1, y: 3.32, w: 1.9, h: 0.6,
      fontFace: F.jp, fontSize: 13.5, bold: true, color: C.deep, align: 'center', margin: 0,
    });
    if (i < 4) arrow(s, x + 2.14, 3.1, 0.24);
  });

  card(s, 0.8, 4.65, 11.7, 1.6, 'FFFFFF', 'DCE6E4');
  s.addText('役割ごとに、見えるものが違う', {
    x: 1.15, y: 4.85, w: 5, h: 0.35, fontFace: F.jp, fontSize: 14, bold: true, color: C.deep, margin: 0,
  });
  const roles = [
    ['薬剤師', '薬の登録・変更、相談対応'],
    ['介護士・看護師', '服薬記録、バイタル、症状相談'],
    ['家族', '処方とバイタルの閲覧のみ'],
  ];
  roles.forEach(([r, d], i) => {
    const x = 1.15 + i * 3.8;
    s.addText(r, { x, y: 5.3, w: 3.6, h: 0.32, fontFace: F.jp, fontSize: 13, bold: true, color: C.mid, margin: 0 });
    s.addText(d, { x, y: 5.65, w: 3.6, h: 0.4, fontFace: F.jp, fontSize: 11.5, color: C.inkSub, margin: 0 });
  });
}

// ══════════════════════════════════ 機能一覧
{
  const s = light();
  heading(s, '日々の記録から、判断の支援まで');

  const feats = [
    ['お薬手帳', 'QRコードで5秒登録\n変更履歴も自動で記録'],
    ['カレンダー', '薬剤師の訪問予定を\n施設側にも表示'],
    ['チャット', '患者ごとの相談ルーム\nリアルタイムで反映'],
    ['服薬の注意点', '添付文書から\n該当箇所だけを提示'],
    ['症状トリアージ', '体調不良時の対応の目安\nを3段階で提示'],
    ['バイタル記録', '血圧・体温・SpO2\nグラフで推移を確認'],
  ];
  feats.forEach(([t, d], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 0.8 + col * 4.05, y = 2.15 + row * 2.3;
    card(s, x, y, 3.75, 2.05, C.wash);
    // ④服薬の注意点 と ⑤症状トリアージ だけがAIを使う機能なので、その2つを差し色にする
    const isAi = i === 3 || i === 4;
    badge(s, String(i + 1), x + 0.28, y + 0.3, 0.44, isAi ? C.amber : C.mid, 14);
    s.addText(t, {
      x: x + 0.85, y: y + 0.33, w: 2.7, h: 0.4,
      fontFace: F.jp, fontSize: 16, bold: true, color: C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.3, y: y + 1.05, w: 3.2, h: 0.85,
      fontFace: F.jp, fontSize: 12, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });
  s.addText('④⑤はAIを使う機能', {
    x: 0.8, y: 6.85, w: 6, h: 0.3, fontFace: F.jp, fontSize: 11, color: C.amber, margin: 0,
  });
}

// ══════════════════════════════════ トリアージ
{
  const s = light();
  heading(s, '症状トリアージ', '体調不良のとき、その場で対応の目安がわかる');

  // 入力→判定
  card(s, 0.8, 2.0, 5.5, 2.9, C.wash);
  s.addText('スタッフが入力する', {
    x: 1.15, y: 2.25, w: 5, h: 0.35, fontFace: F.jp, fontSize: 14, bold: true, color: C.deep, margin: 0,
  });
  ['症状カテゴリー（17種類）', '重症度・発症時刻', '当てはまる危険信号'].forEach((t, i) => {
    badge(s, String(i + 1), 1.2, 2.85 + i * 0.62, 0.36, C.mid, 12);
    s.addText(t, { x: 1.75, y: 2.83 + i * 0.62, w: 4.3, h: 0.4, fontFace: F.jp, fontSize: 13, color: C.ink, margin: 0 });
  });

  s.addShape(pres.ShapeType.rightArrow, { x: 6.45, y: 3.25, w: 0.45, h: 0.4, fill: { color: C.amber }, line: { color: C.amber } });

  const levels = [
    ['OTC対応可', '市販薬で様子を見る', C.ok],
    ['薬剤師に相談', 'ワンタップで相談へ', C.warn],
    ['医療機関を受診', '速やかに受診手配', C.danger],
  ];
  levels.forEach(([t, d, col], i) => {
    const y = 2.0 + i * 1.0;
    card(s, 7.1, y, 5.4, 0.85, 'FFFFFF', col);
    s.addShape(pres.ShapeType.ellipse, { x: 7.38, y: y + 0.26, w: 0.33, h: 0.33, fill: { color: col }, line: { color: col } });
    s.addText(t, { x: 7.88, y: y + 0.11, w: 2.6, h: 0.33, fontFace: F.jp, fontSize: 14.5, bold: true, color: col, margin: 0 });
    s.addText(d, { x: 7.88, y: y + 0.45, w: 4.3, h: 0.3, fontFace: F.jp, fontSize: 11, color: C.inkSub, margin: 0 });
  });

  card(s, 0.8, 5.2, 11.7, 1.15, 'FFFFFF', 'DCE6E4');
  s.addText('判定は「ルール」で決まる。AIは説明文をつくるだけ', {
    x: 1.15, y: 5.38, w: 8, h: 0.35, fontFace: F.jp, fontSize: 14, bold: true, color: C.deep, margin: 0,
  });
  s.addText('根拠は厚生労働省の公開資料と医学書2冊。危険信号が1つでもあれば、重症度によらず受診をすすめる側に倒します。', {
    x: 1.15, y: 5.76, w: 11.1, h: 0.4, fontFace: F.jp, fontSize: 12, color: C.inkSub, margin: 0,
  });
}

// ══════════════════════════════════ AIの使い方
{
  const s = dark();
  s.addText('AIに、医学的な判断はさせない', {
    x: 0.9, y: 1.5, w: 11, h: 0.8, fontFace: F.jp, fontSize: 32, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText('もっともらしい誤りが混ざることを、医療では許容できないため', {
    x: 0.9, y: 2.35, w: 11, h: 0.4, fontFace: F.jp, fontSize: 14.5, color: C.soft, margin: 0,
  });

  const cols = [
    ['○', 'AIがやること', ['添付文書に書かれている\n該当箇所を探して見せる', '複数の薬に共通する注意点を\n重複を省いて整理する'], C.ok],
    ['×', 'AIがやらないこと', ['書かれていないことを補う', '新しい医学的判断をする', 'トリアージの判定を決める'], C.danger],
  ];
  cols.forEach(([mark, title, items, col], i) => {
    const x = 0.9 + i * 5.85;
    card(s, x, 3.15, 5.5, 3.0, '1B635C');
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.35, y: 3.42, w: 0.5, h: 0.5, fill: { color: col }, line: { color: col } });
    s.addText(mark, {
      x: x + 0.35, y: 3.42, w: 0.5, h: 0.5,
      fontFace: F.jp, fontSize: 18, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', margin: 0,
    });
    s.addText(title, {
      x: x + 1.0, y: 3.48, w: 4.2, h: 0.4, fontFace: F.jp, fontSize: 17, bold: true, color: 'FFFFFF', margin: 0,
    });
    items.forEach((t, j) => {
      s.addText(t, {
        x: x + 0.4, y: 4.2 + j * 0.62, w: 4.9, h: 0.58,
        fontFace: F.jp, fontSize: 12, color: C.soft, margin: 0, lineSpacingMultiple: 1.1,
      });
    });
  });
  s.addText('AIが使えない状況でも、判定そのものはアプリだけで返るようにしています。', {
    x: 0.9, y: 6.45, w: 11.5, h: 0.4, fontFace: F.jp, fontSize: 12.5, color: 'FFFFFF', italic: true, margin: 0,
  });
}

// ══════════════════════════════════ ガイドライン
{
  const s = light();
  heading(s, '患者情報を扱うということ',
    '医療情報システムの安全管理に関するガイドライン 第7.0版（厚生労働省）は、介護事業者・薬局も対象');

  const reqs = [
    ['二要素認証', '認証アプリの6桁\nSMSは使わない'],
    ['アクセスログ', '誰がいつ誰の情報を見たか\n改ざん・削除はできない'],
    ['自動ログアウト', '15分の無操作で\n自動サインアウト'],
    ['バックアップ', '日次・週次・任意時点\n3つの方式で保持'],
  ];
  reqs.forEach(([t, d], i) => {
    const x = 0.8 + i * 3.02;
    card(s, x, 2.2, 2.8, 2.4, 'FFFFFF', C.soft);
    badge(s, '✓', x + 0.28, 2.45, 0.44, C.mid, 14);
    s.addText(t, {
      x: x + 0.28, y: 3.1, w: 2.3, h: 0.4, fontFace: F.jp, fontSize: 15, bold: true, color: C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.28, y: 3.58, w: 2.35, h: 0.85,
      fontFace: F.jp, fontSize: 11.5, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });

  card(s, 0.8, 5.0, 11.7, 1.3, C.wash);
  s.addText('できていないことも、隠さず書いています', {
    x: 1.15, y: 5.2, w: 6, h: 0.35, fontFace: F.jp, fontSize: 14, bold: true, color: C.deep, margin: 0,
  });
  s.addText('未対応の項目を一覧にした資料を用意しています。導入をご検討いただく際、そのままご確認いただけます。', {
    x: 1.15, y: 5.6, w: 11.1, h: 0.4, fontFace: F.jp, fontSize: 12, color: C.inkSub, margin: 0,
  });
}

// ══════════════════════════════════ 第2部 扉
{
  const s = dark();
  badge(s, '2', 1.0, 2.5, 1.0, C.amber, 22);
  s.addText('健診データを\nプライマリケアにどう活かすか', {
    x: 2.4, y: 2.15, w: 10, h: 1.9,
    fontFace: F.jp, fontSize: 34, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addText('毎年集まっている特定健診データを、予防のための judgement に変える', {
    x: 2.4, y: 4.25, w: 10, h: 0.45, fontFace: F.jp, fontSize: 15, color: C.soft, margin: 0,
  });
  s.addText('事例：1年間のBRI変化と尿蛋白の新規発現（宮崎県延岡市 2020–2021年）', {
    x: 2.4, y: 5.3, w: 10, h: 0.4, fontFace: F.jp, fontSize: 13, color: 'FFFFFF', margin: 0,
  });
}

// ══════════════════════════════════ 問題意識
{
  const s = light();
  heading(s, '特定健診は、毎年とられている');

  // 現状の流れ
  const now = [
    ['受ける', '腹囲・血圧・血液検査'],
    ['結果を渡す', '基準値との比較'],
    ['保健指導', '該当者に案内'],
  ];
  now.forEach(([t, d], i) => {
    const x = 0.8 + i * 2.6;
    card(s, x, 2.15, 2.3, 1.5, C.wash);
    s.addText(t, { x: x + 0.1, y: 2.4, w: 2.1, h: 0.35, fontFace: F.jp, fontSize: 14.5, bold: true, color: C.deep, align: 'center', margin: 0 });
    s.addText(d, { x: x + 0.1, y: 2.82, w: 2.1, h: 0.6, fontFace: F.jp, fontSize: 11, color: C.inkSub, align: 'center', margin: 0 });
    if (i < 2) arrow(s, x + 2.34, 2.78, 0.22);
  });

  card(s, 8.7, 2.15, 3.8, 1.5, 'F7F2EC');
  s.addText('多くはここで終わる', {
    x: 8.95, y: 2.42, w: 3.3, h: 0.35, fontFace: F.jp, fontSize: 13.5, bold: true, color: '8A6F52', margin: 0,
  });
  s.addText('「今」の値は分かるが、\n変化は活かされにくい', {
    x: 8.95, y: 2.82, w: 3.3, h: 0.6, fontFace: F.jp, fontSize: 11.5, color: '5A5044', margin: 0, lineSpacingMultiple: 1.15,
  });

  // 問い
  card(s, 0.8, 4.15, 11.7, 2.1, C.deep);
  s.addText('問い', {
    x: 1.2, y: 4.4, w: 2, h: 0.4, fontFace: F.jp, fontSize: 15, bold: true, color: C.amber, margin: 0,
  });
  s.addText('毎年同じ人を測っているのだから、\n「去年からどう変わったか」でリスクを見られないか。', {
    x: 1.2, y: 4.85, w: 11, h: 1.1,
    fontFace: F.jp, fontSize: 21, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.3,
  });
}

// ══════════════════════════════════ 事例(BRI)
{
  const s = light();
  heading(s, '事例：からだの「まるみ」の変化を見る',
    '腹囲と身長だけで計算できる指標 BRI（Body Roundness Index）');

  // 3ステップ
  const steps = [
    ['見たもの', '延岡市の40歳以上\n3,819名の2年分'],
    ['調べたこと', '1年間でBRIが\n増えた／減った／横ばい'],
    ['分かったこと', '増えた群で尿蛋白が\n新たに出やすかった'],
  ];
  steps.forEach(([t, d], i) => {
    const x = 0.8 + i * 4.05;
    card(s, x, 2.15, 3.75, 1.9, i === 2 ? C.deep : C.wash);
    s.addText(t, {
      x: x + 0.25, y: 2.4, w: 3.3, h: 0.4,
      fontFace: F.jp, fontSize: 15, bold: true, color: i === 2 ? C.amber : C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.25, y: 2.9, w: 3.3, h: 0.9,
      fontFace: F.jp, fontSize: 13, color: i === 2 ? 'FFFFFF' : C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });

  // 結果チャート
  s.addChart(pres.ChartType.bar, [{
    name: 'オッズ比',
    labels: ['減った', '横ばい（基準）', '増えた'],
    values: [1.16, 1.00, 1.38],
  }], {
    x: 0.8, y: 4.3, w: 6.6, h: 2.4,
    barDir: 'bar',
    chartColors: [C.mid],
    showValue: true, dataLabelPosition: 'outEnd',
    dataLabelColor: C.ink, dataLabelFontSize: 12, dataLabelFontFace: 'Calibri',
    // 書式を指定しないと 1.38 が「1」に丸められて表示される
    dataLabelFormatCode: '0.00',
    showLegend: false,
    showTitle: true, title: '尿蛋白が新たに出るリスク（オッズ比）',
    titleColor: C.deep, titleFontSize: 12.5, titleFontFace: F.jp,
    catAxisLabelColor: C.ink, catAxisLabelFontSize: 11.5, catAxisLabelFontFace: F.jp,
    valAxisLabelColor: C.inkSub, valAxisLabelFontSize: 9,
    valAxisMinVal: 0, valAxisMaxVal: 1.8,
    valGridLine: { color: 'E4EDEB', size: 1 },
    catGridLine: { style: 'none' },
    barGapWidthPct: 55,
  });

  card(s, 7.7, 4.3, 4.8, 2.4, C.wash);
  s.addText('尿蛋白に注目する理由', {
    x: 8.0, y: 4.55, w: 4.2, h: 0.35, fontFace: F.jp, fontSize: 13.5, bold: true, color: C.deep, margin: 0,
  });
  s.addText('腎機能の低下（eGFR）より先に\n出てくることが多く、\n早い段階で気づける指標です。', {
    x: 8.0, y: 4.98, w: 4.3, h: 1.0,
    fontFace: F.jp, fontSize: 12, color: C.ink, margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addText('BRIが増えた群のリスク上昇は、\nBMIの変化を調整しても残りました。', {
    x: 8.0, y: 6.02, w: 4.3, h: 0.6,
    fontFace: F.jp, fontSize: 11.5, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
  });
}

// ══════════════════════════════════ どう活かすか(中核)
{
  const s = light();
  heading(s, 'どう現場で使えるか', '研究を、健診の場での実践につなげる');

  const uses = [
    ['①', '道具がいらない', 'メジャーと身長計だけ。\n特別な検査機器は不要で、\nどの健診会場でも計算できる'],
    ['②', '声のかけ方が変わる', '「太っています」ではなく\n「去年より増えています」。\n変化なら本人も実感しやすい'],
    ['③', '優先順位がつけられる', '限られた保健指導の枠を、\nリスクが上がった人に\n優先して充てられる'],
  ];
  uses.forEach(([n, t, d], i) => {
    const x = 0.8 + i * 4.05;
    card(s, x, 2.15, 3.75, 2.85, C.wash);
    badge(s, n, x + 0.28, 2.42, 0.5, C.amber, 15);
    s.addText(t, {
      x: x + 0.28, y: 3.1, w: 3.3, h: 0.4,
      fontFace: F.jp, fontSize: 15.5, bold: true, color: C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.28, y: 3.6, w: 3.3, h: 1.25,
      fontFace: F.jp, fontSize: 12, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.3,
    });
  });

  card(s, 0.8, 5.35, 11.7, 1.25, C.deep);
  s.addText('研究の目的は、論文を書くことではなく、明日の声かけを変えること', {
    x: 1.2, y: 5.62, w: 11, h: 0.5,
    fontFace: F.jp, fontSize: 18, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addNotes('この資料の中心メッセージ。データ→研究→現場の実践、という流れを示す。');
}

// ══════════════════════════════════ 限界(誠実さ)
{
  const s = light();
  heading(s, '言えること、言えないこと');

  card(s, 0.8, 2.2, 5.6, 3.3, C.wash);
  s.addText('言えること', { x: 1.15, y: 2.45, w: 4, h: 0.4, fontFace: F.jp, fontSize: 16, bold: true, color: C.deep, margin: 0 });
  ['1年間でBRIが増えた人は、\n尿蛋白が新たに出やすかった', '体重や BMI の変化を\n考慮しても、その傾向は残った'].forEach((t, i) => {
    s.addText(t, { x: 1.15, y: 3.1 + i * 1.1, w: 5.0, h: 0.85, fontFace: F.jp, fontSize: 13, color: C.ink, margin: 0, lineSpacingMultiple: 1.25 });
  });

  card(s, 7.0, 2.2, 5.5, 3.3, 'F7F2EC');
  s.addText('言えないこと', { x: 7.35, y: 2.45, w: 4, h: 0.4, fontFace: F.jp, fontSize: 16, bold: true, color: '8A6F52', margin: 0 });
  ['BRIを下げれば腎臓が守れる、\nという因果関係', '1年という短い観察なので、\n一時的な変動の影響もありうる', '延岡市の健診受診者が対象。\nそのまま他地域には広げられない'].forEach((t, i) => {
    s.addText(t, { x: 7.35, y: 3.05 + i * 0.85, w: 4.9, h: 0.75, fontFace: F.jp, fontSize: 12.5, color: '5A5044', margin: 0, lineSpacingMultiple: 1.2 });
  });

  s.addText('次に必要なのは、複数地域・長期の追跡と、介入して確かめる研究です。', {
    x: 0.8, y: 5.85, w: 11.7, h: 0.4, fontFace: F.jp, fontSize: 13, color: C.inkSub, italic: true, margin: 0,
  });
}

// ══════════════════════════════════ 締め
{
  const s = dark();
  s.addShape(pres.ShapeType.ellipse, { x: -1.8, y: 4.0, w: 5.2, h: 5.2, fill: { color: '1B635C' }, line: { color: '1B635C' } });

  s.addText('ふたつに共通していること', {
    x: 1.0, y: 1.5, w: 11, h: 0.8, fontFace: F.jp, fontSize: 30, bold: true, color: 'FFFFFF', margin: 0,
  });

  const two = [
    ['ファーマケア', '施設で毎日とっている\n服薬・症状の記録を、\nその場の判断につなげる'],
    ['健診データの研究', '毎年とっている健診の値を、\n変化として読み、\n予防の優先順位につなげる'],
  ];
  two.forEach(([t, d], i) => {
    const x = 1.0 + i * 5.85;
    card(s, x, 2.6, 5.5, 2.1, '1B635C');
    s.addText(t, { x: x + 0.4, y: 2.85, w: 4.7, h: 0.4, fontFace: F.jp, fontSize: 18, bold: true, color: C.amber, margin: 0 });
    s.addText(d, { x: x + 0.4, y: 3.35, w: 4.8, h: 1.1, fontFace: F.jp, fontSize: 13, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.3 });
  });

  s.addShape(pres.ShapeType.rect, { x: 1.0, y: 5.35, w: 11.35, h: 0.02, fill: { color: '2A7268' }, line: { color: '2A7268' } });
  s.addText('すでに手元にあるデータを、次の一手に変える。', {
    x: 1.0, y: 5.7, w: 11.3, h: 0.6,
    fontFace: F.jp, fontSize: 22, bold: true, color: 'FFFFFF', margin: 0,
  });
}

pres.writeFile({ fileName: 'C:/Users/OWNER/pharmacist_app/PharmaCare_紹介資料.pptx' })
  .then(f => console.log('作成しました:', f));
