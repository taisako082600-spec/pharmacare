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
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await _db.collection('users').doc(cred.user!.uid).set({
      'name': name,
      'role': role,
      'facilityName': facilityName,
      'facilityId': facilityId,
      'facilityIds': facilityId.isNotEmpty ? [facilityId] : [],
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'isAdmin': false,
    });
    return cred;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
