// 紹介用スライド生成スクリプト。
//   node build_deck.js
// 出力: PharmaCare_紹介資料.pptx
//
// 方針:
//   - 読ませる資料ではなく、見せる資料。1スライド1メッセージ。
//   - 第1部はアプリ、第2部は「健診データをどうプライマリケアに活かすか」。
//     BRI研究はそのテーマの事例として置く。
//   - 投影して後ろの席から読めることを優先し、本文は15pt以上を下限にする。
//     文字を大きくした分だけ文章を削る（情報量ではなく密度を下げる）。

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
  card: '1B635C', // 暗色スライド上のカード
  accentLabel: '1F6F78', // 明るい面に置く小見出し用(deepより一段明るい)
};

const F = { jp: 'Yu Gothic' };

// ── 文字サイズの基準 ──────────────────────────────────
// 個別に数値を書くとスライドごとにばらつくので、必ずここを経由する。
const T = {
  hero: 40,      // 表紙・扉の主見出し
  title: 36,     // スライドタイトル
  sub: 16,       // タイトル下の一行説明
  lead: 22,      // 強調したい一文
  cardTitle: 19, // カード見出し
  body: 15,      // 本文
  small: 13,     // 補足・注記
  badge: 17,     // 円形バッジの中の数字
};

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE'; // 13.3 x 7.5 inch
pres.author = 'PharmaCare';
pres.title = 'ファーマケア 紹介資料';

// ── 部品 ───────────────────────────────────────────────
const dark = () => { const s = pres.addSlide(); s.background = { color: C.deep }; return s; };
const light = () => { const s = pres.addSlide(); s.background = { color: C.paper }; return s; };

function heading(s, text, sub) {
  s.addText(text, {
    x: 0.8, y: 0.45, w: 11.7, h: 0.85,
    fontFace: F.jp, fontSize: T.title, bold: true, color: C.deep, margin: 0,
  });
  if (sub) {
    s.addText(sub, {
      x: 0.8, y: 1.34, w: 11.7, h: 0.45,
      fontFace: F.jp, fontSize: T.sub, color: C.inkSub, margin: 0,
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
    fontFace: F.jp, fontSize: fontSize || T.badge, bold: true,
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
  s.addShape(pres.ShapeType.ellipse, { x: 9.8, y: -1.6, w: 5.6, h: 5.6, fill: { color: C.card }, line: { color: C.card } });
  s.addShape(pres.ShapeType.ellipse, { x: 11.4, y: 4.4, w: 3.2, h: 3.2, fill: { color: C.card }, line: { color: C.card } });

  s.addText('現場のデータを、\n次の一手につなげる', {
    x: 1.0, y: 1.75, w: 8.6, h: 2.0,
    fontFace: F.jp, fontSize: 44, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addShape(pres.ShapeType.rect, { x: 1.0, y: 4.3, w: 0.04, h: 1.5, fill: { color: C.amber }, line: { color: C.amber } });
  s.addText('第1部　ファーマケア — 介護施設と薬剤師をつなぐ服薬管理', {
    x: 1.35, y: 4.32, w: 8.6, h: 0.5, fontFace: F.jp, fontSize: T.sub, color: 'FFFFFF', margin: 0,
  });
  s.addText('第2部　健診データをプライマリケアにどう活かすか', {
    x: 1.35, y: 5.05, w: 8.6, h: 0.5, fontFace: F.jp, fontSize: T.sub, color: 'FFFFFF', margin: 0,
  });
  s.addText('薬剤師　迫口 大晟', {
    x: 1.0, y: 6.25, w: 6, h: 0.45, fontFace: F.jp, fontSize: T.body, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 第1部 扉
{
  const s = dark();
  badge(s, '1', 1.0, 2.65, 1.1, C.amber, 26);
  s.addText('ファーマケア', {
    x: 2.5, y: 2.6, w: 9.5, h: 1.0,
    fontFace: F.jp, fontSize: T.hero, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText('介護施設と薬剤師をつなぐ、服薬管理プラットフォーム', {
    x: 2.5, y: 3.68, w: 9.5, h: 0.5, fontFace: F.jp, fontSize: 18, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 課題
{
  const s = light();
  heading(s, '施設と薬局のあいだが、電話とFAXで止まっている');

  const before = ['薬が変わっても伝わらない', '相談したいがつながらない', '夜間・休日は判断材料がない'];
  const after = ['薬の情報がその場で共有される', '時間を選ばずチャットで相談', '症状から対応の目安が出る'];

  card(s, 0.8, 2.15, 5.4, 3.8, 'F0EEEA');
  s.addText('これまで', { x: 1.2, y: 2.45, w: 3, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: '8A6F52', margin: 0 });
  before.forEach((t, i) => {
    s.addText(t, { x: 1.2, y: 3.25 + i * 0.82, w: 4.8, h: 0.55, fontFace: F.jp, fontSize: T.body, color: '5A5044', margin: 0 });
  });

  card(s, 7.15, 2.15, 5.35, 3.8, C.wash);
  s.addText('ファーマケア', { x: 7.55, y: 2.45, w: 4, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.deep, margin: 0 });
  after.forEach((t, i) => {
    s.addText(t, { x: 7.55, y: 3.25 + i * 0.82, w: 4.7, h: 0.55, fontFace: F.jp, fontSize: T.body, color: C.ink, margin: 0 });
  });

  s.addShape(pres.ShapeType.rightArrow, { x: 6.35, y: 3.85, w: 0.5, h: 0.44, fill: { color: C.amber }, line: { color: C.amber } });
  s.addText('Webブラウザだけで利用でき、アプリのインストールは不要', {
    x: 0.8, y: 6.25, w: 11.7, h: 0.45, fontFace: F.jp, fontSize: T.small, color: C.inkSub, italic: true, margin: 0,
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
    card(s, x, 2.25, 2.1, 2.0, C.wash);
    badge(s, n, x + 0.75, 2.5, 0.62, col, 20);
    s.addText(t, {
      x: x + 0.02, y: 3.35, w: 2.06, h: 0.75,
      fontFace: F.jp, fontSize: T.body, bold: true, color: C.deep, align: 'center', margin: 0,
    });
    if (i < 4) arrow(s, x + 2.14, 3.15, 0.24);
  });

  card(s, 0.8, 4.75, 11.7, 1.8, 'FFFFFF', 'DCE6E4');
  s.addText('役割ごとに、見えるものが違う', {
    x: 1.15, y: 4.98, w: 6, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.deep, margin: 0,
  });
  const roles = [
    ['薬剤師', '薬の登録・変更、相談対応'],
    ['介護士・看護師', '服薬記録、バイタル、症状相談'],
    ['家族', '処方とバイタルの閲覧のみ'],
  ];
  roles.forEach(([r, d], i) => {
    const x = 1.15 + i * 3.8;
    s.addText(r, { x, y: 5.5, w: 3.6, h: 0.35, fontFace: F.jp, fontSize: T.body, bold: true, color: C.mid, margin: 0 });
    s.addText(d, { x, y: 5.9, w: 3.65, h: 0.45, fontFace: F.jp, fontSize: T.small, color: C.inkSub, margin: 0 });
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
    ['記録の書面出力', '保管中の記録を\nそのまま印刷できる'],
  ];
  feats.forEach(([t, d], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 0.8 + col * 4.05, y = 2.1 + row * 2.35;
    card(s, x, y, 3.75, 2.15, C.wash);
    // ④服薬の注意点 と ⑤症状トリアージ だけがAIを使う機能なので、その2つを差し色にする
    const isAi = i === 3 || i === 4;
    badge(s, String(i + 1), x + 0.26, y + 0.28, 0.5, isAi ? C.amber : C.mid, T.small + 1);
    s.addText(t, {
      x: x + 0.88, y: y + 0.3, w: 2.8, h: 0.45,
      fontFace: F.jp, fontSize: T.cardTitle - 1, bold: true, color: C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.28, y: y + 1.05, w: 3.25, h: 0.95,
      fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });
  s.addText('④⑤はAIを使う機能', {
    x: 0.8, y: 6.85, w: 6, h: 0.35, fontFace: F.jp, fontSize: T.small, color: C.amber, margin: 0,
  });
}

// ══════════════════════════════════ トリアージ
{
  const s = light();
  // 「トリアージ」は医療の用語で、初めて聞く人には通じない。
  // 副題ではなく見出しの側で、何をする機能なのかを言い切る。
  heading(s, '体調不良のとき、様子を見てよいか迷わない',
    '症状トリアージ ― 聞き取った内容から、対応の目安を3段階で示します');

  card(s, 0.8, 2.05, 5.5, 3.1, C.wash);
  s.addText('スタッフが入力する', {
    x: 1.15, y: 2.28, w: 5, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.deep, margin: 0,
  });
  ['症状カテゴリー（17種類）', '重症度・発症時刻', '当てはまる危険信号'].forEach((t, i) => {
    badge(s, String(i + 1), 1.2, 2.95 + i * 0.66, 0.4, C.mid, T.small);
    s.addText(t, { x: 1.78, y: 2.95 + i * 0.66, w: 4.4, h: 0.42, fontFace: F.jp, fontSize: T.body, color: C.ink, margin: 0 });
  });

  s.addShape(pres.ShapeType.rightArrow, { x: 6.45, y: 3.35, w: 0.45, h: 0.42, fill: { color: C.amber }, line: { color: C.amber } });

  // 「OTC」は業界語なので出さない。3段階が何を指すかだけが伝わればよい。
  const levels = [
    ['市販薬で様子を見る', '緊急性は低いと考えられる', C.ok],
    ['薬剤師に相談', 'ワンタップで相談へつながる', C.warn],
    ['医療機関を受診', '速やかに受診の手配を', C.danger],
  ];
  levels.forEach(([t, d, col], i) => {
    const y = 2.05 + i * 1.06;
    card(s, 7.1, y, 5.4, 0.94, 'FFFFFF', col);
    s.addShape(pres.ShapeType.ellipse, { x: 7.38, y: y + 0.28, w: 0.36, h: 0.36, fill: { color: col }, line: { color: col } });
    s.addText(t, { x: 7.92, y: y + 0.1, w: 2.9, h: 0.38, fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: col, margin: 0 });
    s.addText(d, { x: 7.92, y: y + 0.5, w: 4.3, h: 0.34, fontFace: F.jp, fontSize: T.small, color: C.inkSub, margin: 0 });
  });

  card(s, 0.8, 5.4, 11.7, 1.35, C.deep);
  s.addText('判定はルールで決まる。AIは説明文をつくるだけ', {
    x: 1.2, y: 5.6, w: 8.5, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText('危険信号が1つでもあれば、重症度によらず受診をすすめる側に倒します。', {
    x: 1.2, y: 6.08, w: 11.0, h: 0.42, fontFace: F.jp, fontSize: T.body, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 根拠(原典照合)
{
  const s = light();
  // 「原本を確かめた」は、やって当たり前のこと。資料で言うべきなのは、
  // そのあとに何をしたか — 医師向けの基準を、介護職が答えられる質問に直した点。
  heading(s, '医師向けの基準を、介護職が答えられる言葉に',
    '危険信号118項目は、すべて公開資料か医学書に紐づいています');

  const srcs = [
    ['厚生労働省の公開資料', '症候別トリアージの\n枠組みと症候の分類'],
    ['アルゴリズムで考える\n薬剤師の臨床判断', '15症候それぞれの\n「見逃してはいけない疾患」'],
    ['薬学臨床推論', 'なぜその判定になるかの\n考え方'],
  ];
  srcs.forEach(([t, d], i) => {
    const x = 0.8 + i * 4.05;
    card(s, x, 2.15, 3.75, 2.1, C.wash);
    s.addText(t, {
      x: x + 0.3, y: 2.38, w: 3.2, h: 0.75,
      fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: C.deep, margin: 0, lineSpacingMultiple: 1.1,
    });
    s.addText(d, {
      x: x + 0.3, y: 3.2, w: 3.2, h: 0.85,
      fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });

  // 成果を数字で。数字の幅が3桁と1桁で変わるので、ラベルは横ではなく真下に置く
  const stats = [
    ['118', '実装した危険信号'],
    ['17', '対応する症候'],
    ['3', '照合した文献'],
  ];
  stats.forEach(([n, l], i) => {
    const x = 0.8 + i * 4.05;
    s.addText(n, {
      x, y: 4.4, w: 3.75, h: 0.85, fontFace: 'Calibri', fontSize: 54, bold: true, color: C.amber, margin: 0,
    });
    s.addText(l, {
      x, y: 5.22, w: 3.75, h: 0.42, fontFace: F.jp, fontSize: T.body, color: C.inkSub, margin: 0,
    });
  });

  // 開発の経緯(過剰警告を是正した等)は、初めて見る人には前提が無く伝わらない。
  // 代わりに、翻訳という一番の手間を具体例で見せる。
  card(s, 0.8, 5.75, 11.7, 1.15, C.wash);
  s.addText('例：「Centorの基準で3点以上」→「口を大きく開けられない」', {
    x: 1.2, y: 5.92, w: 11.0, h: 0.4,
    fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: C.deep, margin: 0,
  });
  s.addText('白苔を見る、リンパ節を触る。診察が要る指標は使えないので、見ればわかる質問に置き換えています。', {
    x: 1.2, y: 6.36, w: 11.0, h: 0.4, fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0,
  });
  s.addNotes('資料の要点は「出典がある」ことではなく「専門職でなくても答えられる形に直した」こと。ここが一番手間のかかった部分。');
}

// ══════════════════════════════════ AIの使い方
{
  const s = dark();
  s.addText('AIに、医学的な判断はさせない', {
    x: 0.9, y: 1.35, w: 11.5, h: 0.9, fontFace: F.jp, fontSize: T.title, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText('もっともらしい誤りが混ざることを、医療では許容できないため', {
    x: 0.9, y: 2.3, w: 11.5, h: 0.45, fontFace: F.jp, fontSize: T.sub, color: C.soft, margin: 0,
  });

  const cols = [
    // 丸バッジの中に「○」を置くと二重丸に見えるので、記号はチェックと×にする
    ['✓', 'AIがやること', ['添付文書の該当箇所を\n探して見せる', '複数の薬に共通する注意点を\n重複を省いて整理する'], C.ok],
    ['✕', 'AIがやらないこと', ['書かれていないことを補う', '新しい医学的判断をする', 'トリアージの判定を決める'], C.danger],
  ];
  cols.forEach(([mark, title, items, col], i) => {
    const x = 0.9 + i * 5.85;
    card(s, x, 3.1, 5.5, 3.15, C.card);
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.35, y: 3.38, w: 0.55, h: 0.55, fill: { color: col }, line: { color: col } });
    s.addText(mark, {
      x: x + 0.35, y: 3.38, w: 0.55, h: 0.55,
      fontFace: F.jp, fontSize: 20, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', margin: 0,
    });
    s.addText(title, {
      x: x + 1.05, y: 3.42, w: 4.2, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: 'FFFFFF', margin: 0,
    });
    items.forEach((t, j) => {
      s.addText(t, {
        x: x + 0.38, y: 4.15 + j * 0.68, w: 4.95, h: 0.62,
        fontFace: F.jp, fontSize: T.small + 1, color: C.soft, margin: 0, lineSpacingMultiple: 1.15,
      });
    });
  });
  s.addText('AIが使えない状況でも、判定そのものはアプリだけで返ります。', {
    x: 0.9, y: 6.55, w: 11.5, h: 0.45, fontFace: F.jp, fontSize: T.body, color: 'FFFFFF', italic: true, margin: 0,
  });
}

// ══════════════════════════════════ ガイドライン
{
  const s = light();
  heading(s, '患者情報を扱うということ', '2つのガイドラインに照らして確認しています');

  // 改行位置は明示する。自動折り返しに任せると「第7.0／版」のように末尾1文字が
  // 次行に落ちて読みにくくなる。
  const gls = [
    ['医療情報システムの\n安全管理に関するガイドライン 第7.0版', '厚生労働省', '守るのは利用施設。\nそれを支える機能を提供します', C.mid],
    ['医療情報を取り扱う情報システム・サービスの\n提供事業者における安全管理ガイドライン 第2.0版', '総務省・経済産業省', 'こちらは私たちが名宛人。\n提供者として直接守る側です', C.amber],
  ];
  gls.forEach(([t, org, d, col], i) => {
    const x = 0.8 + i * 6.0;
    card(s, x, 2.0, 5.7, 2.25, i === 1 ? C.wash : 'FFFFFF', i === 1 ? C.amber : 'DCE6E4');
    s.addText(org, {
      x: x + 0.3, y: 2.18, w: 5.1, h: 0.35, fontFace: F.jp, fontSize: T.small, bold: true, color: col, margin: 0,
    });
    s.addText(t, {
      x: x + 0.3, y: 2.55, w: 5.1, h: 0.85,
      fontFace: F.jp, fontSize: T.small + 1, bold: true, color: C.deep, margin: 0, lineSpacingMultiple: 1.1,
    });
    s.addText(d, {
      x: x + 0.3, y: 3.42, w: 5.1, h: 0.65,
      fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.15,
    });
  });

  card(s, 0.8, 4.55, 11.7, 2.2, C.deep);
  s.addText('どちらも「何を求めているか」から実装を決めています', {
    x: 1.2, y: 4.8, w: 10.5, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addText(
    '条文を先に読み、そこから必要な機能を起こしました。次の2枚で、要求事項と実装の対応を示します。',
    { x: 1.2, y: 5.3, w: 10.6, h: 0.45, fontFace: F.jp, fontSize: T.body, color: C.soft, margin: 0 });
  s.addText('できていないことも、この章の最後にそのまま並べています。', {
    x: 1.2, y: 5.95, w: 10.6, h: 0.45, fontFace: F.jp, fontSize: T.body, color: C.amber, margin: 0,
  });
}

// ══════════════════════════════════ 要求事項→実装 の対応表を描く共通処理
//
// 「どの条文に対して、何を作ったか」を1行で並べる。左が求められていること、
// 右がコード上の実体。抽象論に見えないよう、右側には必ずファイル名か具体値を置く。
function requirementTable(title, sub, rows, note) {
  const s = light();
  heading(s, title, sub);

  const top = 2.05;
  const rowH = 0.86;

  // 見出し行
  s.addText('ガイドラインが求めていること', {
    x: 1.1, y: top, w: 5.6, h: 0.35,
    fontFace: F.jp, fontSize: T.small, bold: true, color: C.inkSub, margin: 0,
  });
  s.addText('実装', {
    x: 7.2, y: top, w: 5.3, h: 0.35,
    fontFace: F.jp, fontSize: T.small, bold: true, color: C.inkSub, margin: 0,
  });

  rows.forEach(([ref, req, impl], i) => {
    const y = top + 0.45 + i * rowH;
    card(s, 0.8, y, 11.7, rowH - 0.1, i % 2 === 0 ? C.wash : 'FFFFFF', 'DCE6E4');

    // 条文番号。どこ由来かを必ず添える
    s.addText(ref, {
      x: 1.1, y: y + 0.1, w: 5.6, h: 0.3,
      fontFace: F.jp, fontSize: T.small - 1, bold: true, color: C.amber, margin: 0,
    });
    s.addText(req, {
      x: 1.1, y: y + 0.38, w: 5.6, h: 0.36,
      fontFace: F.jp, fontSize: T.body, color: C.ink, margin: 0,
    });

    // 対応を示す矢印
    s.addShape(pres.ShapeType.rightArrow, {
      x: 6.85, y: y + 0.28, w: 0.28, h: 0.22,
      fill: { color: C.soft }, line: { color: C.soft },
    });

    s.addText(impl, {
      x: 7.2, y: y + 0.24, w: 5.2, h: 0.42,
      fontFace: F.jp, fontSize: T.body, bold: true, color: C.deep, margin: 0,
    });
  });

  if (note) {
    s.addText(note, {
      x: 0.8, y: top + 0.45 + rows.length * rowH + 0.15, w: 11.7, h: 0.4,
      fontFace: F.jp, fontSize: T.small, color: C.inkSub, italic: true, margin: 0,
    });
  }
}

// ══════════════════════════════════ 厚労省ガイドラインとの対応
requirementTable(
  '施設が守る側の要求に、機能で応える',
  '医療情報システムの安全管理に関するガイドライン 第7.0版（厚生労働省）',
  [
    ['システム運用編 14 遵守事項⑤', '令和9年4月までに二要素認証を採用', '認証アプリの6桁（TOTP）'],
    ['同 14.2', 'アクセス権限は必要最小限に', 'Firestoreルールで施設・ロール単位に分離'],
    ['同 17①', '誰がいつ何を見たかを残す', '監査ログ。変更は前後の値まで記録'],
    ['同 17②③', 'ログの改ざんを防ぐ', '追記のみ。更新と削除を禁止'],
    ['同 12.3.2', '離席時に画面をロックする', '15分の無操作で自動サインアウト'],
  ],
  '※ 二要素認証はアカウント作成時に登録必須です。設定を終えるまでアプリ本体には入れません。',
);

// ══════════════════════════════════ 事業者ガイドラインとの対応
requirementTable(
  '提供者として直接問われる要求',
  '医療情報を取り扱う情報システム・サービスの提供事業者における安全管理ガイドライン 第2.0版',
  [
    ['6.1', '国内法の執行が及ぶ範囲に置く', 'データ・処理系とも東京リージョン'],
    ['6.2 真正性', '改変の事実と、その内容を残す', '変更前後の値・作成者・サーバー時刻'],
    ['6.2 見読性', '画面表示に加え、書面を作成できる', '記録の印刷機能'],
    ['6.2 保存性', '期間中は復元できる状態を保つ', '任意時点への復元・削除保護'],
    ['4.1／4.2', '医療機関へ所定の項目を開示し、役割分担を明確にする', 'サービス仕様適合開示書'],
  ],
  '※ このガイドラインは医療機関ではなく、システムを提供する事業者そのものが名宛人です。',
);

// ══════════════════════════════════ 電子保存の3原則をかみ砕く
//
// 「真正性・見読性・保存性」は法令用語で、字面からは中身が想像できない。
// 前ページの表だけでは「で、何をしたの?」が残るので、
// 何のための決まりか → どんな場面で効くか → このアプリで何をしたか、の順に開く。
{
  const s = light();
  heading(s, '紙のカルテと同じ信頼を、データで担保する',
    '前ページの「真正性・見読性・保存性」は、かみ砕くとこの3つです');

  const principles = [
    [
      '真正性', 'あとから書き換えられていないこと',
      'アレルギーが「あり」から「なし」に\n変わっていたとして、それが正規の\n訂正なのか分からなければ、\nその記録は使えません。',
      '誰が・いつ・何を・どう変えたかを\n変更前の値ごと残します。\n記録そのものの書き換えと削除は、\n仕組みとして禁止しています。',
    ],
    [
      '見読性', '必要なときに読み出せること',
      '行政の調査や監査では、記録の\n提出を求められます。画面で\n見えるだけでは足りず、紙に\n出せる必要があります。',
      '入居者ごとの記録を、そのまま\n印刷できるようにしました。\n印刷したこと自体も、\n持ち出しとして記録に残します。',
    ],
    [
      '保存性', '保存期間中は失われないこと',
      '誤操作や障害でデータが壊れても、\n決められた期間は元に戻せなければ\nなりません。',
      '過去7日間の任意の時点まで\n巻き戻せます。データベース\n自体の誤削除も、設定で\nできないようにしています。',
    ],
  ];

  principles.forEach(([name, lead, why, how], i) => {
    const x = 0.8 + i * 4.05;

    // 見出し帯
    card(s, x, 2.0, 3.75, 0.92, C.deep);
    s.addText(name, {
      x: x + 0.25, y: 2.1, w: 3.2, h: 0.36,
      fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.amber, margin: 0,
    });
    s.addText(lead, {
      x: x + 0.25, y: 2.5, w: 3.3, h: 0.34,
      fontFace: F.jp, fontSize: T.small, color: 'FFFFFF', margin: 0,
    });

    // なぜ要るのか
    card(s, x, 3.0, 3.75, 1.85, C.wash);
    s.addText('なぜ要るのか', {
      x: x + 0.25, y: 3.14, w: 3.2, h: 0.3,
      fontFace: F.jp, fontSize: T.small - 1, bold: true, color: C.inkSub, margin: 0,
    });
    s.addText(why, {
      x: x + 0.25, y: 3.46, w: 3.3, h: 1.3,
      fontFace: F.jp, fontSize: T.small, color: C.ink, margin: 0, lineSpacingMultiple: 1.25,
    });

    // このアプリでは
    card(s, x, 4.95, 3.75, 1.85, 'FFFFFF', C.soft);
    s.addText('このアプリでは', {
      x: x + 0.25, y: 5.09, w: 3.2, h: 0.3,
      fontFace: F.jp, fontSize: T.small - 1, bold: true, color: C.accentLabel, margin: 0,
    });
    s.addText(how, {
      x: x + 0.25, y: 5.41, w: 3.3, h: 1.3,
      fontFace: F.jp, fontSize: T.small, color: C.ink, margin: 0, lineSpacingMultiple: 1.25,
    });
  });

  s.addText('この3つは、紙のカルテで当たり前に成り立っていたことを、電子でも同じ水準にするための決まりです。', {
    x: 0.8, y: 6.95, w: 11.7, h: 0.4,
    fontFace: F.jp, fontSize: T.small, color: C.inkSub, italic: true, margin: 0,
  });
}

// ══════════════════════════════════ 未対応（正直に出す）
{
  const s = light();
  heading(s, 'できていないこと', '導入をご検討いただく前に、こちらからお伝えします');

  const gaps = [
    ['プライバシーマーク／ISMS認証', '未取得',
      '事業者ガイドライン4.4が求めています。技術的な工夫では\n代替できず、審査期間と費用がかかるため事業判断が要ります。'],
    ['第三者による安全管理の評価', '未実施',
      '同4.3。現状は内部での確認に留まっています。'],
    ['監査ログを施設側で確認する画面', '未実装',
      'システム運用編17①は、記録するだけでなく定期的に確認することまで\n求めています。記録と権限は揃っているので、閲覧画面を足せば満たせます。'],
  ];
  gaps.forEach(([t, state, d], i) => {
    const y = 2.15 + i * 1.5;
    card(s, 0.8, y, 11.7, 1.32, C.wash);
    s.addText(t, {
      x: 1.15, y: y + 0.16, w: 6.2, h: 0.4,
      fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.deep, margin: 0,
    });
    // 状態のバッジ
    card(s, 7.6, y + 0.18, 1.5, 0.42, C.amber);
    s.addText(state, {
      x: 7.6, y: y + 0.18, w: 1.5, h: 0.42,
      fontFace: F.jp, fontSize: T.small, bold: true, color: 'FFFFFF',
      align: 'center', valign: 'middle', margin: 0,
    });
    s.addText(d, {
      x: 1.15, y: y + 0.6, w: 10.9, h: 0.62,
      fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });

  card(s, 0.8, 6.7, 11.7, 0.65, C.deep);
  s.addText('未対応の一覧は開示書にそのまま載せています。ご確認のうえ判断してください。', {
    x: 1.2, y: 6.83, w: 10.8, h: 0.4,
    fontFace: F.jp, fontSize: T.body, color: 'FFFFFF', margin: 0,
  });
  s.addNotes('隠さず出すことが、医療情報を預かる事業者としての信頼につながる。指摘される前に自分から言う。');
}

// ══════════════════════════════════ 第2部 扉
{
  const s = dark();
  badge(s, '2', 1.0, 2.45, 1.1, C.amber, 26);
  s.addText('健診データを\nプライマリケアにどう活かすか', {
    x: 2.5, y: 2.05, w: 10.2, h: 2.0,
    fontFace: F.jp, fontSize: 38, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addText('毎年集まっている特定健診データを、予防のための判断に変える', {
    x: 2.5, y: 4.3, w: 10.2, h: 0.5, fontFace: F.jp, fontSize: 18, color: C.soft, margin: 0,
  });
  // ここまでは施設のアプリの話だった。なぜ急に健診の研究が出てくるのか、
  // 最後の1枚まで説明が無いと、別々の話が2つ並んでいるようにしか読めない。
  // 扉で先に橋を架けておく。
  card(s, 2.5, 5.15, 10.2, 1.25, C.card);
  s.addText('第1部と同じ考え方です。', {
    x: 2.85, y: 5.32, w: 9.6, h: 0.4,
    fontFace: F.jp, fontSize: T.body, bold: true, color: C.amber, margin: 0,
  });
  s.addText('すでに手元にあるデータを、その場の判断につなげる。第1部は施設の服薬記録で、第2部は健診の数値です。', {
    x: 2.85, y: 5.75, w: 9.6, h: 0.45,
    fontFace: F.jp, fontSize: T.small + 1, color: 'FFFFFF', margin: 0,
  });

  s.addText('事例：1年間のBRI変化と尿蛋白の新規発現（宮崎県延岡市 2020–2021年）', {
    x: 2.5, y: 6.6, w: 10.2, h: 0.45, fontFace: F.jp, fontSize: T.small + 1, color: C.soft, margin: 0,
  });
}

// ══════════════════════════════════ 問題意識
{
  const s = light();
  heading(s, '特定健診は、毎年とられている');

  const now = [
    ['受ける', '腹囲・血圧・血液検査'],
    ['結果を渡す', '基準値との比較'],
    ['保健指導', '該当者に案内'],
  ];
  now.forEach(([t, d], i) => {
    const x = 0.8 + i * 2.6;
    card(s, x, 2.15, 2.3, 1.7, C.wash);
    s.addText(t, { x: x + 0.05, y: 2.4, w: 2.2, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: C.deep, align: 'center', margin: 0 });
    s.addText(d, { x: x + 0.05, y: 2.9, w: 2.2, h: 0.7, fontFace: F.jp, fontSize: T.small, color: C.inkSub, align: 'center', margin: 0 });
    if (i < 2) arrow(s, x + 2.34, 2.92, 0.22);
  });

  card(s, 8.7, 2.15, 3.8, 1.7, 'F7F2EC');
  s.addText('多くはここで終わる', {
    x: 8.95, y: 2.4, w: 3.3, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle - 3, bold: true, color: '8A6F52', margin: 0,
  });
  s.addText('「今」の値は分かるが、\n変化は活かされにくい', {
    x: 8.95, y: 2.88, w: 3.4, h: 0.75, fontFace: F.jp, fontSize: T.small, color: '5A5044', margin: 0, lineSpacingMultiple: 1.15,
  });

  card(s, 0.8, 4.3, 11.7, 2.2, C.deep);
  s.addText('問い', {
    x: 1.2, y: 4.55, w: 2, h: 0.42, fontFace: F.jp, fontSize: T.body, bold: true, color: C.amber, margin: 0,
  });
  s.addText('毎年同じ人を測っているのだから、\n「去年からどう変わったか」でリスクを見られないか。', {
    x: 1.2, y: 5.02, w: 11.0, h: 1.2,
    fontFace: F.jp, fontSize: 24, bold: true, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.3,
  });
}

// ══════════════════════════════════ 事例(BRI)
{
  const s = light();
  heading(s, '事例：からだの「まるみ」の変化を見る',
    '腹囲と身長だけで計算できる指標 BRI（Body Roundness Index）');

  const steps = [
    ['見たもの', '延岡市の40歳以上\n3,819名の2年分'],
    ['調べたこと', '1年間でBRIが\n増えた／減った／横ばい'],
    ['分かったこと', '増えた群で尿蛋白が\n新たに出やすかった'],
  ];
  steps.forEach(([t, d], i) => {
    const x = 0.8 + i * 4.05;
    card(s, x, 2.1, 3.75, 1.95, i === 2 ? C.deep : C.wash);
    s.addText(t, {
      x: x + 0.28, y: 2.3, w: 3.2, h: 0.42,
      fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: i === 2 ? C.amber : C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.28, y: 2.82, w: 3.25, h: 0.95,
      fontFace: F.jp, fontSize: T.small + 1, color: i === 2 ? 'FFFFFF' : C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
    });
  });

  // 「減った群」も基準の1を超えて見えるが、信頼区間が1をまたいでおり
  // (1.16、95%CI 0.85–1.58)、差があるとは言えない。同じ太さの棒で並べると
  // 「減っても危ない」と読めてしまうので、色を分け、注釈で明示する。
  s.addChart(pres.ChartType.bar, [{
    name: 'リスクの比',
    labels: ['減った', '横ばい（基準）', '増えた'],
    values: [1.16, 1.00, 1.38],
  }], {
    x: 0.8, y: 4.2, w: 6.6, h: 2.2,
    barDir: 'bar',
    chartColors: [C.soft, C.soft, C.mid],
    varyColors: true,
    showValue: true, dataLabelPosition: 'outEnd',
    dataLabelColor: C.ink, dataLabelFontSize: 14, dataLabelFontFace: 'Calibri',
    // 書式を指定しないと 1.38 が「1」に丸められて表示される
    dataLabelFormatCode: '0.00',
    showLegend: false,
    showTitle: true, title: '横ばいの群を1としたときの、尿蛋白の出やすさ',
    titleColor: C.deep, titleFontSize: 14, titleFontFace: F.jp,
    catAxisLabelColor: C.ink, catAxisLabelFontSize: 14, catAxisLabelFontFace: F.jp,
    valAxisLabelColor: C.inkSub, valAxisLabelFontSize: 11,
    valAxisMinVal: 0, valAxisMaxVal: 1.8,
    valGridLine: { color: 'E4EDEB', size: 1 },
    catGridLine: { style: 'none' },
    barGapWidthPct: 55,
  });

  s.addText('「増えた」だけが統計的に確かめられた差です。「減った」は 1.16 と出ていますが、'
    + 'ばらつきの範囲（0.85〜1.58）が1をまたぐため、差があるとは言えません。', {
    x: 0.8, y: 6.45, w: 6.7, h: 0.55,
    fontFace: F.jp, fontSize: T.small - 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.2,
  });

  card(s, 7.7, 4.2, 4.8, 2.8, C.wash);
  s.addText('尿蛋白に注目する理由', {
    x: 8.0, y: 4.4, w: 4.3, h: 0.4, fontFace: F.jp, fontSize: T.cardTitle - 3, bold: true, color: C.deep, margin: 0,
  });
  s.addText('腎機能の低下より先に出ることが\n多く、早い段階で気づけます。', {
    x: 8.0, y: 4.85, w: 4.3, h: 0.8,
    fontFace: F.jp, fontSize: T.small + 1, color: C.ink, margin: 0, lineSpacingMultiple: 1.25,
  });
  s.addText('1.38倍とは', {
    x: 8.0, y: 5.68, w: 4.3, h: 0.35, fontFace: F.jp, fontSize: T.small - 1, bold: true, color: C.accentLabel, margin: 0,
  });
  s.addText('横ばいだった人に比べ、尿蛋白が\n新たに出た人の割合が約1.4倍。\n体重やBMIの変化を考慮しても\n残った差です。', {
    x: 8.0, y: 6.0, w: 4.4, h: 0.95,
    fontFace: F.jp, fontSize: T.small, color: C.ink, margin: 0, lineSpacingMultiple: 1.2,
  });
}

// ══════════════════════════════════ どう活かすか(中核)
{
  const s = light();
  heading(s, 'どう現場で使えるか', '研究を、健診の場での実践につなげる');

  const uses = [
    ['①', '道具がいらない', 'メジャーと身長計だけ。\n特別な機器がなくても\nどの会場でも計算できる'],
    ['②', '声のかけ方が変わる', '「太っています」ではなく\n「去年より増えています」。\n本人も実感しやすい'],
    ['③', '優先順位がつけられる', '限られた保健指導の枠を、\nリスクが上がった人に\n優先して充てられる'],
  ];
  uses.forEach(([n, t, d], i) => {
    const x = 0.8 + i * 4.05;
    card(s, x, 2.1, 3.75, 3.0, C.wash);
    badge(s, n, x + 0.28, 2.35, 0.55, C.amber, T.cardTitle - 2);
    s.addText(t, {
      x: x + 0.28, y: 3.1, w: 3.3, h: 0.45,
      fontFace: F.jp, fontSize: T.cardTitle - 2, bold: true, color: C.deep, margin: 0,
    });
    s.addText(d, {
      x: x + 0.28, y: 3.66, w: 3.3, h: 1.3,
      fontFace: F.jp, fontSize: T.small + 1, color: C.inkSub, margin: 0, lineSpacingMultiple: 1.3,
    });
  });

  card(s, 0.8, 5.45, 11.7, 1.3, C.deep);
  s.addText('研究の目的は、論文を書くことではなく、明日の声かけを変えること', {
    x: 1.2, y: 5.75, w: 11.0, h: 0.55,
    fontFace: F.jp, fontSize: T.lead, bold: true, color: 'FFFFFF', margin: 0,
  });
  s.addNotes('この資料の中心メッセージ。データ→研究→現場の実践、という流れを示す。');
}

// ══════════════════════════════════ 限界(誠実さ)
{
  const s = light();
  heading(s, '言えること、言えないこと');

  card(s, 0.8, 2.15, 5.6, 3.5, C.wash);
  s.addText('言えること', { x: 1.15, y: 2.4, w: 4, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: C.deep, margin: 0 });
  ['1年間でBRIが増えた人は、\n尿蛋白が新たに出やすかった', '体重やBMIの変化を\n考慮しても傾向は残った'].forEach((t, i) => {
    s.addText(t, { x: 1.15, y: 3.1 + i * 1.2, w: 5.1, h: 0.95, fontFace: F.jp, fontSize: T.body, color: C.ink, margin: 0, lineSpacingMultiple: 1.25 });
  });

  card(s, 7.0, 2.15, 5.5, 3.5, 'F7F2EC');
  s.addText('言えないこと', { x: 7.35, y: 2.4, w: 4, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle, bold: true, color: '8A6F52', margin: 0 });
  // 「減った群も危ない」と読まれかねないので、ここで明示的に否定しておく。
  // また、痩せの背景(病気・低栄養)を区別できていない点も、この研究の限界として重要。
  [
    'BRIを下げれば腎臓が守れる、\nという因果関係',
    '「減った人も危ない」とは\n言えない（差が確かめられていない）',
    '痩せた理由が生活改善なのか、\n病気や低栄養なのかは区別できない',
    '1年・延岡市の受診者が対象。\nそのまま他地域には広げられない',
  ].forEach((t, i) => {
    s.addText(t, { x: 7.35, y: 2.95 + i * 0.72, w: 5.0, h: 0.68, fontFace: F.jp, fontSize: T.small, color: '5A5044', margin: 0, lineSpacingMultiple: 1.15 });
  });

  s.addText('次に必要なのは、複数地域・長期の追跡と、介入して確かめる研究です。', {
    x: 0.8, y: 5.95, w: 11.7, h: 0.45, fontFace: F.jp, fontSize: T.body, color: C.inkSub, italic: true, margin: 0,
  });
}

// ══════════════════════════════════ 締め
{
  const s = dark();
  s.addShape(pres.ShapeType.ellipse, { x: -1.8, y: 4.0, w: 5.2, h: 5.2, fill: { color: C.card }, line: { color: C.card } });

  s.addText('ふたつに共通していること', {
    x: 1.0, y: 1.3, w: 11.5, h: 0.9, fontFace: F.jp, fontSize: T.title, bold: true, color: 'FFFFFF', margin: 0,
  });

  const two = [
    ['ファーマケア', '施設で毎日とっている\n服薬・症状の記録を、\nその場の判断につなげる'],
    ['健診データの研究', '毎年とっている健診の値を、\n変化として読み、\n予防の優先順位につなげる'],
  ];
  two.forEach(([t, d], i) => {
    const x = 1.0 + i * 5.85;
    card(s, x, 2.45, 5.5, 2.4, C.card);
    s.addText(t, { x: x + 0.4, y: 2.68, w: 4.8, h: 0.45, fontFace: F.jp, fontSize: T.cardTitle + 1, bold: true, color: C.amber, margin: 0 });
    s.addText(d, { x: x + 0.4, y: 3.25, w: 4.85, h: 1.35, fontFace: F.jp, fontSize: T.body, color: 'FFFFFF', margin: 0, lineSpacingMultiple: 1.3 });
  });

  s.addText('すでに手元にあるデータを、次の一手に変える。', {
    x: 1.0, y: 5.6, w: 11.4, h: 0.7,
    fontFace: F.jp, fontSize: 26, bold: true, color: 'FFFFFF', margin: 0,
  });
}

pres.writeFile({ fileName: 'C:/Users/OWNER/pharmacist_app/PharmaCare_紹介資料.pptx' })
  .then(f => console.log('作成しました:', f));
