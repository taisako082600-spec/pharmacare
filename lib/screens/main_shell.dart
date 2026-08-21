import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/mfa_service.dart';
import 'mfa_screens.dart';
import 'home_screen.dart';
import 'chat_list_screen.dart';
import 'patient_list_screen.dart';
import 'calendar_screen.dart';
import 'profile_screen.dart';
import 'family_home_screen.dart';

class MainShell extends StatefulWidget {
  final UserModel user;
  const MainShell({super.key, required this.user});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    if (widget.user.isFamily) {
      _screens = [
        FamilyHomeScreen(user: widget.user),
        CalendarScreen(user: widget.user),
        ProfileScreen(user: widget.user),
      ];
    } else {
      _screens = [
        HomeScreen(user: widget.user),
        ChatListScreen(user: widget.user),
        PatientListScreen(user: widget.user),
        CalendarScreen(user: widget.user),
        ProfileScreen(user: widget.user),
      ];
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _promptMfaIfUnenrolled());
  }

  /// 二要素認証が未登録なら、ログイン直後に一度だけ案内する。
  ///
  /// 登録画面はマイページから開けるが、それだけでは誰も登録しない。
  /// 2026-08-19時点の本番アカウント5件はいずれも未登録で、
  /// 「機能はあるが使われていない」状態だった。ガイドライン システム運用編 14⑤ は
  /// 令和9年4月1日までの二要素認証採用を求めており、期限までに実際に使われている
  /// 必要がある。
  ///
  /// ここでブロックはしない。介護施設では夜勤帯に初めてログインする職員もいて、
  /// その場で認証アプリを用意できないと業務が止まるため。強制するなら
  /// Identity Platform の `mfa.state` を `MANDATORY` にする（全員の登録完了後）。
  Future<void> _promptMfaIfUnenrolled() async {
    if (await MfaService().isEnrolled()) return;
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二要素認証の設定をおすすめします'),
        content: const Text(
          'このアプリは患者さんの医療情報を扱います。\n'
          'パスワードが漏れても本人以外がログインできないよう、'
          '認証アプリによる6桁の確認を追加できます。\n\n'
          '設定は数分で終わり、費用はかかりません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('あとで'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('設定する'),
          ),
        ],
      ),
    );

    if (go == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MfaSettingsScreen(accountName: widget.user.email),
        ),
      );
    }
  }

  Color get _themeColor {
    switch (widget.user.role) {
      case '薬剤師': return const Color(0xFF1976D2);
      case '介護士': return const Color(0xFF388E3C);
      case '看護師': return const Color(0xFFD32F2F);
      case '家族': return const Color(0xFF6A1B9A);
      default: return const Color(0xFF388E3C);
    }
  }

  // チャット未読数を取得（施設限定で効率化）
  Stream<bool> _hasUnreadChat() {
    final uid = widget.user.uid;
    final facilityId = widget.user.facilityId;
    final facilityIds = widget.user.facilityIds.isNotEmpty
        ? widget.user.facilityIds
        : (facilityId.isNotEmpty ? [facilityId] : <String>[]);

    if (facilityIds.isEmpty) return Stream.value(false);

    return FirebaseFirestore.instance
        .collection('rooms')
        .where('facilityId', whereIn: facilityIds)
        .snapshots()
        .map((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final lastSenderUid = data['lastSenderUid'] as String?;
        final lastMessage = data['lastMessage'] as String? ?? '';
        final lastMessageAt = data['lastMessageAt'] as Timestamp?;
        final lastReadMap = data['lastRead'] as Map<String, dynamic>?;
        final lastReadAt = lastReadMap?[uid] as Timestamp?;

        if (lastMessage.isNotEmpty &&
            lastSenderUid != uid &&
            (lastReadAt == null || (lastMessageAt != null && lastMessageAt.compareTo(lastReadAt) > 0))) {
          return true;
        }
      }
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: widget.user.isFamily
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              indicatorColor: _themeColor.withValues(alpha: 0.15),
              backgroundColor: Colors.white,
              elevation: 8,
              shadowColor: Colors.black26,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'ホーム'),
                NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'カレンダー'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'マイページ'),
              ],
            )
          : StreamBuilder<bool>(
              stream: _hasUnreadChat(),
              builder: (context, unreadSnap) {
                final hasUnread = unreadSnap.data ?? false;
                return NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) => setState(() => _currentIndex = i),
                  indicatorColor: _themeColor.withValues(alpha: 0.15),
                  backgroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black26,
                  destinations: [
                    const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'ホーム'),
                    NavigationDestination(
                      icon: Badge(isLabelVisible: hasUnread && _currentIndex != 1, child: const Icon(Icons.chat_bubble_outline_rounded)),
                      selectedIcon: const Icon(Icons.chat_bubble_rounded),
                      label: 'チャット',
                    ),
                    const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: '入居者'),
                    const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'カレンダー'),
                    const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'マイページ'),
                  ],
                );
              },
            ),
    );
  }
}
