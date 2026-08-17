import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/idle_timeout.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/admin/admin_shell.dart';
import 'models/user_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDtFXMxP2CzKBes2-My7YUSvEI5O7Jjv0w",
      authDomain: "pharmacist-app-646df.firebaseapp.com",
      projectId: "pharmacist-app-646df",
      storageBucket: "pharmacist-app-646df.firebasestorage.app",
      messagingSenderId: "927963369988",
      appId: "1:927963369988:web:e1cde38e60dcae741b9b51",
    ),
  );
  // Firestoreオフラインキャッシュを有効化（2回目以降の画面遷移が高速化）
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ファーマケア',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        highlightColor: Colors.transparent,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      // 無操作が続いたら自動でサインアウトする(ガイドライン システム運用編 12.3.2)。
      // アプリ全体を包むことで、どの画面で放置されても働く。
      builder: (context, child) => IdleTimeout(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, a, b) => page,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, c, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFFAB47BC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_pharmacy_rounded, color: Colors.white, size: 72),
              SizedBox(height: 20),
              Text(
                'ファーマケア',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              SizedBox(height: 8),
              Text('薬剤師と施設をつなぐ', style: TextStyle(color: Colors.white70, fontSize: 14)),
              SizedBox(height: 48),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: Colors.white60, strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        if (snapshot.data == null) {
          return const LoginScreen();
        }
        // ログイン済み → Firestoreからユーザー情報取得
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _SplashScreen();
            }
            if (!userSnap.hasData || !userSnap.data!.exists) {
              return const LoginScreen();
            }
            final user = UserModel.fromMap(snapshot.data!.uid, userSnap.data!.data() as Map<String, dynamic>);
            if (user.isAdmin) {
              return AdminShell(user: user);
            }
            return MainShell(user: user);
          },
        );
      },
    );
  }
}
