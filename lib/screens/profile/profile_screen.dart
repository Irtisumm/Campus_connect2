import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
  content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
  behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.textPrimary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
  title: Text(t), backgroundColor: Colors.transparent,
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => ctx.pop()));

// ── Profile Screen ────────────────────────────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final userId = appState.userId ?? 'GUEST';
        final isAdmin = appState.isAdmin;
        final profile = appState.currentUserProfile;
        final displayName = profile?.name ?? (isAdmin ? 'Administrator' : 'Guest User');
        final displayEmail =
            profile?.email ?? (isAdmin ? 'admin@city.edu.my' : 'guest@student.city.edu.my');
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
                        color: AppTheme.red.withOpacity(0.3),
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
                            color: Colors.white.withOpacity(0.2),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isAdmin ? AppTheme.gold : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                                size: 14,
                                color: isAdmin ? const Color(0xFF7A5B00) : AppTheme.red,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isAdmin ? 'Administrator' : 'Student',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isAdmin ? const Color(0xFF7A5B00) : AppTheme.red,
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
                      : () => _showEditProfileDialog(context, appState, profile),
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
                        onTap: () => _toast(context, 'Language settings coming soon'),
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
                        onTap: () => _toast(context, 'Help: support@student.city.edu.my'),
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
                        Icon(Icons.logout_rounded, color: Colors.white, size: 20),
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

  void _showEditProfileDialog(BuildContext context, AppState appState, dynamic profile) {
    final nameCtrl = TextEditingController(text: profile?.name?.toString() ?? '');
    final emailCtrl = TextEditingController(text: profile?.email?.toString() ?? '');
    final programmeCtrl = TextEditingController(text: profile?.programme?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: profile?.phone?.toString() ?? '');
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
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Programme is required' : null,
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
                    final phoneValid = RegExp(r'^[0-9+\-\s]{7,20}$').hasMatch(value);
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
              child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
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
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
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
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.8),
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
              color: AppTheme.red.withOpacity(0.1),
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
            trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
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
