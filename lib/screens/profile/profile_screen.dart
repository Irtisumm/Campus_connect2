import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

void _toast(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        duration: const Duration(seconds: 2)));

/// Up to two leading initials from [name], falling back to 'U' when empty —
/// never a fake name.
String _initialsOf(String name) {
  final initials = name
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => part.trim()[0])
      .take(2)
      .join();
  return initials.isEmpty ? 'U' : initials;
}

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
  static const double rowHeight = 56;
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
        final loadStatus = appState.profileLoadStatus;

        return Scaffold(
          backgroundColor: _ProfileTokens.blush,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final horizontal = viewport.maxWidth < 360
                    ? 14.0
                    : viewport.maxWidth < 600
                        ? 18.0
                        : 26.0;
                final bottomPadding =
                    (MediaQuery.viewPaddingOf(context).bottom + 28)
                        .clamp(40.0, 64.0);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 8, horizontal, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          button: true,
                          label: 'Back',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                if (context.canPop()) context.pop();
                              },
                              borderRadius: BorderRadius.circular(13),
                              child: Ink(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _ProfileTokens.pink
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: _ProfileTokens.raspberry,
                                  size: 19,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                            horizontal, 6, horizontal, bottomPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (profile != null) ...[
                              _CombinedProfileCard(
                                initials: _initialsOf(profile.name),
                                name: profile.name,
                                studentId: profile.userId,
                                programme: profile.programme,
                                role: isAdmin ? 'Administrator' : 'Student',
                                isAdmin: isAdmin,
                                email: profile.email,
                              ),
                              const SizedBox(height: 16),
                              Semantics(
                                button: true,
                                label: 'Edit Profile',
                                child: SizedBox(
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showEditProfileDialog(
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
                            ] else
                              _ProfileLoadStateCard(
                                status: loadStatus,
                                onRetry: () => appState.retryLoadProfile(),
                              ),
                            const SizedBox(height: 18),
                            const _ProfileSectionHeader('Settings'),
                            _ProfileActionGroup(
                              children: [
                                _ProfileActionRow(
                                  icon: Icons.lock_rounded,
                                  label: 'Change Password',
                                  color: _ProfileTokens.pink,
                                  onTap: () =>
                                      _showChangePasswordDialog(
                                          context, appState),
                                ),
                                const _ProfileGroupDivider(),
                                _ProfileActionRow(
                                  icon: Icons.notifications_rounded,
                                  label: 'Notification Preferences',
                                  color: _ProfileTokens.pink,
                                  onTap: () =>
                                      _showNotificationSettings(
                                          context, appState),
                                ),
                                const _ProfileGroupDivider(),
                                _ProfileActionRow(
                                  icon: Icons.language_rounded,
                                  label: 'Language',
                                  color: _ProfileTokens.pink,
                                  trailing: Text(
                                    profile?.preferredLanguage ??
                                        UserProfile.defaultLanguage,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _ProfileTokens.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onTap: () => _showLanguageDialog(
                                      context, appState),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
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
                                  onTap: () => _showHelpDialog(context),
                                ),
                                const _ProfileGroupDivider(),
                                _ProfileActionRow(
                                  icon: Icons.shield_outlined,
                                  label: 'Privacy Policy',
                                  color: _ProfileTokens.blue,
                                  onTap: () => _showPrivacyDialog(context),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Semantics(
                              button: true,
                              label: 'Log out',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        _showLogoutDialog(context, appState),
                                    child: Ink(
                                      height: 46,
                                      decoration: const BoxDecoration(
                                        gradient: _ProfileTokens.gradient,
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.logout_rounded,
                                              color: Colors.white, size: 20),
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
                            const SizedBox(height: 16),
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
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Loading / retry / signed-out state shown in place of the profile card when
/// the authenticated student's profile has not loaded yet. Replaces the old
/// hard-coded "Guest User" / sample-email fallbacks with honest UI states.
class _ProfileLoadStateCard extends StatelessWidget {
  final ProfileLoadStatus status;
  final VoidCallback onRetry;

  const _ProfileLoadStateCard({required this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final loading = status == ProfileLoadStatus.loading;
    final signedIn = status != ProfileLoadStatus.idle;
    final message = switch (status) {
      ProfileLoadStatus.loading => 'Loading your profile…',
      ProfileLoadStatus.missing =>
        'Your profile could not be found. Please contact the administrator.',
      ProfileLoadStatus.error =>
        "We couldn't load your profile. Check your connection and try again.",
      ProfileLoadStatus.idle => 'Sign in to view your profile.',
      ProfileLoadStatus.ready => 'Loading your profile…',
    };
    final showRetry = signedIn && !loading && status == ProfileLoadStatus.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
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
      child: Column(
        children: [
          if (loading)
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                color: _ProfileTokens.pink,
                strokeWidth: 3,
              ),
            )
          else
            Icon(
              status == ProfileLoadStatus.idle
                  ? Icons.lock_person_outlined
                  : Icons.cloud_off_rounded,
              size: 36,
              color: _ProfileTokens.muted,
            ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ProfileTokens.navy,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showRetry) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ProfileTokens.pink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(
                      color: _ProfileTokens.pink, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
        final panelWidth = width * 0.49;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final accessibilityHeight = ((textScale - 1.0).clamp(0.0, 1.0)) * 84;
        final cardHeight =
            (width * 0.64 + accessibilityHeight).clamp(180.0, 270.0);
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
                  // Keep the account column clear of the gentle red edge.
                  padding: EdgeInsets.fromLTRB(width * 0.52, 5, 7, 5),
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
      ..lineTo(size.width * 0.96, 0)
      ..cubicTo(size.width * 0.98, size.height * 0.22, size.width * 1.01,
          size.height * 0.40, size.width, size.height * 0.54)
      ..cubicTo(size.width * 0.99, size.height * 0.73, size.width * 0.97,
          size.height * 0.92, size.width * 0.95, size.height)
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
          width: 56,
          height: 56,
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xE6FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                fontSize: 9.5,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(minHeight: 32, maxWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                size: 14,
                color: _ProfileTokens.raspberry,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ProfileTokens.raspberry,
                    fontSize: 11,
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _ProfileTokens.pink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: _ProfileTokens.raspberry, size: 18),
        ),
        const SizedBox(width: 6),
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
                  fontSize: 10.5,
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
                  fontSize: 13,
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
      padding: const EdgeInsets.only(left: 36),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _ProfileTokens.muted,
              fontSize: 11.5,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        fontSize: 14,
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

/// Hosts the shared Profile action dialogs (edit, change password,
/// notifications, language, help, privacy, about, logout) inherited by the
/// redesigned [ProfileScreen]. It is abstract because that screen supplies the
/// only `build`; the legacy `build` with hard-coded "Guest User" / sample-email
/// fallbacks has been removed so no fake profile data ships in production.
abstract class _LegacyProfileScreen extends StatelessWidget {
  const _LegacyProfileScreen({super.key});

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

  void _showChangePasswordDialog(BuildContext context, AppState appState) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Change Password',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordCtrl,
                  obscureText: true,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordCtrl,
                  obscureText: true,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordCtrl,
                  obscureText: true,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Use at least 6 characters. Your password is never stored.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: submitting
                  ? null
                  : () async {
                      if (currentPasswordCtrl.text.isEmpty) {
                        _toast(ctx, 'Enter your current password');
                        return;
                      }
                      if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
                        _toast(ctx, 'New passwords do not match');
                        return;
                      }
                      if (newPasswordCtrl.text.length < 6) {
                        _toast(ctx,
                            'Password must contain at least six characters');
                        return;
                      }
                      setState(() => submitting = true);
                      final result = await appState.changePassword(
                        currentPassword: currentPasswordCtrl.text,
                        newPassword: newPasswordCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      setState(() => submitting = false);
                      if (result.success) {
                        Navigator.of(dialogCtx).pop();
                        _toast(ctx,
                            result.message ?? 'Password changed successfully');
                      } else {
                        _toast(ctx,
                            result.message ?? 'Could not change password');
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Change',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context, AppState appState) {
    final profile = appState.currentUserProfile;
    final prefs = Map<String, bool>.from(
        profile?.notificationPrefs ?? UserProfile.defaultNotificationPrefs);
    const keys = <(String, String)>[
      ('lostFoundMatches', 'Lost & Found Matches'),
      ('eventUpdates', 'Event Updates'),
      ('issueStatus', 'Issue Status Changes'),
      ('lockerReminders', 'Locker Reminders'),
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Notification Preferences',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in keys)
                  _NotificationToggle(
                    label: entry.$2,
                    value: prefs[entry.$1] ?? true,
                    onChanged: (val) =>
                        setState(() => prefs[entry.$1] = val),
                  ),
              ],
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
                final ok = await appState.updateNotificationPrefs(prefs);
                if (!ctx.mounted) return;
                Navigator.of(dialogCtx).pop();
                _toast(ctx,
                    ok ? 'Preferences saved' : 'Could not save preferences');
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, AppState appState) {
    final profile = appState.currentUserProfile;
    String selected =
        profile?.preferredLanguage ?? UserProfile.defaultLanguage;
    const supported = <String>[UserProfile.defaultLanguage];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Language',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final lang in supported)
                ListTile(
                  dense: true,
                  title: Text(lang),
                  trailing: selected == lang
                      ? const Icon(Icons.check_rounded, color: AppTheme.red)
                      : null,
                  onTap: () => setState(() => selected = lang),
                ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'More languages will be available when the app adds '
                  'localization. Your choice is saved to your profile.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
              onPressed: () async {
                final ok = await appState.updatePreferredLanguage(selected);
                if (!ctx.mounted) return;
                Navigator.of(dialogCtx).pop();
                _toast(ctx,
                    ok ? 'Language preference saved' : 'Could not save language');
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need a hand? Reach the Campus Connect team and we will help you '
              'with your account, events, lockers and more.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
            ),
            SizedBox(height: 12),
            Text(
              'Email: support@student.city.edu.my',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              final uri = Uri.parse(
                  'mailto:support@student.city.edu.my?subject=Campus Connect Support');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                if (!context.mounted) return;
                _toast(context, 'Email us at support@student.city.edu.my');
              }
            },
            child: const Text('Email Us', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Campus Connect is committed to protecting your privacy. This '
                'policy explains how your data is handled.',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
              ),
              SizedBox(height: 12),
              Text(
                'What we store',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              SizedBox(height: 6),
              Text(
                'Your profile (name, email, student ID, faculty, phone, '
                'notification and language preferences) is stored securely in '
                'Firebase, linked to your authenticated account.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
              ),
              SizedBox(height: 12),
              Text(
                'Who can see it',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              SizedBox(height: 6),
              Text(
                'Only you and authorised administrators can read your profile. '
                'Other students cannot access your data. Database security rules '
                'enforce this on the server, not only in the app.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
              ),
              SizedBox(height: 12),
              Text(
                'Passwords',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              SizedBox(height: 6),
              Text(
                'Passwords are managed by Firebase Authentication and are never '
                'stored, logged, or written to your profile.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
              ),
            ],
          ),
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
