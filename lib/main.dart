import 'package:flutter/material.dart';
import 'screens/events/manage_event_screen.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'services/data_service.dart';
import 'services/photo_service.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/lost_found/lost_found_screens.dart';
import 'screens/issues/issues_screens.dart';
import 'screens/events/events_screens.dart';
import 'screens/events/my_events_screen.dart';
import 'screens/lockers/lockers_screens.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/admin/admin_registrations_screen.dart';
import 'screens/profile/profile_screen.dart';


// ── Main ─────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => DataService()),
        ChangeNotifierProvider(create: (_) => PhotoUploadService()),
      ],
      child: const CampusConnectApp(),
    ),
  );
}

// ── Router ────────────────────────────────────────────────────────
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    // ── Splash & Auth ──────────────────────────────────────────
    GoRoute(path: '/',      builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegistrationScreen()),
    // ── Shell with bottom nav ──────────────────────────────────
    ShellRoute(
      builder: (ctx, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/lost-found', builder: (ctx, _) => const LostFoundHubScreen()),
        GoRoute(path: '/issues',     builder: (ctx, _) => const IssuesHubScreen()),
        GoRoute(path: '/events',     builder: (ctx, _) => const EventsHubScreen()),
        GoRoute(path: '/lockers',    builder: (ctx, _) => const LockerHubScreen()),
      ],
    ),
    // ── Lost & Found ───────────────────────────────────────────
    GoRoute(path: '/lost-found/report-lost',  builder: (_, __) => const ReportLostScreen()),
    GoRoute(path: '/lost-found/report-found', builder: (_, __) => const ReportFoundScreen()),
    GoRoute(path: '/lost-found/my-lost',      builder: (_, __) => const MyLostReportsScreen()),
    GoRoute(path: '/lost-found/my-found',     builder: (_, __) => const MyFoundReportsScreen()),
    GoRoute(path: '/lost-found/lost/:id',     builder: (_, s) => LostDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/lost-found/found/:id',    builder: (_, s) => FoundDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/lost-found/notifications',builder: (_, __) => const NotificationsScreen()),
    // ── Admin L&F ──────────────────────────────────────────────
    GoRoute(path: '/admin/lost-found/lost-list',   builder: (_, __) => const AdminLostListScreen()),
    GoRoute(path: '/admin/lost-found/found-list',  builder: (_, __) => const AdminFoundListScreen()),
    GoRoute(path: '/admin/lost-found/match-list',  builder: (_, __) => const AdminMatchListScreen()),
    GoRoute(path: '/admin/lost-found/lost/:id',    builder: (_, s) => AdminLostDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/admin/lost-found/found/:id',   builder: (_, s) => AdminFoundDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/admin/lost-found/match/:id',   builder: (_, s) => AdminMatchDetailScreen(id: s.pathParameters['id']!)),
    // ── Issues ─────────────────────────────────────────────────
    GoRoute(path: '/issues/report',           builder: (_, __) => const ReportIssueScreen()),
    GoRoute(path: '/issues/my-issues',        builder: (_, __) => const MyIssuesScreen()),
    GoRoute(path: '/issues/detail/:id',       builder: (_, s) => IssueDetailScreen(id: s.pathParameters['id']!)),
    // ── Admin Issues ───────────────────────────────────────────
    GoRoute(path: '/admin/issues/list',        builder: (_, __) => const AdminIssuesListScreen()),
    GoRoute(path: '/admin/issues/detail/:id',  builder: (_, s) => AdminIssueDetailScreen(id: s.pathParameters['id']!)),
    // ── Events ─────────────────────────────────────────────────
    GoRoute(path: '/events/create',               builder: (_, __) => const CreateEventScreen()),
    GoRoute(path: '/events/my-events',            builder: (_, __) => const MyEventsScreen()),
    GoRoute(path: '/events/my-events/:id',        builder: (_, s) => MyEventDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/events/manage/:id',           builder: (_, s) => ManageMyEventScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/events/detail/:id',        builder: (_, s) => EventDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/events/elections',         builder: (_, __) => const ElectionsInfoScreen()),
    // ── Admin Events ────────────────────────────────────────────
    GoRoute(path: '/admin/events/list',        builder: (_, __) => const AdminEventsListScreen()),
    GoRoute(path: '/admin/events/pending/:id', builder: (_, s) => AdminPendingEventDetailScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/admin/events/editor',      builder: (_, __) => const AdminEventEditorScreen()),
    GoRoute(path: '/admin/events/editor/:id',  builder: (_, s) => AdminEventEditorScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/admin/events/elections',   builder: (_, __) => const AdminElectionsMgmtScreen()),
    // ── Lockers ─────────────────────────────────────────────────
    GoRoute(path: '/lockers/browse',           builder: (_, __) => const BrowseLockersScreen()),
    GoRoute(path: '/lockers/detail/:id',       builder: (_, s) => LockerBookingScreen(id: s.pathParameters['id']!)),
    GoRoute(path: '/lockers/my-locker',        builder: (_, __) => const MyLockerScreen()),
    // ── Admin Lockers ────────────────────────────────────────────
    GoRoute(path: '/admin/lockers/list',       builder: (_, __) => const AdminLockersListScreen()),
    GoRoute(path: '/admin/lockers/detail/:id', builder: (_, s) => AdminLockerDetailScreen(id: s.pathParameters['id']!)),
    // ── Admin Registrations ─────────────────────────────────────
    GoRoute(path: '/admin/registrations', builder: (_, __) => const AdminRegistrationsScreen()),
    // ── Profile ─────────────────────────────────────────────────
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
  ],
);

// ── App Root ──────────────────────────────────────────────────────
class CampusConnectApp extends StatelessWidget {
  const CampusConnectApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Campus Connect',
      theme: AppTheme.theme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ── App Shell (bottom nav + header) ──────────────────────────────
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/lost-found', '/issues', '/events', '/lockers'];
  static const _labels = ['Lost & Found', 'Issues', 'Events', 'Lockers'];
  static const _icons = [Icons.search_rounded, Icons.warning_amber_rounded, Icons.event_rounded, Icons.lock_rounded];

  int _activeIndex(BuildContext ctx) {
    final loc = GoRouterState.of(ctx).uri.toString();
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (loc.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _activeIndex(context);
    return Scaffold(
      // ── Header ────────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient,
            boxShadow: [BoxShadow(color: Color(0x2A5193B3), blurRadius: 12, offset: Offset(0, 3))]),
          child: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
            // Logo
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Campus Connect', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
              Text('City University Malaysia', style: TextStyle(fontSize: 10, color: Color(0xCCFFFFFF), fontWeight: FontWeight.w500)),
            ])),
            // Admin toggle - Now requires login
            Consumer<AppState>(
              builder: (context, appState, child) {
                final isAdminMode = appState.isAdmin;
                return GestureDetector(
                  onTap: () async {
                    // If already admin, logout
                    if (isAdminMode) {
                      context.read<AppState>().logout();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('👤 Switched to Student mode'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                      return;
                    }

                    // Show login dialog to switch to admin
                    final result = await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const LoginScreen(isAdminLogin: true, isDialog: true),
                    );

                    if (result == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('🛡 Admin mode activated'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isAdminMode ? AppTheme.gold : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isAdminMode ? Icons.shield_rounded : Icons.person_rounded, size: 14, color: isAdminMode ? const Color(0xFF7A5B00) : Colors.white),
                      const SizedBox(width: 5),
                      Text(isAdminMode ? 'Admin' : 'Student', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isAdminMode ? const Color(0xFF7A5B00) : Colors.white)),
                    ]),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            // Profile button
            GestureDetector(
              onTap: () => context.push('/profile'),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 6),
            // Notification bell with dynamic badge
            Consumer2<DataService, AppState>(
              builder: (context, dataService, appState, child) {
                final unreadCount =
                    dataService.unreadNotificationCountForUser(appState.userId, appState.isAdmin);
                return GestureDetector(
                  onTap: () => context.push('/lost-found/notifications'),
                  child: Stack(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 20)),
                    if (unreadCount > 0) Positioned(top: 2, right: 2, child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: Text('$unreadCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
                    )),
                  ]),
                );
              },
            ),
          ]))),
        ),
      ),
      // ── Adaptive body ─────────────────────────────────────────
      body: Consumer<AppState>(
        builder: (context, appState, childWidget) {
          // If Admin and on a hub tab, show admin hub instead
          if (appState.isAdmin && idx == 0) return const AdminLFDashboardScreen();
          if (appState.isAdmin && idx == 1) return const AdminIssuesDashboardScreen();
          if (appState.isAdmin && idx == 2) return const AdminEventsListScreen();
          if (appState.isAdmin && idx == 3) return const AdminLockerDashboardScreen();
          return childWidget!;
        },
        child: child,
      ),
      // ── Bottom Nav ────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, -4))]),
        child: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_tabs.length, (i) {
            final active = idx == i;
            return Expanded(child: GestureDetector(
              onTap: () => context.go(_tabs[i]),
              child: AnimatedContainer(duration: const Duration(milliseconds: 220), padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: active ? AppTheme.red.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icons[i], color: active ? AppTheme.red : AppTheme.textMuted, size: active ? 24 : 22),
                  const SizedBox(height: 3),
                  Text(_labels[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w800 : FontWeight.w500, color: active ? AppTheme.red : AppTheme.textMuted)),
                  if (active) Container(margin: const EdgeInsets.only(top: 3), width: 18, height: 3, decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(99))),
                ]),
              ).animate(target: active ? 1 : 0).scaleXY(begin: 0.95, end: 1.0),
            ));
          }),
        ))),
      ),
    );
  }
}
