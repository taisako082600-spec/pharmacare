// firestore.rules を Firebase の Rules テストAPI にかけて検証する。
//
//   node test_rules.js
//
// 実アカウントを作らずに「この認証状態でこの操作は通るか」を確かめられる。
// 権限の穴は書いた本人には見えないので、意図した拒否が本当に拒否されるかを
// 機械で確かめる。**期待ALLOWのケースも必ず入れること** —— 締めすぎて正規の
// 操作が壊れるほうが、実運用では先に問題になる。
//
// ハマりどころ:
//   - 更新の検証では testCase.resource(更新前のドキュメント)を渡さないと
//     diff() が評価できず、正当な更新まで DENY と出る(2026-08-24に一度誤読した)
//   - ルール内の get()/exists() は実データを見ない。functionMocks で明示的に
//     返り値を与える必要がある

const { getAuth } = require('./auth_helper');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'pharmacist-app-646df';
const DOCS = '/databases/(default)/documents';

const ME = 'uid_attacker';
const OWNER = 'uid_owner';
const MY_FACILITY = 'facility_mine'; // ME が作った施設
const OTHER_FACILITY = 'facility_other'; // 他人の施設(招待コードが発行されている)
const THIRD_FACILITY = 'facility_third'; // 他人の施設(コードを持っていない)
const PATIENT = 'patient_secret';
const CODE_FACILITY = '111111'; // 施設参加用(patientId なし)
const CODE_FAMILY = '222222'; // 家族用(patientId あり)

// 申請→承認フローの検証用
const MEMBER = 'uid_member'; // MEMBER_FACILITY に所属している職員
const MEMBER_FACILITY = 'facility_member';
const PHARMACIST = 'uid_pharmacist'; // 申請していない薬剤師
const APPROVED_PHARMACIST = 'uid_pharmacist_ok'; // 承認済みの申請がある薬剤師

const NOW = '2026-08-27T00:00:00Z';
const FUTURE = '2030-01-01T00:00:00Z';

// ルール内の get()/exists() が引くドキュメントを全ケース共通で用意する。
// 実在しないものは exists=false を返させ、「知らないコードは通らない」ことも確かめる。
const MOCKS = [
  mockExists(`${DOCS}/facilities/${MY_FACILITY}`, true),
  mockGet(`${DOCS}/facilities/${MY_FACILITY}`, { createdBy: ME }),
  mockExists(`${DOCS}/facilities/${OTHER_FACILITY}`, true),
  mockGet(`${DOCS}/facilities/${OTHER_FACILITY}`, { createdBy: OWNER }),
  mockExists(`${DOCS}/facilities/${THIRD_FACILITY}`, true),
  mockGet(`${DOCS}/facilities/${THIRD_FACILITY}`, { createdBy: OWNER }),
  mockExists(`${DOCS}/invite_codes/${CODE_FACILITY}`, true),
  mockGet(`${DOCS}/invite_codes/${CODE_FACILITY}`, {
    facilityId: OTHER_FACILITY,
    used: false,
    expiresAt: FUTURE,
  }),
  mockExists(`${DOCS}/invite_codes/${CODE_FAMILY}`, true),
  mockGet(`${DOCS}/invite_codes/${CODE_FAMILY}`, {
    facilityId: OTHER_FACILITY,
    patientId: PATIENT,
    used: false,
    expiresAt: FUTURE,
  }),
  // 自分の users ドキュメント(isAdmin 判定などで引かれる)
  // 実在しないコードは exists=false を返させる(でっち上げが通らないことの確認用)
  mockExists(`${DOCS}/invite_codes/999999`, false),
  mockExists(`${DOCS}/users/${ME}`, true),
  mockGet(`${DOCS}/users/${ME}`, { isAdmin: false, role: '介護士', facilityId: '', facilityIds: [] }),
  // 申請→承認フロー用。MEMBER は MEMBER_FACILITY に所属している。
  mockExists(`${DOCS}/users/${MEMBER}`, true),
  mockGet(`${DOCS}/users/${MEMBER}`, {
    isAdmin: false,
    role: '介護士',
    facilityId: MEMBER_FACILITY,
    facilityIds: [MEMBER_FACILITY],
  }),
  // 承認済みの申請があるのは APPROVED_PHARMACIST の分だけ。
  mockExists(`${DOCS}/connection_requests/${APPROVED_PHARMACIST}_${MEMBER_FACILITY}`, true),
  mockGet(`${DOCS}/connection_requests/${APPROVED_PHARMACIST}_${MEMBER_FACILITY}`, {
    status: 'approved',
  }),
  mockExists(`${DOCS}/connection_requests/${PHARMACIST}_${MEMBER_FACILITY}`, false),
];

function mockGet(p, data) {
  return {
    function: 'get',
    args: [{ exactValue: p }],
    result: { value: { data } },
  };
}
function mockExists(p, value) {
  return {
    function: 'exists',
    args: [{ exactValue: p }],
    result: { value },
  };
}

function tc(label, expectation, { method, docPath, uid, data, before }) {
  const request = {
    auth: uid ? { uid, token: { sub: uid } } : null,
    method,
    path: `${DOCS}/${docPath}`,
    time: NOW,
  };
  if (data) request.resource = { data };

  const testCase = { expectation, request, functionMocks: MOCKS };
  if (before) testCase.resource = { data: before };
  return { label, testCase };
}

const user = (extra = {}) => ({
  name: '利用者',
  role: '介護士',
  email: 'a@example.com',
  isAdmin: false,
  mfaRequired: true,
  facilityId: '',
  facilityIds: [],
  ...extra,
});

const CASES = [
  tc('① 招待コード無しで他施設に所属する', 'DENY', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({ facilityId: OTHER_FACILITY, facilityIds: [OTHER_FACILITY] }),
  }),
  tc('② 有効な招待コードを添えて所属する', 'ALLOW', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({
      facilityId: OTHER_FACILITY,
      facilityIds: [OTHER_FACILITY],
      joinedWithCode: CODE_FACILITY,
    }),
  }),
  // 自分が作った施設は「所有者だから」通ってしまうので、
  // ここでは自分と無関係な第三の施設を狙わせる。
  tc('③ コードは実在するが、狙う施設と一致しない', 'DENY', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({
      facilityId: THIRD_FACILITY,
      facilityIds: [THIRD_FACILITY],
      joinedWithCode: CODE_FACILITY,
    }),
  }),
  tc('③b 存在しないコードをでっち上げる', 'DENY', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({
      facilityId: THIRD_FACILITY,
      facilityIds: [THIRD_FACILITY],
      joinedWithCode: '999999',
    }),
  }),
  tc('④ 自分が作った施設には所属できる(新規施設の登録)', 'ALLOW', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({ facilityId: MY_FACILITY, facilityIds: [MY_FACILITY] }),
  }),
  tc('⑤ 入居者IDを知っているだけで家族登録する', 'DENY', {
    method: 'create',
    docPath: `users/${ME}`,
    uid: ME,
    data: user({ role: '家族', linkedPatientId: PATIENT }),
  }),
  tc('⑥ 家族用コードを添えれば紐付けできる', 'ALLOW', {
    method: 'create',
    docPath: `users/${ME}`,
    uid: ME,
    data: user({
      role: '家族',
      linkedPatientId: PATIENT,
      facilityId: OTHER_FACILITY,
      facilityIds: [OTHER_FACILITY],
      joinedWithCode: CODE_FAMILY,
    }),
  }),
  tc('⑦ 施設用コード(patientId無し)で家族紐付けを狙う', 'DENY', {
    method: 'create',
    docPath: `users/${ME}`,
    uid: ME,
    data: user({
      role: '家族',
      linkedPatientId: PATIENT,
      facilityId: OTHER_FACILITY,
      facilityIds: [OTHER_FACILITY],
      joinedWithCode: CODE_FACILITY,
    }),
  }),
  tc('⑧ 作成時に自分を管理者にする', 'DENY', {
    method: 'create',
    docPath: `users/${ME}`,
    uid: ME,
    data: user({ isAdmin: true }),
  }),
  tc('⑨ 後から自分のisAdminを立てる', 'DENY', {
    method: 'update',
    docPath: `users/${ME}`,
    uid: ME,
    before: user(),
    data: user({ isAdmin: true }),
  }),
  tc('⑩ 他人のコードを勝手に使用済みにする(妨害)', 'DENY', {
    method: 'update',
    docPath: `invite_codes/${CODE_FACILITY}`,
    uid: ME,
    before: { facilityId: OTHER_FACILITY, used: false, expiresAt: FUTURE },
    data: { facilityId: OTHER_FACILITY, used: true, usedBy: OWNER, expiresAt: FUTURE },
  }),
  tc('⑪ 家族用コードのpatientIdを別の入居者に付け替える', 'DENY', {
    method: 'update',
    docPath: `invite_codes/${CODE_FAMILY}`,
    uid: ME,
    before: { facilityId: OTHER_FACILITY, patientId: PATIENT, used: false, expiresAt: FUTURE },
    data: {
      facilityId: OTHER_FACILITY,
      patientId: 'patient_another',
      used: true,
      usedBy: ME,
      expiresAt: FUTURE,
    },
  }),
  // 申請→承認フロー。施設側が薬剤師の users を書けるのは、
  // 承認済みの申請が実在するときだけ。
  tc('⑬ 承認していない薬剤師を勝手に自施設へ所属させる', 'DENY', {
    method: 'update',
    docPath: `users/${PHARMACIST}`,
    uid: MEMBER,
    before: user({ name: '薬剤師' }),
    data: user({ name: '薬剤師', facilityId: MEMBER_FACILITY, facilityIds: [MEMBER_FACILITY] }),
  }),
  tc('⑭ 承認済みの申請があれば所属させられる', 'ALLOW', {
    method: 'update',
    docPath: `users/${APPROVED_PHARMACIST}`,
    uid: MEMBER,
    before: user({ name: '薬剤師' }),
    data: user({ name: '薬剤師', facilityId: MEMBER_FACILITY, facilityIds: [MEMBER_FACILITY] }),
  }),
  tc('⑮ 承認に便乗して相手のロールも書き換える', 'DENY', {
    method: 'update',
    docPath: `users/${APPROVED_PHARMACIST}`,
    uid: MEMBER,
    before: user({ name: '薬剤師' }),
    data: user({
      name: '薬剤師',
      role: '家族',
      linkedPatientId: PATIENT,
      facilityId: MEMBER_FACILITY,
      facilityIds: [MEMBER_FACILITY],
    }),
  }),
  tc('⑫ 正規の使用済み化(自分が使う)', 'ALLOW', {
    method: 'update',
    docPath: `invite_codes/${CODE_FACILITY}`,
    uid: ME,
    before: { facilityId: OTHER_FACILITY, used: false, expiresAt: FUTURE },
    data: {
      facilityId: OTHER_FACILITY,
      used: true,
      usedBy: ME,
      usedAt: NOW,
      expiresAt: FUTURE,
    },
  }),
];

(async () => {
  const source = fs.readFileSync(path.join(__dirname, 'firestore.rules'), 'utf8');
  const { token, extraHeaders } = await getAuth(['https://www.googleapis.com/auth/cloud-platform']);

  const res = await fetch(`https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify({
      source: { files: [{ name: 'firestore.rules', content: source }] },
      testSuite: { testCases: CASES.map((c) => c.testCase) },
    }),
  });

  const json = await res.json();

  if (!res.ok) {
    console.error('テストAPIの呼び出しに失敗:');
    console.error(JSON.stringify(json, null, 2).slice(0, 2000));
    process.exitCode = 1;
    return;
  }
  if (json.issues && json.issues.length) {
    console.error('ルールの構文エラー:');
    for (const i of json.issues) {
      console.error(` - ${i.description} (${i.sourcePosition?.line ?? '?'}行目)`);
    }
    process.exitCode = 1;
    return;
  }

  let failed = 0;
  (json.testResults || []).forEach((r, i) => {
    const c = CASES[i];
    const want = c.testCase.expectation;
    const ok = r.state === 'SUCCESS';
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.label}  [期待 ${want}]`);
    if (!ok) {
      const err = (r.errors || [])[0];
      if (err) console.log(`        ${err.description ?? JSON.stringify(err)}`);
    }
  });

  console.log(`\n${CASES.length - failed}/${CASES.length} 通過`);
  process.exitCode = failed === 0 ? 0 : 1;
})();
