import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
    required String facilityName,
    required String facilityId,
    // 招待コードで施設に参加する場合のコード文字列。
    // firestore.rules は、施設に所属した状態のユーザー作成を、
    // 「実在する有効な招待コードが提示されているか」で判定する。
    // 判定材料としてドキュメントに残す必要があるため受け取る。
    String joinedWithCode = '',
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);

    // 新規の職員アカウントは二要素認証を必須にする。
    //
    // 「作成時に必須」にしておけば、未登録のまま運用に入るアカウントが生まれず、
    // あとから一律必須へ切り替えるときに誰も締め出されない。
    // 家族ロールは対象外 — 閲覧のみで、高齢のご家族が認証アプリを用意できないと
    // ご本人の状況を確認する手段が絶たれてしまうため。
    final requireMfa = role != '家族';

    await _db.collection('users').doc(cred.user!.uid).set({
      'name': name,
      'role': role,
      'facilityName': facilityName,
      'facilityId': facilityId,
      'facilityIds': facilityId.isNotEmpty ? [facilityId] : [],
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'isAdmin': false,
      'mfaRequired': requireMfa,
      if (joinedWithCode.isNotEmpty) 'joinedWithCode': joinedWithCode,
    });

    // 二要素認証の登録にはメールアドレスの確認が前提になる(Firebaseの仕様)。
    // 登録画面で待たせる時間を減らすため、ここで先に送っておく。
    if (requireMfa) {
      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {
        // 送信に失敗しても登録自体は続行する。確認画面から再送できる。
      }
    }

    return cred;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
