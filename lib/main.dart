import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'screens/events/manage_event_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/luxe.dart';
import 'services/app_state.dart';
import 'models/campus_notification.dart';
import 'services/data_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/onesignal_service.dart';
import 'services/lost_found_service.dart';
import 'services/photo_service.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/lost_found/lost_found_screens.dart';
import 'screens/issues/issues_screens.dart';
import 'screens/events/events_screens.dart';
import 'screens/events/admin_create_event_screen.dart';
import 'screens/events/my_events_screen.dart';
import 'screens/events/admin_election_detail_screen.dart';
import 'screens/events/admin_election_editor_screen.dart';
import 'screens/events/admin_election_archive_screen.dart';
import 'screens/lockers/lockers_screens.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/admin/admin_registrations_screen.dart';
import 'screens/profile/profile_screen.dart';

// ── Push background handler ──────────────────────────────────────
/// Registered as the Firebase Messaging background-message handler.
///
/// This runs in a separate isolate when the app is in the background or
/// terminated.  Its only job is to ensure the Firebase SDKs are
/// initialised so the payload is routed correctly.  The actual tap
/// handling (mark-read + navigation) is done by [PushService.initialize]
/// in [main] via `onMessageOpenedApp` / `getInitialMessage`.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // No UI work in the background isolate — onMessageOpenedApp handles
  // the tap when the user brings the app to the foreground.
}

/// Called when the user taps a OneSignal push notification (background
/// or terminated).  Marks the notification read in Firestore and navigates
/// to the relevant screen.
///
/// If the router has not been initialised yet (cold-start tap arriving
/// before [main] completes), the tap is queued and replayed once the
/// router is ready so no notification is ever lost.
void _handleOneSignalTap(Map<String, dynamic> data, AppState appState) {
  final tap = OneSignalService.parseTap(data);
  if (tap == null) return;

  // Mark the notification as read in Firestore.
  if (tap.type == 'lfNotification') {
    appState.markLfNotificationRead(tap.notificationId);
  } else if (tap.type == 'lockerNotification') {
    appState.markLockerNotificationRead(tap.notificationId);
  }

  // Source-aware deep-link using the canonical navigation mapping from
  // Phase 3.  Falls back to the notifications screen when no entity is
  // attached or the type is unknown.
  final router = _router;
  if (router == null) {
    // Cold-start tap arrived before the router was built.
    _pendingNotificationTaps.add(data);
    return;
  }

  final source = tap.type == 'lfNotification'
      ? NotificationSource.lostFound
      : tap.type == 'lockerNotification'
          ? NotificationSource.locker
          : null;

  final route = source != null
      ? defaultScreenForSource(
          source, tap.relatedReportId.isNotEmpty ? tap.relatedReportId : null)
      : '/notifications';

  router.push(route);
}

// ── Main ─────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the top-level background-message handler so FCM messages
  // are received when the app is not in the foreground.
  FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );

  // Initialise push service and capture the message that launched the
  // app (if the user tapped a notification while the app was killed).
  // The onTap callback uses the router — build it first, then wire.
  final pushService = PushService();

  // Build the AppState instance first — the router needs it for the auth guard.
  final appState = AppState(pushService: pushService);

  // Build the router with the auth guard wired to AppState.
  _buildRouter(appState);

  // Replay any notification taps that arrived during cold-start before
  // the router was ready.  These taps were queued by _handleOneSignalTap.
  if (_pendingNotificationTaps.isNotEmpty) {
    final pending = List<Map<String, dynamic>>.from(_pendingNotificationTaps);
    _pendingNotificationTaps.clear();
    for (final data in pending) {
      _handleOneSignalTap(data, appState);
    }
  }

  // ── OneSignal push notification delivery ─────────────────────────
  // OneSignal replaces FCM as the push delivery layer. The existing
  // PushService / firebase_messaging code is kept intact but will be
  // removed once OneSignal is verified on a real device.
  final oneSignal = OneSignalService();
  await oneSignal.initialize(
    onClick: (data) => _handleOneSignalTap(data, appState),
  );

  // Lock app orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configure status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => DataService()),
        ChangeNotifierProvider(create: (_) => PhotoUploadService()),
        // Stateless Firestore gateway — nothing listens to it, so a plain
        // Provider rather than a ChangeNotifierProvider.
        Provider(create: (_) => LostFoundService()),
      ],
      child: const CampusConnectApp(),
    ),
  );
}

// ── Router ────────────────────────────────────────────────────────
GoRouter? _router;
final List<Map<String, dynamic>> _pendingNotificationTaps = [];

void _buildRouter(AppState appState) {
  _router = GoRouter(
    refreshListenable: appState,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.uri.toString();
      // Public routes — always accessible, no auth check.
      if (loc == '/' || loc == '/login' || loc == '/register') return null;
      // Every other route requires an active session.
      if (!appState.isAuthenticated) return '/login';
      return null;
    },
    routes: [
      // ── Splash & Auth ──────────────────────────────────────────
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/register', builder: (_, __) => const RegistrationScreen()),
      // ── Shell with bottom nav ──────────────────────────────────
      ShellRoute(
        builder: (ctx, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/lost-found',
              builder: (ctx, _) => const LostFoundHubScreen()),
          GoRoute(
              path: '/issues', builder: (ctx, _) => const IssuesHubScreen()),
          GoRoute(
              path: '/events', builder: (ctx, _) => const EventsHubScreen()),
          GoRoute(
              path: '/lockers', builder: (ctx, _) => const LockerHubScreen()),
        ],
      ),
      // ── Lost & Found ───────────────────────────────────────────
      GoRoute(
          path: '/lost-found/report-lost',
          builder: (_, __) => const ReportLostScreen()),
      GoRoute(
          path: '/lost-found/report-found',
          builder: (_, __) => const ReportFoundScreen()),
      GoRoute(
          path: '/lost-found/my-lost',
          builder: (_, __) => const MyLostReportsScreen()),
      GoRoute(
          path: '/lost-found/my-found',
          builder: (_, __) => const MyFoundReportsScreen()),
      GoRoute(
          path: '/lost-found/lost/:id',
          builder: (_, s) => LostDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/lost-found/found/:id',
          builder: (_, s) => FoundDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      GoRoute(
          path: '/lost-found/notifications',
          builder: (_, __) => const NotificationsScreen()),
      // ── Admin L&F ──────────────────────────────────────────────
      GoRoute(
          path: '/admin/lost-found/lost-list',
          builder: (_, __) => const AdminLostListScreen()),
      GoRoute(
          path: '/admin/lost-found/found-list',
          builder: (_, __) => const AdminFoundListScreen()),
      GoRoute(
          path: '/admin/lost-found/inventory',
          builder: (_, __) => const AdminInventoryScreen()),
      GoRoute(
          path: '/admin/lost-found/inventory/archive',
          builder: (_, __) => const AdminInventoryArchiveScreen()),
      GoRoute(
          path: '/admin/lost-found/inventory/:id',
          builder: (_, s) =>
              AdminInventoryDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/lost-found/match-list',
          builder: (_, __) => const AdminMatchListScreen()),
      GoRoute(
          path: '/admin/lost-found/approved-matches',
          builder: (_, __) => const ApprovedMatchesScreen()),
      GoRoute(
          path: '/admin/lost-found/match/:id',
          builder: (_, s) =>
              AdminMatchDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/lost-found/lost/:id',
          builder: (_, s) =>
              AdminLostDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/lost-found/found/:id',
          builder: (_, s) =>
              AdminFoundDetailScreen(id: s.pathParameters['id']!)),
      // ── Issues ─────────────────────────────────────────────────
      GoRoute(
          path: '/issues/report',
          builder: (_, __) => const ReportIssueScreen()),
      GoRoute(
          path: '/issues/my-issues',
          builder: (_, __) => const MyIssuesScreen()),
      GoRoute(
          path: '/issues/detail/:id',
          builder: (_, s) => IssueDetailScreen(id: s.pathParameters['id']!)),
      // ── Admin Issues ───────────────────────────────────────────
      GoRoute(
          path: '/admin/issues/list',
          builder: (_, __) => const AdminIssuesListScreen()),
      GoRoute(
          path: '/admin/issues/detail/:id',
          builder: (_, s) =>
              AdminIssueDetailScreen(id: s.pathParameters['id']!)),
      // ── Events ─────────────────────────────────────────────────
      GoRoute(
          path: '/events/create',
          builder: (_, __) => const CreateEventScreen()),
      GoRoute(
          path: '/events/my-events',
          builder: (_, __) => const MyEventsScreen()),
      GoRoute(
          path: '/events/my-events/:id',
          builder: (_, s) => MyEventDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/events/manage/:id',
          builder: (_, s) => ManageMyEventScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/events/detail/:id',
          builder: (_, s) => EventDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/events/elections',
          builder: (_, __) => const ElectionsInfoScreen()),
      // ── Admin Events ────────────────────────────────────────────
      GoRoute(
          path: '/admin/events/list',
          builder: (_, __) => const AdminEventsListScreen()),
      GoRoute(
          path: '/admin/events/pending/:id',
          builder: (_, s) =>
              AdminPendingEventDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/events/editor',
          builder: (_, __) => const AdminCreateEventScreen()),
      GoRoute(
          path: '/admin/events/editor/:id',
          builder: (_, s) =>
              AdminCreateEventScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/events/elections',
          builder: (_, __) => const AdminElectionsMgmtScreen()),
      GoRoute(
          path: '/admin/events/elections/detail/:id',
          builder: (_, s) =>
              AdminElectionDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/events/elections/editor/:id',
          builder: (_, s) =>
              AdminElectionEditorScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/admin/events/elections/archive',
          builder: (_, __) => const AdminElectionArchiveScreen()),
      // ── Lockers ─────────────────────────────────────────────────
      GoRoute(
          path: '/lockers/browse',
          builder: (_, __) => const BrowseLockersScreen()),
      GoRoute(
          path: '/lockers/detail/:id',
          builder: (_, s) => LockerBookingScreen(id: s.pathParameters['id']!)),
      GoRoute(
          path: '/lockers/my-locker',
          builder: (_, __) => const MyLockerScreen()),
      // ── Admin Lockers ────────────────────────────────────────────
      GoRoute(
          path: '/admin/lockers/list',
          builder: (_, __) => const AdminLockersListScreen()),
      GoRoute(
          path: '/admin/lockers/detail/:id',
          builder: (_, s) =>
              AdminLockerDetailScreen(id: s.pathParameters['id']!)),
      // ── Admin Registrations ─────────────────────────────────────
      GoRoute(
          path: '/admin/registrations',
          builder: (_, __) => const AdminRegistrationsScreen()),
      // ── Profile ─────────────────────────────────────────────────
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    ],
  );
}

// ── App Root ──────────────────────────────────────────────────────
class CampusConnectApp extends StatelessWidget {
  const CampusConnectApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Campus Connect',
      theme: AppTheme.theme,
      routerConfig: _router!,
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

  /// Filled variants mark the active tab; outlined variants the rest.
  static const _iconsActive = [
    Icons.travel_explore_rounded,
    Icons.report_problem_rounded,
    Icons.calendar_month_rounded,
    Icons.lock_rounded,
  ];
  static const _iconsIdle = [
    Icons.travel_explore_outlined,
    Icons.report_problem_outlined,
    Icons.calendar_month_outlined,
    Icons.lock_outline_rounded,
  ];

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
    final lightHeader = idx == 0;
    final narrowHeader = lightHeader && MediaQuery.sizeOf(context).width < 430;
    final isAdminMode = context.watch<AppState>().isAdmin;
    // The admin locker dashboard owns the same identity header as the other
    // admin dashboards. The shell continues to own the shared bottom nav.
    final isAdminDashboard = isAdminMode && (idx == 1 || idx == 2 || idx == 3);
    final lightChrome = lightHeader || isAdminDashboard;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightChrome
          ? SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Luxe.bg,
        // ── Hero Header ───────────────────────────────────────────
        // The admin Issues dashboard owns the reference-style identity row.
        // Do not stack the shared shell header above it.
        appBar: idx == 0 || isAdminDashboard
            ? null
            : PreferredSize(
                preferredSize:
                    Size.fromHeight(MediaQuery.of(context).padding.top + 70),
                child: Container(
                  decoration: BoxDecoration(
                    color: lightHeader ? Luxe.bg : null,
                    gradient: lightHeader ? null : Luxe.heroGradient,
                    boxShadow: lightHeader
                        ? null
                        : [
                            BoxShadow(
                              color: Luxe.primaryDeep.withValues(alpha: 0.26),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                              spreadRadius: -4,
                            ),
                          ],
                  ),
                  child: Stack(
                    children: [
                      // Geometry, ambient light and campus skyline
                      if (!lightHeader)
                        Positioned.fill(
                          child: IgnorePointer(
                            child:
                                CustomPaint(painter: HeaderBackdropPainter()),
                          ),
                        ),
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Luxe.s4 + 2, Luxe.s2 + 2, Luxe.s4 + 2, Luxe.s3),
                          child: Row(
                            children: [
                              // Floating logo
                              Container(
                                width:
                                    lightHeader ? (narrowHeader ? 48 : 54) : 42,
                                height:
                                    lightHeader ? (narrowHeader ? 48 : 54) : 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius:
                                      BorderRadius.circular(Luxe.rSmall),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Luxe.primary.withValues(
                                          alpha: lightHeader ? 0.12 : 0.30),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.school_rounded,
                                    color: Luxe.primary,
                                    size: lightHeader
                                        ? (narrowHeader ? 25 : 29)
                                        : 23),
                              ),
                              SizedBox(
                                  width: lightHeader && narrowHeader
                                      ? 12
                                      : Luxe.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text('Campus Connect',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: lightHeader
                                                ? (narrowHeader ? 18 : 21)
                                                : 19,
                                            fontWeight: FontWeight.w800,
                                            color: lightHeader
                                                ? Luxe.ink
                                                : Colors.white,
                                            letterSpacing: -0.5,
                                            height: 1.1,
                                          )),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                                'City University Malaysia',
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: lightHeader
                                                      ? Luxe.inkSoft
                                                      : Colors.white.withValues(
                                                          alpha: 0.82),
                                                  fontWeight: FontWeight.w500,
                                                )),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Verified badge
                                        Container(
                                          width: 13,
                                          height: 13,
                                          decoration: BoxDecoration(
                                            color: lightHeader
                                                ? Luxe.primary
                                                    .withValues(alpha: 0.12)
                                                : Colors.white
                                                    .withValues(alpha: 0.92),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.check_rounded,
                                              size: 9, color: Luxe.primary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                  width: lightHeader && narrowHeader
                                      ? 4
                                      : Luxe.s2),
                              // ── Student / Admin selector (frosted glass) ──
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: narrowHeader ? 78 : 180,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Consumer<AppState>(
                                    builder: (context, appState, child) {
                                      final isAdminMode = appState.isAdmin;
                                      return GestureDetector(
                                        onTap: () async {
                                          // If already admin, sign out and redirect to login.
                                          if (isAdminMode) {
                                            context.read<AppState>().logout();
                                            if (context.mounted) {
                                              context.go('/login');
                                            }
                                            return;
                                          }

                                          // Show login dialog to switch to admin
                                          final result = await showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) => const LoginScreen(
                                                isAdminLogin: true,
                                                isDialog: true),
                                          );

                                          if (result == true) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                    '🛡 Admin mode activated'),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                backgroundColor:
                                                    AppTheme.textPrimary,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999)),
                                                duration:
                                                    const Duration(seconds: 1),
                                              ),
                                            );
                                          }
                                        },
                                        child: isAdminMode
                                            ? Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 11,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Luxe.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          Luxe.rChip),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Luxe.accent
                                                          .withValues(
                                                              alpha: 0.45),
                                                      blurRadius: 12,
                                                      offset:
                                                          const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.shield_rounded,
                                                          size: 13,
                                                          color: Color(
                                                              0xFF7A4B00)),
                                                      SizedBox(width: 5),
                                                      Text('Admin',
                                                          style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Color(
                                                                  0xFF7A4B00))),
                                                    ]),
                                              )
                                            : lightHeader
                                                ? Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal:
                                                                narrowHeader
                                                                    ? 9
                                                                    : 15,
                                                            vertical:
                                                                narrowHeader
                                                                    ? 8
                                                                    : 11),
                                                    decoration: BoxDecoration(
                                                      color: Luxe.primary
                                                          .withValues(
                                                              alpha: .08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              Luxe.rChip),
                                                      border: Border.all(
                                                          color: Luxe.primary
                                                              .withValues(
                                                                  alpha: .10)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .school_rounded,
                                                            size: 14,
                                                            color:
                                                                Luxe.primary),
                                                        SizedBox(width: 4),
                                                        Text('Student',
                                                            style: TextStyle(
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Luxe
                                                                    .primary)),
                                                        SizedBox(width: 1),
                                                        Icon(
                                                            Icons
                                                                .expand_more_rounded,
                                                            size: 15,
                                                            color:
                                                                Luxe.primary),
                                                      ],
                                                    ),
                                                  )
                                                : const GlassSurface(
                                                    radius: Luxe.rChip,
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 11,
                                                            vertical: 8),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .school_rounded,
                                                            size: 13,
                                                            color:
                                                                Colors.white),
                                                        SizedBox(width: 5),
                                                        Text('Student',
                                                            style: TextStyle(
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Colors
                                                                    .white)),
                                                        SizedBox(width: 2),
                                                        Icon(
                                                            Icons
                                                                .expand_more_rounded,
                                                            size: 14,
                                                            color:
                                                                Colors.white),
                                                      ],
                                                    ),
                                                  ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(
                                  width: lightHeader && narrowHeader ? 4 : 7),
                              // ── Profile ───────────────────────────────────
                              lightHeader
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Luxe.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Luxe.primary
                                                .withValues(alpha: .12)),
                                      ),
                                      child: IconButton(
                                        onPressed: () =>
                                            context.push('/profile'),
                                        icon: Icon(Icons.person_outline_rounded,
                                            color: Luxe.ink,
                                            size: narrowHeader ? 20 : 24),
                                        padding: EdgeInsets.all(
                                            narrowHeader ? 6 : 10),
                                        constraints: const BoxConstraints(),
                                      ),
                                    )
                                  : GlassSurface(
                                      radius: Luxe.rChip,
                                      padding: const EdgeInsets.all(9),
                                      onTap: () => context.push('/profile'),
                                      child: const Icon(Icons.person_rounded,
                                          color: Colors.white, size: 19),
                                    ),
                              SizedBox(
                                  width: lightHeader && narrowHeader ? 4 : 7),
                              // ── Notifications ─────────────────────────────
                              Consumer<AppState>(
                                builder: (context, appState, child) {
                                  return StreamBuilder<int>(
                                    stream: appState
                                        .watchUnreadCampusNotifications(),
                                    initialData: 0,
                                    builder: (context, snap) {
                                      final unreadCount = snap.data ?? 0;
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          lightHeader
                                              ? Container(
                                                  decoration: BoxDecoration(
                                                    color: Luxe.surface,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: Luxe.primary
                                                            .withValues(
                                                                alpha: .12)),
                                                  ),
                                                  child: IconButton(
                                                    onPressed: () => context
                                                        .push('/notifications'),
                                                    icon: Icon(
                                                        Icons
                                                            .notifications_none_rounded,
                                                        color: Luxe.ink,
                                                        size: narrowHeader
                                                            ? 20
                                                            : 24),
                                                    padding: EdgeInsets.all(
                                                        narrowHeader ? 6 : 10),
                                                    constraints:
                                                        const BoxConstraints(),
                                                  ),
                                                )
                                              : GlassSurface(
                                                  radius: Luxe.rChip,
                                                  padding:
                                                      const EdgeInsets.all(9),
                                                  onTap: () => context
                                                      .push('/notifications'),
                                                  child: const Icon(
                                                      Icons
                                                          .notifications_rounded,
                                                      color: Colors.white,
                                                      size: 19),
                                                ),
                                          if (unreadCount > 0)
                                            Positioned(
                                              top: -3,
                                              right: -3,
                                              child: IgnorePointer(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(3),
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 18,
                                                          minHeight: 18),
                                                  decoration: BoxDecoration(
                                                    color: Luxe.accent,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: 0.9),
                                                        width: 1.5),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Luxe.accent
                                                            .withValues(
                                                                alpha: 0.6),
                                                        blurRadius: 8,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text('$unreadCount',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontSize: 9,
                                                          height: 1.15,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Color(
                                                              0xFF7A4B00))),
                                                )
                                                    .animate(
                                                        onPlay: (c) => c.repeat(
                                                            reverse: true))
                                                    .scaleXY(
                                                        begin: 1.0,
                                                        end: 1.14,
                                                        duration: 1100.ms,
                                                        curve:
                                                            Curves.easeInOut),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        // ── Adaptive body ─────────────────────────────────────────
        body: Consumer<AppState>(
          builder: (context, appState, childWidget) {
            // If Admin and on a hub tab, show admin hub instead
            if (appState.isAdmin && idx == 0)
              return const AdminLFDashboardScreen();
            if (appState.isAdmin && idx == 1)
              return const AdminIssuesDashboardScreen();
            if (appState.isAdmin && idx == 2)
              return const AdminEventsListScreen();
            if (appState.isAdmin && idx == 3)
              return const AdminLockerDashboardScreen();
            return childWidget!;
          },
          child: child,
        ),
        // ── Floating Navigation Bar (Material 3) ──────────────────
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(Luxe.s4, Luxe.s1, Luxe.s4, Luxe.s3),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Luxe.s2 - 2, vertical: Luxe.s2 + 2),
              decoration: BoxDecoration(
                color: Luxe.surface,
                borderRadius: BorderRadius.circular(Luxe.rCard),
                border: Border.all(color: Luxe.primary.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Luxe.primary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Luxe.primary.withValues(alpha: 0.10),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final active = idx == i;
                  return Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // AnimatedContainer cannot tween between a finite
                        // width and double.infinity. The Expanded tab already
                        // gives us the exact finite width needed by the active
                        // pill, so use that bound explicitly.
                        final tabWidth = constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 40.0;
                        return GestureDetector(
                          onTap: () => context.go(_tabs[i]),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // M3 pill indicator
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                height: 34,
                                width: active ? tabWidth : 40,
                                padding: active
                                    ? const EdgeInsets.symmetric(horizontal: 8)
                                    : EdgeInsets.zero,
                                decoration: BoxDecoration(
                                  gradient: active
                                      ? LinearGradient(colors: [
                                          Luxe.secondary
                                              .withValues(alpha: 0.16),
                                          Luxe.primary.withValues(alpha: 0.13),
                                        ])
                                      : null,
                                  borderRadius:
                                      BorderRadius.circular(Luxe.rChip),
                                ),
                                child: active
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(_iconsActive[i],
                                                size: 20, color: Luxe.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              _labels[i],
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Luxe.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Icon(_iconsIdle[i],
                                        size: 21, color: Luxe.inkMuted),
                              ),
                              if (!active) ...[
                                const SizedBox(height: 4),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    height: 1.1,
                                    fontWeight: FontWeight.w500,
                                    color: Luxe.inkMuted,
                                  ),
                                  child: Text(_labels[i],
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
