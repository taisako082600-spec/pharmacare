import 'package:firebase_auth/firebase_auth.dart';

/// 二要素認証(TOTP方式)。
///
/// 根拠: 「医療情報システムの安全管理に関するガイドライン第7.0版」システム運用編
/// 14 遵守事項⑤
///
///   > 令和9年度（令和9年4月1日時点）で稼働していることが想定される医療情報システムを、
///   > 今後、新規導入又は機器の入替等を伴うシステム更改をするに際しては、二要素認証を採用、
///   > 又はこれに相当する対応を行うこと。
///   > ・クライアント端末では電子カルテ等のアプリケーションのログイン時に二要素認証を実装すること。
///
/// SMS方式ではなくTOTP(認証アプリ)方式を選んでいる理由:
///   - SMSは1通あたり課金が発生する(日本宛 約4.9円、MFA検証は月100回無料/超過9.8円)。
///     施設スタッフが毎日ログインする使い方だと無料枠を超えて継続的な費用になる。
///   - TOTPは端末内で生成するため通信費・API費用ともにゼロ。
///   - 介護施設は電波状況が悪い居室もあり、SMSが届かないと業務が止まる。
///
/// 利用者はGoogle Authenticator等の認証アプリを使う。
class MfaService {
  static final MfaService _instance = MfaService._internal();
  factory MfaService() => _instance;
  MfaService._internal();

  /// 現在のユーザーが二要素認証を登録済みか。
  Future<bool> isEnrolled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final factors = await user.multiFactor.getEnrolledFactors();
    return factors.isNotEmpty;
  }

  /// メールアドレスが確認済みか。
  ///
  /// Firebaseは、メールアドレスの確認が済んでいないアカウントでは二要素認証を
  /// 登録させない(auth/unverified-email)。本人でないアドレスに二要素認証を
  /// 紐づけてしまうと復旧できなくなるための仕様。
  /// 画面側は登録を始める前にこれを確認し、未確認なら先に確認メールを送る。
  Future<bool> isEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // 確認直後でもローカルの状態は古いままなので、サーバーから取り直す
    await user.reload();
    return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
  }

  /// 確認メールを送る。
  Future<void> sendEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ログインしていません');
    }
    await user.sendEmailVerification();
  }

  /// 登録済みの要素一覧(解除画面で表示する用)。
  Future<List<MultiFactorInfo>> enrolledFactors() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    return user.multiFactor.getEnrolledFactors();
  }

  /// 登録の第1段階。認証アプリに読み込ませるQRコードURLと、手入力用の秘密鍵を作る。
  ///
  /// 返した [TotpSecret] は [completeEnrollment] にそのまま渡す必要があるため、
  /// 画面側で保持しておくこと。
  Future<TotpEnrollmentStart> startEnrollment({required String accountName}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ログインしていません');
    }

    final session = await user.multiFactor.getSession();
    final secret = await TotpMultiFactorGenerator.generateSecret(session);
    final qrCodeUrl = await secret.generateQrCodeUrl(
      accountName: accountName,
      issuer: 'ファーマケア',
    );

    return TotpEnrollmentStart(
      secret: secret,
      qrCodeUrl: qrCodeUrl,
      manualEntryKey: secret.secretKey,
    );
  }

  /// 登録の第2段階。認証アプリに表示された6桁を検証して登録を確定する。
  Future<void> completeEnrollment({
    required TotpSecret secret,
    required String oneTimePassword,
    String displayName = '認証アプリ',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ログインしていません');
    }

    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(
      secret,
      oneTimePassword,
    );
    await user.multiFactor.enroll(assertion, displayName: displayName);
  }

  /// 二要素認証を解除する。
  /// 直近の再認証が必要になることがあるため、呼び出し側で失敗を扱えるようにしている。
  Future<void> unenroll(String factorUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ログインしていません');
    }
    await user.multiFactor.unenroll(factorUid: factorUid);
  }

  /// ログイン時に二要素認証を求められた場合の解決。
  ///
  /// `signInWithEmailAndPassword` が [FirebaseAuthMultiFactorException] を投げたら、
  /// その `resolver` と利用者が入力した6桁をここへ渡す。
  Future<UserCredential> resolveSignIn({
    required MultiFactorResolver resolver,
    required String oneTimePassword,
  }) async {
    // 本アプリはTOTPしか登録させないため、先頭の要素を使う。
    final hint = resolver.hints.first;
    final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(
      hint.uid,
      oneTimePassword,
    );
    return resolver.resolveSignIn(assertion);
  }
}

/// 登録開始時に画面へ渡す情報。
class TotpEnrollmentStart {
  /// 登録確定(completeEnrollment)に必要。画面側で保持すること。
  final TotpSecret secret;

  /// 認証アプリで読み取らせるQRコードの元URL(otpauth://...)。
  final String qrCodeUrl;

  /// カメラが使えない場合に手入力してもらう秘密鍵。
  final String manualEntryKey;

  const TotpEnrollmentStart({
    required this.secret,
    required this.qrCodeUrl,
    required this.manualEntryKey,
  });
}
