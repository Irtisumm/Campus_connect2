import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

void _toast(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
    title: Text(t),
    backgroundColor: Colors.transparent,
    flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
    leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => ctx.pop()));

// ── Profile Screen ────────────────────────────────────────────────
class _ProfileTokens {
  _ProfileTokens._();

  static const Color raspberry = Color(0xFFB60845);
  static const Color pink = Color(0xFFF23570);
  static const Color blush = Color(0xFFFFF8FA);
  static const Color navy = Color(0xFF1F304B);
  static const Color muted = Color(0xFF7B8EA7);
  static const Color hairline = Color(0xFFE9EDF2);
  static const Color blue = Color(0xFF2C649D);
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [raspberry, pink],
  );
  static const double cardRadius = 20;
  static const double rowHeight = 42;
  static const double headerBaseHeight = 88;
  static const double headerOverlap = 12;
  // This is the version label already exposed by the existing screen.
  static const String versionLabel = 'Campus Connect v3.0';
}

/// Redesigned profile view. The legacy widget remains below so its existing
/// dialogs and action implementations can be reused without changing their
/// authentication, state, or navigation behavior.
class ProfileScreen extends _LegacyProfileScreen {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final profile = appState.currentUserProfile;
        final isAdmin = appState.isAdmin;
        final studentId = profile?.userId ?? appState.userId ?? 'GUEST';
        final name =
            profile?.name ?? (isAdmin ? 'Administrator' : 'Guest User');
        final email = profile?.email ??
            (isAdmin ? 'admin@city.edu.my' : 'guest@student.city.edu.my');
        final programme = profile?.programme ?? 'General Studies';
        final initials = name
            .split(' ')
            .where((part) => part.trim().isNotEmpty)
            .map((part) => part.trim()[0])
            .take(2)
            .join();
        final role = isAdmin ? 'Administrator' : 'Student';

        return Scaffold(
          backgroundColor: _ProfileTokens.blush,
          bottomNavigationBar: const _ProfileBottomNavigationBar(),
          body: LayoutBuilder(
            builder: (context, viewport) {
              final topInset = MediaQuery.paddingOf(context).top;
              final headerHeight = topInset + _ProfileTokens.headerBaseHeight;
              final contentTop = headerHeight - _ProfileTokens.headerOverlap;
              final horizontal = viewport.maxWidth < 360
                  ? 16.0
                  : viewport.maxWidth < 600
                      ? 20.0
                      : 28.0;

              return RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: headerHeight,
                      child: _ProfileHeader(
                        height: headerHeight,
                        onBack: () {
                          if (context.canPop()) context.pop();
                        },
                      ),
                    ),
                    Positioned.fill(
                      top: contentTop,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        child: ColoredBox(
                          color: _ProfileTokens.blush,
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                                horizontal, 6, horizontal, 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    (viewport.maxHeight - contentTop - 14)
                                        .clamp(0.0, double.infinity),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _CombinedProfileCard(
                                    initials: initials.isEmpty ? 'U' : initials,
                                    name: name,
                                    studentId: studentId,
                                    programme: programme,
                                    role: role,
                                    isAdmin: isAdmin,
                                    email: email,
                                  ),
                                  const SizedBox(height: 4),
                                  Semantics(
                                    button: true,
                                    label: 'Edit Profile',
                                    child: SizedBox(
                                      height: 42,
                                      child: OutlinedButton.icon(
                                        onPressed: profile == null
                                            ? null
                                            : () => _showEditProfileDialog(
                                                context, appState, profile),
                                        icon: const Icon(Icons.edit_rounded,
                                            size: 18),
                                        label: const Text('Edit Profile'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _ProfileTokens.pink,
                                          backgroundColor: Colors.white,
                                          side: const BorderSide(
                                            color: _ProfileTokens.pink,
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const _ProfileSectionHeader('Settings'),
                                  _ProfileActionGroup(
                                    children: [
                                      _ProfileActionRow(
                                        icon: Icons.lock_rounded,
                                        label: 'Change Password',
                                        color: _ProfileTokens.pink,
                                        onTap: () =>
                                            _showChangePasswordDialog(context),
                                      ),
                                      const _ProfileGroupDivider(),
                                      _ProfileActionRow(
                                        icon: Icons.notifications_rounded,
                                        label: 'Notification Preferences',
                                        color: _ProfileTokens.pink,
                                        onTap: () =>
                                            _showNotificationSettings(context),
                                      ),
                                      const _ProfileGroupDivider(),
                                      _ProfileActionRow(
                                        icon: Icons.language_rounded,
                                        label: 'Language',
                                        color: _ProfileTokens.pink,
                                        trailing: const Text(
                                          'English',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: _ProfileTokens.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () => _toast(context,
                                            'Language settings coming soon'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const _ProfileSectionHeader('About & Help'),
                                  _ProfileActionGroup(
                                    children: [
                                      _ProfileActionRow(
                                        icon: Icons.info_outline_rounded,
                                        label: 'About Campus Connect',
                                        color: _ProfileTokens.blue,
                                        onTap: () => _showAboutDialog(context),
                                      ),
                                      const _ProfileGroupDivider(),
                                      _ProfileActionRow(
                                        icon: Icons.help_outline_rounded,
                                        label: 'Help & Support',
                                        color: _ProfileTokens.blue,
                                        onTap: () => _toast(context,
                                            'Help: support@student.city.edu.my'),
                                      ),
                                      const _ProfileGroupDivider(),
                                      _ProfileActionRow(
                                        icon: Icons.shield_outlined,
                                        label: 'Privacy Policy',
                                        color: _ProfileTokens.blue,
                                        onTap: () => _toast(
                                            context, 'Privacy policy opened'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Semantics(
                                    button: true,
                                    label: 'Log out',
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _showLogoutDialog(
                                              context, appState),
                                          child: Ink(
                                            height: 42,
                                            decoration: const BoxDecoration(
                                              gradient: _ProfileTokens.gradient,
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.logout_rounded,
                                                    color: Colors.white,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Logout',
                                                  style: TextStyle(
                                                    fontSize: 15.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Center(
                                    child: Text(
                                      _ProfileTokens.versionLabel,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: _ProfileTokens.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final double height;
  final VoidCallback onBack;

  const _ProfileHeader({required this.height, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: _ProfileTokens.gradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const IgnorePointer(
                child: CustomPaint(painter: _CampusLineArtPainter())),
            Padding(
              padding: EdgeInsets.fromLTRB(28, top + 18, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onBack,
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampusLineArtPainter extends CustomPainter {
  const _CampusLineArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final baseY = size.height - 8;
    final left = size.width * 0.62;
    canvas.drawLine(Offset(left, baseY), Offset(size.width, baseY), stroke);

    void building(double x, double width, double height, {bool roof = true}) {
      final top = baseY - height;
      canvas.drawRect(Rect.fromLTWH(x, top, width, height), stroke);
      if (roof) {
        final roof = Path()
          ..moveTo(x - 5, top)
          ..lineTo(x + width / 2, top - 10)
          ..lineTo(x + width + 5, top)
          ..moveTo(x + width / 2 - 6, top - 12)
          ..lineTo(x + width / 2 + 6, top - 12);
        canvas.drawPath(roof, stroke);
      }
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          final wx = x + 5 + col * (width - 12) / 2;
          final wy = top + 12 + row * 14;
          canvas.drawRect(Rect.fromLTWH(wx, wy, 4, 6), stroke);
        }
      }
    }

    building(left + 8, 25, 30);
    building(left + 42, 31, 43);
    building(left + 80, 22, 27, roof: false);
    building(left + 110, 31, 36);
    building(left + 148, 22, 49);
    canvas.drawCircle(Offset(left + 3, baseY - 45), 5, stroke);
    canvas.drawCircle(Offset(left + 130, baseY - 53), 4, stroke);
  }

  @override
  bool shouldRepaint(covariant _CampusLineArtPainter oldDelegate) => false;
}

class _CombinedProfileCard extends StatelessWidget {
  final String initials;
  final String name;
  final String studentId;
  final String programme;
  final String role;
  final bool isAdmin;
  final String email;

  const _CombinedProfileCard({
    required this.initials,
    required this.name,
    required this.studentId,
    required this.programme,
    required this.role,
    required this.isAdmin,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final panelWidth = width * 0.47;
        final cardHeight = (width * 0.58).clamp(164.0, 210.0);
        return Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_ProfileTokens.cardRadius),
            boxShadow: [
              BoxShadow(
                color: _ProfileTokens.raspberry.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: ClipPath(
                  clipper: const _ProfileWaveClipper(),
                  child: DecoratedBox(
                    decoration:
                        const BoxDecoration(gradient: _ProfileTokens.gradient),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
                      child: _ProfilePanel(
                        initials: initials,
                        name: name,
                        studentId: studentId,
                        programme: programme,
                        role: role,
                        isAdmin: isAdmin,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(width * 0.42, 5, 7, 5),
                  child: _AccountDetails(
                    email: email,
                    programme: programme,
                    studentId: studentId,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileWaveClipper extends CustomClipper<Path> {
  const _ProfileWaveClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.76, 0)
      ..cubicTo(size.width * 0.92, size.height * 0.22, size.width * 1.04,
          size.height * 0.40, size.width, size.height * 0.54)
      ..cubicTo(size.width * 0.96, size.height * 0.73, size.width * 0.83,
          size.height * 0.92, size.width * 0.78, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ProfileWaveClipper oldClipper) => false;
}

class _ProfilePanel extends StatelessWidget {
  final String initials;
  final String name;
  final String studentId;
  final String programme;
  final String role;
  final bool isAdmin;

  const _ProfilePanel({
    required this.initials,
    required this.name,
    required this.studentId,
    required this.programme,
    required this.role,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            height: 1.12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xE6FFFFFF),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.17),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Text(
              programme,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(minHeight: 28, maxWidth: 132),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                size: 12,
                color: _ProfileTokens.raspberry,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ProfileTokens.raspberry,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountDetails extends StatelessWidget {
  final String email;
  final String programme;
  final String studentId;

  const _AccountDetails({
    required this.email,
    required this.programme,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _AccountRow(
            icon: Icons.mail_rounded,
            label: 'Email',
            value: email,
            maxLines: 2,
          ),
        ),
        const _AccountDivider(),
        Expanded(
          child: _AccountRow(
            icon: Icons.school_rounded,
            label: 'Programme',
            value: programme,
            maxLines: 2,
          ),
        ),
        const _AccountDivider(),
        Expanded(
          child: _AccountRow(
            icon: Icons.badge_rounded,
            label: 'Student ID',
            value: studentId,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  const _AccountRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _ProfileTokens.pink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: _ProfileTokens.raspberry, size: 16),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ProfileTokens.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ProfileTokens.navy,
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountDivider extends StatelessWidget {
  const _AccountDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 35),
      child: Container(height: 1, color: _ProfileTokens.hairline),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  final String title;

  const _ProfileSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _ProfileTokens.muted,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 2,
            decoration: const BoxDecoration(gradient: _ProfileTokens.gradient),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionGroup extends StatelessWidget {
  final List<Widget> children;

  const _ProfileActionGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_ProfileTokens.cardRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_ProfileTokens.cardRadius),
          boxShadow: [
            BoxShadow(
              color: _ProfileTokens.raspberry.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _ProfileGroupDivider extends StatelessWidget {
  const _ProfileGroupDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 56),
      child: Divider(height: 1, thickness: 1, color: _ProfileTokens.hairline),
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ProfileActionRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: _ProfileTokens.rowHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 17),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ProfileTokens.navy,
                        fontSize: 13.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  trailing ??
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _ProfileTokens.muted,
                        size: 22,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The profile route is pushed above the main shell, so it owns the same
/// compact navigation treatment while keeping the original destinations and
/// tap behaviour intact.
class _ProfileBottomNavigationBar extends StatelessWidget {
  const _ProfileBottomNavigationBar();

  static const _tabs = ['/lost-found', '/issues', '/events', '/lockers'];
  static const _labels = ['Lost & Found', 'Issues', 'Events', 'Lockers'];
  static const _icons = [
    Icons.travel_explore_outlined,
    Icons.report_problem_outlined,
    Icons.calendar_month_outlined,
    Icons.lock_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _ProfileTokens.raspberry.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: _ProfileTokens.raspberry.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: _ProfileTokens.raspberry.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              children: List.generate(_tabs.length, (index) {
                return Expanded(
                  child: Semantics(
                    button: true,
                    label: _labels[index],
                    child: InkWell(
                      onTap: () => context.go(_tabs[index]),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 24,
                              width: 42,
                              child: Icon(
                                _icons[index],
                                size: 20,
                                color: _ProfileTokens.muted,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color: _ProfileTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegacyProfileScreen extends StatelessWidget {
  const _LegacyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final userId = appState.userId ?? 'GUEST';
        final isAdmin = appState.isAdmin;
        final profile = appState.currentUserProfile;
        final displayName =
            profile?.name ?? (isAdmin ? 'Administrator' : 'Guest User');
        final displayEmail = profile?.email ??
            (isAdmin ? 'admin@city.edu.my' : 'guest@student.city.edu.my');
        final displayProgramme = profile?.programme ?? 'General Studies';
        final displayPhone = profile?.phone ?? '';
        final initials = displayName
            .split(' ')
            .where((e) => e.isNotEmpty)
            .map((e) => e[0])
            .take(2)
            .join();

        return Scaffold(
          appBar: _appBar('Profile', context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── User Profile Card ──────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.red.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Avatar
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Center(
                            child: Text(
                              initials.isEmpty ? 'U' : initials,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Name
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // User ID
                        Text(
                          userId,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Programme Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            displayProgramme,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Role Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isAdmin ? AppTheme.gold : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAdmin
                                    ? Icons.shield_rounded
                                    : Icons.person_rounded,
                                size: 14,
                                color: isAdmin
                                    ? const Color(0xFF7A5B00)
                                    : AppTheme.red,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isAdmin ? 'Administrator' : 'Student',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isAdmin
                                      ? const Color(0xFF7A5B00)
                                      : AppTheme.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 24),

                // ── Account Information ────────────────────────────
                const SectionLabel('Account Information'),
                Card(
                  child: Column(
                    children: [
                      _ProfileInfoTile(
                        icon: Icons.email_rounded,
                        label: 'Email',
                        value: displayEmail,
                      ),
                      const Divider(height: 1),
                      _ProfileInfoTile(
                        icon: Icons.school_rounded,
                        label: 'Programme',
                        value: displayProgramme,
                      ),
                      const Divider(height: 1),
                      _ProfileInfoTile(
                        icon: Icons.badge_rounded,
                        label: 'Student ID',
                        value: userId,
                      ),
                      if (displayPhone.isNotEmpty) ...[
                        const Divider(height: 1),
                        _ProfileInfoTile(
                          icon: Icons.phone_rounded,
                          label: 'Phone',
                          value: displayPhone,
                        ),
                      ],
                    ],
                  ),
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.15),

                const SizedBox(height: 10),
                OutlineBtn(
                  label: 'Edit Profile',
                  onPressed: profile == null
                      ? null
                      : () =>
                          _showEditProfileDialog(context, appState, profile),
                ),

                const SizedBox(height: 16),

                // ── Settings & Actions ─────────────────────────────
                const SectionLabel('Settings'),
                Card(
                  child: Column(
                    children: [
                      _ProfileActionTile(
                        icon: Icons.lock_outline_rounded,
                        label: 'Change Password',
                        color: AppTheme.red,
                        onTap: () => _showChangePasswordDialog(context),
                      ),
                      const Divider(height: 1),
                      _ProfileActionTile(
                        icon: Icons.notifications_outlined,
                        label: 'Notification Preferences',
                        color: AppTheme.red,
                        onTap: () => _showNotificationSettings(context),
                      ),
                      const Divider(height: 1),
                      _ProfileActionTile(
                        icon: Icons.language_rounded,
                        label: 'Language',
                        color: AppTheme.red,
                        trailing: const Text(
                          'English',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () =>
                            _toast(context, 'Language settings coming soon'),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.15),

                const SizedBox(height: 16),

                // ── About & Help ───────────────────────────────────
                const SectionLabel('About & Help'),
                Card(
                  child: Column(
                    children: [
                      _ProfileActionTile(
                        icon: Icons.info_outline_rounded,
                        label: 'About Campus Connect',
                        color: AppTheme.textPrimary,
                        onTap: () => _showAboutDialog(context),
                      ),
                      const Divider(height: 1),
                      _ProfileActionTile(
                        icon: Icons.help_outline_rounded,
                        label: 'Help & Support',
                        color: AppTheme.textPrimary,
                        onTap: () => _toast(
                            context, 'Help: support@student.city.edu.my'),
                      ),
                      const Divider(height: 1),
                      _ProfileActionTile(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy Policy',
                        color: AppTheme.textPrimary,
                        onTap: () => _toast(context, 'Privacy policy opened'),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),

                const SizedBox(height: 24),

                // ── Logout Button ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _showLogoutDialog(context, appState),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.15),

                const SizedBox(height: 12),

                // ── App Version ────────────────────────────────────
                Center(
                  child: const Text(
                    'Campus Connect v3.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditProfileDialog(
      BuildContext context, AppState appState, dynamic profile) {
    final nameCtrl =
        TextEditingController(text: profile?.name?.toString() ?? '');
    final emailCtrl =
        TextEditingController(text: profile?.email?.toString() ?? '');
    final programmeCtrl =
        TextEditingController(text: profile?.programme?.toString() ?? '');
    final phoneCtrl =
        TextEditingController(text: profile?.phone?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Email is required';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: programmeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Programme / Faculty',
                    prefixIcon: Icon(Icons.school_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Programme is required'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    final phoneValid =
                        RegExp(r'^[0-9+\-\s]{7,20}$').hasMatch(value);
                    if (!phoneValid) return 'Enter a valid phone number';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final saved = await appState.updateCurrentUserProfile(
                name: nameCtrl.text,
                email: emailCtrl.text,
                programme: programmeCtrl.text,
                phone: phoneCtrl.text,
              );
              if (!context.mounted) return;
              if (saved) {
                Navigator.of(dialogCtx).pop();
                _toast(context, 'Profile updated');
              } else {
                _toast(context, 'Failed to update profile');
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Change Password',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              if (newPasswordCtrl.text == confirmPasswordCtrl.text &&
                  newPasswordCtrl.text.length >= 6) {
                Navigator.of(dialogCtx).pop();
                _toast(context, 'Password changed successfully');
              } else {
                _toast(context, 'Passwords do not match or too short');
              }
            },
            child: const Text('Change', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Notification Preferences',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NotificationToggle(
              label: 'Lost & Found Matches',
              value: true,
              onChanged: (val) {},
            ),
            _NotificationToggle(
              label: 'Event Updates',
              value: true,
              onChanged: (val) {},
            ),
            _NotificationToggle(
              label: 'Issue Status Changes',
              value: true,
              onChanged: (val) {},
            ),
            _NotificationToggle(
              label: 'Locker Reminders',
              value: true,
              onChanged: (val) {},
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _toast(context, 'Preferences saved');
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Campus Connect',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 3.0',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.red,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Campus Connect is your all-in-one student companion app for City University Malaysia.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
            ),
            SizedBox(height: 12),
            Text(
              'Features:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              '• Lost & Found Management\n'
              '• Campus Issue Reporting\n'
              '• Event Management\n'
              '• Locker Booking System',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, height: 1.8),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              appState.logout();
              Navigator.of(dialogCtx).pop();
              context.go('/login');
              _toast(context, 'Logged out successfully');
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Profile Info Tile ──────────────────────────────────────────────
class _ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppTheme.red),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Action Tile ────────────────────────────────────────────
class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Notification Toggle ────────────────────────────────────────────
class _NotificationToggle extends StatefulWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotificationToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<_NotificationToggle> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Switch(
            value: _value,
            onChanged: (val) {
              setState(() => _value = val);
              widget.onChanged(val);
            },
            activeThumbColor: AppTheme.red,
          ),
        ],
      ),
    );
  }
}
