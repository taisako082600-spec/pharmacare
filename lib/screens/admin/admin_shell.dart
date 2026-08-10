import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'admin_dashboard_screen.dart';
import 'admin_facilities_screen.dart';
import 'admin_users_screen.dart';
import 'admin_chat_monitor_screen.dart';
import 'admin_stats_screen.dart';
import 'admin_drug_knowledge_screen.dart';

class AdminShell extends StatefulWidget {
  final UserModel user;
  const AdminShell({super.key, required this.user});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      AdminDashboardScreen(user: widget.user),
      AdminFacilitiesScreen(user: widget.user),
      AdminUsersScreen(user: widget.user),
      AdminChatMonitorScreen(user: widget.user),
      AdminStatsScreen(user: widget.user),
      AdminDrugKnowledgeScreen(user: widget.user),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        indicatorColor: const Color(0xFF7B1FA2).withValues(alpha: 0.15),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'ダッシュボード'),
          NavigationDestination(icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business), label: '施設'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'ユーザー'),
          NavigationDestination(icon: Icon(Icons.monitor_outlined), selectedIcon: Icon(Icons.monitor), label: '監視'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '統計'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: '薬剤知識'),
        ],
      ),
    );
  }
}
