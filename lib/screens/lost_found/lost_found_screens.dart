import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/campus_notification.dart';
import '../../models/item.dart';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';
import '../../services/lost_found_service.dart';
import '../../services/app_state.dart';
import '../../services/cloudinary_service.dart';
import '../../services/notification_service.dart';
import '../auth/login_screen.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppTheme.textPrimary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    duration: const Duration(seconds: 2),
  ));
}

AppBar _gradientAppBar(String title, BuildContext context,
        {List<Widget>? actions}) =>
    AppBar(
      title: Text(title),
      flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
      backgroundColor: Colors.transparent,
      leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop()),
      actions: actions,
    );

// ── Screen 1: Hub ────────────────────────────────────────────────
class LostFoundHubScreen extends StatefulWidget {
  const LostFoundHubScreen({super.key});
  @override
  State<LostFoundHubScreen> createState() => _LostFoundHubScreenState();
}

class _LostFoundHubScreenState extends State<LostFoundHubScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;

  @override
  void initState() {
    super.initState();
    // One combined feed for lost + found; AppState resolves the signed-in
    // caller. The hub never touches DataService or Firestore directly.
    _reports = context.read<AppState>().watchMyAllReports();
  }

  /// Maps a report status onto the semantic palette. Kept tolerant of
  /// wording so new statuses degrade to neutral rather than crash.

  /// 'Matched - Pending' → 'Matched'. Keeps chips to a single word or two.
  /// Groups statuses into ordered {label: count} pairs for the chip row.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: _reports,
      builder: (context, snapshot) {
        // On the first frame the stream has not emitted yet; render the full
        // layout with zeroed counts so the hub never flashes an empty-state
        // where its cards should be. Errors are surfaced as chips of zero too
        // — the hub has no "could not load" body, unlike the list screens, so a
        // failed read degrades to "0 Submitted" rather than blocking the page.
        final all = snapshot.data ?? const <Item>[];
        final lost = all.where((r) => r.isLost).toList(growable: false);
        final found = all.where((r) => r.isFound).toList(growable: false);
        // "Found Reports" counts only found reports that are still Active —
        // once a found report is handed over (In Inventory), returned,
        // resolved, or closed it no longer counts as an active found report.
        final activeFound =
            found.where((r) => r.status == ItemStatus.active).length;
        final active = all
            .where((r) =>
                r.status == ItemStatus.active ||
                r.status == ItemStatus.matchedPending)
            .length;

        return Scaffold(
          backgroundColor: Luxe.bg,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding:
                const EdgeInsets.fromLTRB(Luxe.s4, Luxe.s3, Luxe.s4, Luxe.s7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _LostFoundIdentityRow(),
                const _LostFoundHero(),
                const SizedBox(height: Luxe.s2),
                const _PrivacyCard()
                    .animate()
                    .fadeIn(duration: 420.ms)
                    .slideY(begin: 0.12, curve: Curves.easeOutCubic),
                const SizedBox(height: Luxe.s4),
                const _HubSectionHeader('REPORT AN ITEM'),
                LayoutBuilder(builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >= 310;
                  final cards = [
                    _HeroActionCard(
                      title: 'Report Lost Item',
                      icon: Icons.search_rounded,
                      gradient: Luxe.lostGradient,
                      glow: Luxe.primary,
                      illustration: const [
                        Icons.backpack_rounded,
                        Icons.account_balance_wallet_rounded,
                        Icons.laptop_mac_rounded,
                      ],
                      onTap: () => context.push('/lost-found/report-lost'),
                    ),
                    _HeroActionCard(
                      title: 'Report Found Item',
                      icon: Icons.inventory_2_rounded,
                      gradient: Luxe.foundGradient,
                      glow: Luxe.accent,
                      illustration: const [
                        Icons.inventory_2_rounded,
                        Icons.badge_rounded,
                        Icons.smartphone_rounded,
                      ],
                      onTap: () => context.push('/lost-found/report-found'),
                    ),
                  ];
                  return sideBySide
                      ? Row(children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: Luxe.s3),
                          Expanded(child: cards[1]),
                        ])
                      : Column(children: [
                          cards[0],
                          const SizedBox(height: Luxe.s3),
                          cards[1],
                        ]);
                }),
                const SizedBox(height: Luxe.s4),
                _StatsCard(
                    lost: lost.length, found: activeFound, active: active),
                const SizedBox(height: Luxe.s4),
                _HubSectionHeader(
                  'MY REPORTS',
                  trailing: TextButton(
                    onPressed: () => context.push('/lost-found/my-lost'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('View all',
                        style: Luxe.body.copyWith(
                            color: Luxe.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
                _MyReportsCard(
                  lost: lost,
                  found: found,
                  onLost: () => context.push('/lost-found/my-lost'),
                  onFound: () => context.push('/lost-found/my-found'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ── Privacy card ──────────────────────────────────────────────────
/// Section labels for the dashboard. Typography and whitespace provide the
/// hierarchy; there are no decorative indicator lines.
class _HubSectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const _HubSectionHeader(this.label, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Luxe.s2, bottom: Luxe.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: Luxe.sectionLabel.copyWith(
                color: Luxe.ink,
                fontSize: 13,
                letterSpacing: 1.7,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The Lost & Found identity controls belong to the dashboard's scrollable
/// content rather than a separate shell app bar. All callbacks intentionally
/// remain the same as the shell controls used on the other tabs.
class _LostFoundIdentityRow extends StatelessWidget {
  final bool includeTopSafeArea;
  final bool showMenu;

  const _LostFoundIdentityRow({
    this.includeTopSafeArea = true,
    this.showMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final tiny = constraints.maxWidth < 350;
        final logoSize = showMenu
            ? (tiny
                ? 40.0
                : compact
                    ? 44.0
                    : 48.0)
            : (tiny
                ? 44.0
                : compact
                    ? 46.0
                    : 52.0);
        final controlSize = showMenu
            ? (tiny
                ? 34.0
                : compact
                    ? 36.0
                    : 40.0)
            : (tiny
                ? 36.0
                : compact
                    ? 38.0
                    : 44.0);
        final iconSize = showMenu
            ? (tiny
                ? 17.0
                : compact
                    ? 19.0
                    : 21.0)
            : (tiny
                ? 18.0
                : compact
                    ? 20.0
                    : 23.0);
        final gap = showMenu
            ? (tiny
                ? 3.0
                : compact
                    ? 4.0
                    : 6.0)
            : (tiny
                ? 3.0
                : compact
                    ? 4.0
                    : 8.0);
        final roleWidth = showMenu
            ? (tiny
                ? 62.0
                : compact
                    ? 82.0
                    : 108.0)
            : (tiny
                ? 66.0
                : compact
                    ? 74.0
                    : 132.0);

        final row = Padding(
          padding: EdgeInsets.only(
            top: tiny ? 3 : 7,
            bottom: tiny ? 3 : 5,
          ),
          child: Row(
            children: [
              if (showMenu) ...[
                _IdentityMenuButton(
                  size: controlSize,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                SizedBox(width: gap),
              ],
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Luxe.rSmall),
                  boxShadow: [
                    BoxShadow(
                      color: Luxe.primary.withValues(alpha: .10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.school_rounded,
                    color: Luxe.primary, size: iconSize + 4),
              ),
              SizedBox(
                  width: tiny
                      ? 6
                      : compact
                          ? 7
                          : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Campus Connect',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: showMenu
                              ? (compact ? 16 : 18)
                              : (compact ? 17 : 19),
                          fontWeight: FontWeight.w800,
                          color: Luxe.ink,
                          letterSpacing: -.45,
                          height: 1.08,
                        ),
                      ),
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
                                fontSize: showMenu
                                    ? (compact ? 9 : 9.5)
                                    : (compact ? 10 : 10.5),
                                color: Luxe.inkSoft,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Luxe.primary.withValues(alpha: .12),
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
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: roleWidth),
                child: Consumer<AppState>(
                  builder: (context, appState, child) {
                    final isAdmin = appState.isAdmin;
                    final roleColor =
                        isAdmin ? const Color(0xFF7A4B00) : Luxe.primary;
                    return GestureDetector(
                      onTap: () async {
                        if (isAdmin) {
                          appState.logout();
                          if (context.mounted) context.go('/login');
                          return;
                        }

                        final result = await showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const LoginScreen(
                              isAdminLogin: true, isDialog: true),
                        );
                        if (result == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('🛡 Admin mode activated'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppTheme.textPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999)),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? Luxe.accent
                              : Luxe.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(Luxe.rChip),
                          border: Border.all(
                              color: isAdmin
                                  ? Luxe.accent.withValues(alpha: .45)
                                  : Luxe.primary.withValues(alpha: .10)),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAdmin
                                    ? Icons.shield_rounded
                                    : Icons.school_rounded,
                                size: compact ? 13 : 14,
                                color: roleColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isAdmin ? 'Admin' : 'Student',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: roleColor,
                                ),
                              ),
                              const SizedBox(width: 1),
                              Icon(Icons.expand_more_rounded,
                                  size: 15, color: roleColor),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: gap),
              _IdentityIconButton(
                size: controlSize,
                iconSize: iconSize,
                icon: Icons.person_outline_rounded,
                onPressed: () => context.push('/profile'),
              ),
              SizedBox(width: gap),
              Consumer<AppState>(
                builder: (context, appState, child) {
                  return StreamBuilder<int>(
                    stream: appState.watchUnreadCampusNotifications(),
                    initialData: 0,
                    builder: (context, snap) {
                      final unreadCount = snap.data ?? 0;
                      return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _IdentityIconButton(
                                size: controlSize,
                                iconSize: iconSize,
                                icon: Icons.notifications_none_rounded,
                                onPressed: () =>
                                    context.push('/lost-found/notifications'),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  top: -3,
                                  right: -3,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      constraints: const BoxConstraints(
                                          minWidth: 17, minHeight: 17),
                                      decoration: BoxDecoration(
                                        color: Luxe.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: .9),
                                            width: 1.5),
                                      ),
                                      child: Text('$unreadCount',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 9,
                                              height: 1.15,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF7A4B00))),
                                    ),
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
        );

        return includeTopSafeArea
            ? SafeArea(top: true, bottom: false, child: row)
            : row;
      },
    );
  }
}

class _IdentityIconButton extends StatelessWidget {
  final double size;
  final double iconSize;
  final IconData icon;
  final VoidCallback onPressed;

  const _IdentityIconButton({
    required this.size,
    required this.iconSize,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Luxe.primary.withValues(alpha: .12)),
        boxShadow: [
          BoxShadow(
            color: Luxe.primary.withValues(alpha: .06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        icon: Icon(icon, color: Luxe.ink, size: iconSize),
      ),
    );
  }
}

class _IdentityMenuButton extends StatelessWidget {
  final double size;
  final VoidCallback onPressed;

  const _IdentityMenuButton({required this.size, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Luxe.rSmall),
        border: Border.all(color: Luxe.primary.withValues(alpha: .10)),
        boxShadow: [
          BoxShadow(
            color: Luxe.primary.withValues(alpha: .07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        icon: Icon(Icons.menu_rounded, color: Luxe.ink, size: size * .54),
      ),
    );
  }
}

class _LostFoundHero extends StatelessWidget {
  const _LostFoundHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        return SizedBox(
          height: compact ? 112 : 120,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact
                          ? constraints.maxWidth * .72
                          : constraints.maxWidth * .68,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: RichText(
                            text: TextSpan(
                              style: Luxe.display.copyWith(
                                fontSize: compact ? 28 : 30,
                                color: Luxe.ink,
                                letterSpacing: -1.1,
                              ),
                              children: const [
                                TextSpan(text: 'Lost '),
                                TextSpan(
                                    text: '&',
                                    style: TextStyle(color: Luxe.primary)),
                                TextSpan(text: ' Found'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: Luxe.s3),
                        Text(
                          'Report lost items and report found items.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Luxe.body.copyWith(
                            color: Luxe.inkSoft,
                            fontSize: compact ? 15 : 16,
                            height: 1.48,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: compact ? -8 : 0,
                top: compact ? -18 : -24,
                child: _LostFoundArtwork(size: compact ? 122 : 134),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LostFoundArtwork extends StatelessWidget {
  final double size;
  const _LostFoundArtwork({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .88,
            height: size * .72,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: .055),
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            right: size * .02,
            top: size * .03,
            child: Container(
              width: size * .20,
              height: size * .20,
              decoration: BoxDecoration(
                color: Luxe.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Transform.rotate(
            angle: -.12,
            child: Icon(Icons.backpack_rounded,
                size: size * .62, color: Luxe.primary.withValues(alpha: .88)),
          ),
          Positioned(
            left: size * .02,
            bottom: size * .18,
            child: Transform.rotate(
              angle: -.25,
              child: Icon(Icons.account_balance_wallet_rounded,
                  size: size * .30, color: const Color(0xFF242B4D)),
            ),
          ),
          Positioned(
            right: size * .05,
            bottom: size * .02,
            child: Transform.rotate(
              angle: .35,
              child: Icon(Icons.key_rounded,
                  size: size * .30, color: const Color(0xFF8B5E54)),
            ),
          ),
          Positioned(
            right: size * .12,
            bottom: size * .28,
            child: Container(
              width: size * .19,
              height: size * .27,
              decoration: BoxDecoration(
                color: const Color(0xFF24345E),
                borderRadius: BorderRadius.circular(size * .04),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.question_mark_rounded,
                  size: size * .11, color: Luxe.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final int lost;
  final int found;
  final int active;
  const _StatsCard(
      {required this.lost, required this.found, required this.active});

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        Icons.description_rounded,
        Luxe.primary,
        lost,
        'Lost Reports',
        'Submitted'
      ),
      (
        Icons.inventory_2_rounded,
        Luxe.accent,
        found,
        'Found Reports',
        'Submitted'
      ),
      (Icons.verified_rounded, Luxe.info, active, 'Total Active', 'Reports'),
    ];
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Luxe.s3, vertical: Luxe.s2),
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(Luxe.rCard),
        border: Border.all(color: Luxe.primary.withValues(alpha: .06)),
        boxShadow: Luxe.lift(),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: Luxe.s2),
            Expanded(
              child: _StatItem(
                icon: stats[i].$1,
                color: stats[i].$2,
                value: stats[i].$3,
                label: stats[i].$4,
                sublabel: stats[i].$5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final String sublabel;
  const _StatItem(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label,
      required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(Luxe.rSmall),
            border: Border.all(color: color.withValues(alpha: .14)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: Luxe.s1),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: Luxe.body.copyWith(color: Luxe.ink),
            children: [
              TextSpan(
                  text: '$value ',
                  style: Luxe.display.copyWith(fontSize: 18, color: color)),
              TextSpan(text: label, style: Luxe.body.copyWith(fontSize: 10.5)),
            ],
          ),
        ),
        Text(sublabel,
            style: Luxe.caption.copyWith(fontSize: 10.5, color: Luxe.inkMuted)),
      ],
    );
  }
}

class _MyReportsCard extends StatelessWidget {
  final List<Item> lost;
  final List<Item> found;
  final VoidCallback onLost;
  final VoidCallback onFound;

  const _MyReportsCard({
    required this.lost,
    required this.found,
    required this.onLost,
    required this.onFound,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(Luxe.rCard),
        border: Border.all(color: Luxe.primary.withValues(alpha: .06)),
        boxShadow: Luxe.lift(),
      ),
      child: Column(
        children: [
          _ReportHeader(
              title: 'My Lost Reports',
              icon: Icons.description_rounded,
              tint: Luxe.primary,
              total: lost.length,
              reports: lost,
              onTap: onLost),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: Luxe.s4),
              color: Luxe.hairline),
          _ReportHeader(
              title: 'My Found Reports',
              icon: Icons.inventory_2_rounded,
              tint: Luxe.accent,
              total: found.length,
              reports: found,
              onTap: onFound),
        ],
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final int total;
  final List<Item> reports;
  final VoidCallback onTap;

  const _ReportHeader(
      {required this.title,
      required this.icon,
      required this.tint,
      required this.total,
      required this.reports,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeCount = reports
        .where((report) =>
            report.status == ItemStatus.active ||
            report.status == ItemStatus.matchedPending)
        .length;
    final statusLabel = '$activeCount Active';
    final semanticLabel = title == 'My Lost Reports'
        ? 'View my lost reports'
        : 'View my found reports';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        final rowPadding = compact ? 8.0 : 10.0;
        final iconTileSize = compact ? 38.0 : 40.0;
        final arrowTouchSize = compact ? 34.0 : 36.0;
        final arrowVisibleSize = compact ? 26.0 : 28.0;
        final badgeWidth = compact ? 68.0 : 72.0;

        return Semantics(
          button: true,
          label: semanticLabel,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: rowPadding, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: iconTileSize,
                    height: iconTileSize,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(Luxe.rSmall),
                      border: Border.all(color: tint.withValues(alpha: .16)),
                    ),
                    child: Icon(icon, color: tint, size: compact ? 20 : 21),
                  ),
                  SizedBox(width: compact ? 7 : 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: Luxe.title.copyWith(fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: Luxe.s1),
                        RichText(
                          text: TextSpan(
                            style: Luxe.body.copyWith(color: Luxe.inkMuted),
                            children: [
                              TextSpan(
                                text: '$total',
                                style: Luxe.display
                                    .copyWith(fontSize: 18, color: tint),
                              ),
                              const TextSpan(text: ' Submitted'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 4 : 7),
                  SizedBox(
                    width: badgeWidth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Luxe.info.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(Luxe.rChip),
                        border:
                            Border.all(color: Luxe.info.withValues(alpha: .14)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Luxe.info,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              maxLines: 1,
                              style: Luxe.caption.copyWith(
                                  fontSize: 11,
                                  color: Luxe.info,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 3 : 5),
                  SizedBox(
                    width: arrowTouchSize,
                    height: arrowTouchSize,
                    child: Center(
                      child: LuxeArrowButton(size: arrowVisibleSize),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Luxe.s3 - 2, vertical: Luxe.s3),
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(Luxe.rCard),
        border: Border.all(color: Luxe.primary.withValues(alpha: 0.07)),
        boxShadow: Luxe.lift(),
      ),
      child: Stack(
        children: [
          // Soft ambient shield glow bleeding from the right edge.
          const Positioned(
            right: -26,
            top: -14,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: ShieldMark(size: 118, showCheck: false),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShieldMark(size: 54),
                  const SizedBox(width: Luxe.s2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Privacy Protected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Luxe.title.copyWith(fontSize: 17)),
                        const SizedBox(height: Luxe.s1),
                        Text(
                          'Your reports are private — only you and '
                          'authorised staff can see them.',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Luxe.body.copyWith(
                              fontSize: 12, height: 1.3, color: Luxe.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Luxe.s2),
              Container(height: 1, color: Luxe.hairline),
              const SizedBox(height: Luxe.s1),
              const SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    const Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LuxeSecurityChip('Secure'),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LuxeSecurityChip('Encrypted'),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LuxeSecurityChip('Trusted'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ── Hero action card (Report Lost / Report Found) ─────────────────
class _HeroActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Gradient gradient;
  final Color glow;
  final List<IconData> illustration;
  final VoidCallback onTap;

  const _HeroActionCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.illustration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowCard = constraints.maxWidth < 170;
        final cardHeight = narrowCard ? 132.0 : 128.0;
        final semanticLabel = title == 'Report Lost Item'
            ? 'Report a lost item'
            : 'Report a found item';
        return Semantics(
          button: true,
          label: semanticLabel,
          child: Pressable(
            onTap: onTap,
            child: Container(
              height: cardHeight,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(Luxe.rCard),
                boxShadow: Luxe.liftStrong(tint: glow),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: CardIllustration(icons: illustration)),
                  // Diagonal glass highlight
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: Luxe.glassSheen,
                          borderRadius: BorderRadius.circular(Luxe.rCard),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Luxe.s2 + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius:
                                BorderRadius.circular(Luxe.rSmall + 4),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.38)),
                          ),
                          child: Icon(icon, color: Colors.white, size: 21),
                        ),
                        Expanded(
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(0, -14),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(title,
                                        maxLines: 1,
                                        textAlign: TextAlign.center,
                                        style: Luxe.cardTitle.copyWith(
                                            fontSize: 18, color: Colors.white)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    right: Luxe.s2 + 2,
                    bottom: Luxe.s2 + 2,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                          child: LuxeArrowButton(onDark: true, size: 28)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ── Report summary card (My Lost / My Found) ──────────────────────
class _ReportSummaryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final int total;
  final List<MapEntry<String, int>> chips;
  final Color Function(String) colorOf;
  final VoidCallback onTap;

  const _ReportSummaryCard({
    required this.title,
    required this.icon,
    required this.tint,
    required this.total,
    required this.chips,
    required this.colorOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Luxe.s4 + 2),
        decoration: BoxDecoration(
          color: Luxe.surface,
          borderRadius: BorderRadius.circular(Luxe.rCard),
          border: Border.all(color: tint.withValues(alpha: 0.08)),
          boxShadow: Luxe.lift(tint: tint),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tint.withValues(alpha: 0.16),
                        tint.withValues(alpha: 0.07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(Luxe.rSmall + 2),
                    border: Border.all(color: tint.withValues(alpha: 0.14)),
                  ),
                  child: Icon(icon, color: tint, size: 24),
                ),
                const SizedBox(width: Luxe.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Luxe.title),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$total',
                              style: Luxe.display
                                  .copyWith(fontSize: 22, color: tint)),
                          const SizedBox(width: 5),
                          Text('Submitted',
                              style:
                                  Luxe.caption.copyWith(color: Luxe.inkMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Luxe.s2),
                const LuxeArrowButton(size: 42),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: Luxe.s3 + 2),
              Container(height: 1, color: Luxe.hairline),
              const SizedBox(height: Luxe.s3),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: Luxe.s2,
                  runSpacing: Luxe.s2,
                  children: [
                    for (final e in chips)
                      LuxeStatusChip(
                          label: '${e.value} ${e.key}', color: colorOf(e.key)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Screen 2: Report Lost ────────────────────────────────────────
class ReportLostScreen extends StatefulWidget {
  const ReportLostScreen({super.key});
  @override
  State<ReportLostScreen> createState() => _ReportLostState();
}

class _ReportLostState extends State<ReportLostScreen> {
  final _key = GlobalKey<FormState>();
  String? _cat, _loc;
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final List<File> _images = [];
  bool _done = false;
  bool _saving = false;

  static const _cats = [
    'Phone',
    'Wallet',
    'ID Card',
    'Keys',
    'Bag',
    'Laptop',
    'Books',
    'Other'
  ];
  static const _locs = [
    'Block A',
    'Block B',
    'Block C',
    'Library',
    'Cafeteria',
    'Sports Complex',
    'Main Entrance',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _descC.addListener(_descriptionChanged);
  }

  void _descriptionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _descC.removeListener(_descriptionChanged);
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  /// Persists the report to Firestore through [LostFoundService].
  ///
  /// The screen never touches Firestore itself — it hands an [Item] to the
  /// service and only ever sees an [AuthFailure] with a display-ready message.
  Future<void> _submit() async {
    if (!(_key.currentState!.validate() && _cat != null && _loc != null)) {
      _toast(context, 'Please fill all fields');
      return;
    }

    final appState = context.read<AppState>();

    setState(() => _saving = true);
    try {
      await appState.createReport(
        Item(
          type: ItemType.lost,
          title: _titleC.text,
          category: _cat!,
          description: _descC.text,
          whereLost: _loc!,
          whenLost: DateTime.now(),
          reportedByUid: appState.firebaseUid ?? '',
          reportedByStudentId: appState.userId ?? '',
        ),
        images: _images.isNotEmpty ? _images : null,
      );
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, failure.message);
    } on CloudinaryException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Photo upload failed: ${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not submit your report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done)
      return _SuccessView(
          title: 'Report Submitted!',
          msg:
              "Your item has been reported. Admin will review it. We'll notify you if a match is found.",
          onHome: () => context.go('/lost-found'),
          onSub: () => context.push('/lost-found/my-lost'),
          subLabel: 'View My Reports');
    final horizontal = MediaQuery.sizeOf(context).width < 360 ? 16.0 : 22.0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        24;
    return Scaffold(
      backgroundColor: Luxe.bg,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.paddingOf(context).top + 112),
        child: const _ReportLostHeader(),
      ),
      body: ColoredBox(
        color: Luxe.bg,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 24),
            decoration: const BoxDecoration(
              color: Luxe.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: Form(
              key: _key,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ReportLostInfoCard(),
                  const SizedBox(height: 14),
                  _ReportLostSelectCard(
                    icon: Icons.grid_view_rounded,
                    label: 'Category',
                    hint: 'Select category',
                    value: _cat,
                    items: _cats,
                    onChanged: (v) => setState(() => _cat = v),
                  ),
                  const SizedBox(height: 14),
                  _ReportLostTextCard(
                    icon: Icons.title_rounded,
                    label: 'Item Title',
                    hint: 'Enter item title',
                    controller: _titleC,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Item title is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _ReportLostDescriptionCard(controller: _descC),
                  const SizedBox(height: 14),
                  _ReportLostSelectCard(
                    icon: Icons.location_on_rounded,
                    label: 'Where Lost',
                    hint: 'Select location',
                    value: _loc,
                    items: _locs,
                    onChanged: (v) => setState(() => _loc = v),
                  ),
                  const SizedBox(height: 14),
                  _PhotoBox(
                    polished: true,
                    onImagesChanged: (imgs) => _images
                      ..clear()
                      ..addAll(imgs),
                  ),
                  const SizedBox(height: 18),
                  _ReportLostSubmitButton(
                    saving: _saving,
                    onPressed: _saving ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  _ReportLostCancelButton(onPressed: () => context.pop()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportLostHeader extends StatelessWidget {
  const _ReportLostHeader();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(gradient: Luxe.heroGradient),
        child: Stack(
          children: [
            Positioned(
              right: -12,
              top: 24,
              child: Opacity(
                opacity: .10,
                child: Row(
                  children: const [
                    Icon(Icons.help_outline_rounded,
                        color: Colors.white, size: 70),
                    SizedBox(width: 6),
                    Icon(Icons.backpack_rounded, color: Colors.white, size: 94),
                    Icon(Icons.help_outline_rounded,
                        color: Colors.white, size: 58),
                  ],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Back',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .12)),
                        ),
                        child: IconButton(
                          tooltip: 'Back',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 23),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Report Lost Item',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportLostInfoCard extends StatelessWidget {
  const _ReportLostInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Luxe.primary.withValues(alpha: .12)),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: .45),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Luxe.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active reports are reviewed before submission.',
                  style: TextStyle(
                    color: Luxe.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Provide accurate details to help us find your item faster.',
                  style: TextStyle(
                    color: Luxe.inkSoft,
                    fontSize: 13,
                    height: 1.35,
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

class _ReportLostIconTile extends StatelessWidget {
  final IconData icon;
  const _ReportLostIconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Luxe.primary.withValues(alpha: .08)),
      ),
      child: Icon(icon, color: Luxe.primary, size: 23),
    );
  }
}

class _ReportLostSelectCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _ReportLostSelectCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: (_) => value == null ? 'Select ${label.toLowerCase()}' : null,
      builder: (state) {
        final invalid = state.hasError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: invalid
                      ? Luxe.primary
                      : Luxe.primary.withValues(alpha: .12),
                ),
                boxShadow: Luxe.lift(strength: .35),
              ),
              child: Row(
                children: [
                  _ReportLostIconTile(icon: icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Luxe.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final targetWidth =
                                (MediaQuery.sizeOf(context).width * .62)
                                    .clamp(190.0, 230.0)
                                    .toDouble();
                            final dropdownWidth =
                                targetWidth > constraints.maxWidth
                                    ? constraints.maxWidth
                                    : targetWidth;
                            return Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: dropdownWidth,
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: value,
                                    hint: Text(hint,
                                        style: const TextStyle(
                                            color: Luxe.inkSoft, fontSize: 14)),
                                    isExpanded: true,
                                    focusColor: Colors.white,
                                    dropdownColor: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    elevation: 8,
                                    menuMaxHeight: 320,
                                    menuWidth: dropdownWidth,
                                    alignment: AlignmentDirectional.centerStart,
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Luxe.inkSoft,
                                        size: 23),
                                    style: const TextStyle(
                                        color: Luxe.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                    items: items
                                        .map((item) => DropdownMenuItem<String>(
                                              value: item,
                                              child: Text(item),
                                            ))
                                        .toList(),
                                    onChanged: (selected) {
                                      state.didChange(selected);
                                      onChanged(selected);
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (invalid)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text(state.errorText!,
                    style: const TextStyle(
                        color: Luxe.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        );
      },
    );
  }
}

class _ReportLostTextCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?) validator;

  const _ReportLostTextCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: focused
                      ? Luxe.primary
                      : Luxe.primary.withValues(alpha: .12),
                  width: focused ? 1.4 : 1),
              boxShadow: Luxe.lift(strength: .35),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReportLostIconTile(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Luxe.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      TextFormField(
                        controller: controller,
                        validator: validator,
                        textInputAction: TextInputAction.next,
                        style:
                            const TextStyle(color: Luxe.inkSoft, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: const TextStyle(
                              color: Luxe.inkSoft, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          errorStyle: const TextStyle(
                              color: Luxe.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportLostDescriptionCard extends StatelessWidget {
  final TextEditingController controller;
  const _ReportLostDescriptionCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: focused
                      ? Luxe.primary
                      : Luxe.primary.withValues(alpha: .12),
                  width: focused ? 1.4 : 1),
              boxShadow: Luxe.lift(strength: .35),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ReportLostIconTile(icon: Icons.description_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Description',
                          style: TextStyle(
                              color: Luxe.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      TextFormField(
                        controller: controller,
                        minLines: 4,
                        maxLines: 6,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Description is required'
                                : null,
                        style:
                            const TextStyle(color: Luxe.inkSoft, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Describe your lost item in detail',
                          hintStyle:
                              TextStyle(color: Luxe.inkSoft, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          errorStyle: TextStyle(
                              color: Luxe.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${controller.text.length} characters',
                          style: const TextStyle(
                              color: Luxe.inkMuted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportLostSubmitButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onPressed;
  const _ReportLostSubmitButton(
      {required this.saving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Submit report',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: Luxe.heroGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: Luxe.liftStrong(tint: Luxe.primary),
          ),
          child: Center(
            child: saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, color: Colors.white, size: 21),
                      SizedBox(width: 10),
                      Text('Submit Report',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReportLostCancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ReportLostCancelButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancel report',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Luxe.primary, width: 1.3),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, color: Luxe.primary, size: 22),
              SizedBox(width: 10),
              Text('Cancel',
                  style: TextStyle(
                      color: Luxe.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Screen 3: Report Found ───────────────────────────────────────
class ReportFoundScreen extends StatefulWidget {
  const ReportFoundScreen({super.key});
  @override
  State<ReportFoundScreen> createState() => _ReportFoundState();
}

class _ReportFoundState extends State<ReportFoundScreen> {
  String? _cat, _loc;
  final _descC = TextEditingController();
  final List<File> _images = [];
  bool _done = false;
  bool _saving = false;

  static const _cats = [
    'Phone',
    'Wallet',
    'ID Card',
    'Keys',
    'Bag',
    'Laptop',
    'Books',
    'Other'
  ];
  static const _locs = [
    'Block A',
    'Block B',
    'Block C',
    'Library',
    'Cafeteria',
    'Sports Complex',
    'Main Entrance',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _descC.addListener(_descriptionChanged);
  }

  void _descriptionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _descC.removeListener(_descriptionChanged);
    _descC.dispose();
    super.dispose();
  }

  /// Persists the found report to Firestore through [LostFoundService].
  ///
  /// Mirrors `_ReportLostState._submit` — the only difference is
  /// [ItemType.found]. The screen never touches Firestore itself and only ever
  /// sees an [AuthFailure] carrying a display-ready message.
  Future<void> _submit() async {
    // Validation unchanged: this form has no Form/validator, so the three
    // fields are checked inline exactly as before.
    if (!(_cat != null && _loc != null && _descC.text.isNotEmpty)) {
      _toast(context, 'Please fill all fields');
      return;
    }

    final appState = context.read<AppState>();

    setState(() => _saving = true);
    try {
      await appState.createReport(
        Item(
          type: ItemType.found,
          title: _descC.text,
          category: _cat!,
          description: _descC.text,
          whereLost: _loc!,
          whenLost: DateTime.now(),
          reportedByUid: appState.firebaseUid ?? '',
          reportedByStudentId: appState.userId ?? '',
        ),
        images: _images.isNotEmpty ? _images : null,
      );
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, failure.message);
    } on CloudinaryException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Photo upload failed: ${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not submit your report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done)
      return _FoundReportStepperView(
          onHome: () => context.go('/lost-found'),
          onViewReports: () => context.push('/lost-found/my-found'));
    final horizontal = MediaQuery.sizeOf(context).width < 360 ? 18.0 : 24.0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        24;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        // 88 dp of content plus the device's safe-area inset keeps the full
        // hero compact while still making room for the status bar/cutout.
        preferredSize: Size.fromHeight(MediaQuery.paddingOf(context).top + 88),
        child: const _ReportFoundHeader(),
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ReportFoundReminder(),
            const SizedBox(height: 24),
            _FoundSelectField(
              label: 'Category',
              hint: 'Select category',
              value: _cat,
              items: _cats,
              onChanged: (v) => setState(() => _cat = v),
            ),
            const SizedBox(height: 20),
            _FoundDescriptionField(controller: _descC),
            const SizedBox(height: 20),
            _FoundSelectField(
              label: 'Where Found',
              hint: 'Select location',
              value: _loc,
              items: _locs,
              onChanged: (v) => setState(() => _loc = v),
            ),
            const SizedBox(height: 24),
            _PhotoBox(
              foundStyle: true,
              onImagesChanged: (imgs) => _images
                ..clear()
                ..addAll(imgs),
            ),
            const SizedBox(height: 24),
            _ReportFoundSubmitButton(
              saving: _saving,
              onPressed: _saving ? null : _submit,
            ),
            const SizedBox(height: 12),
            _ReportFoundCancelButton(onPressed: () => context.pop()),
          ],
        ),
      ),
    );
  }
}

// ── Screen 4: My Lost Reports ────────────────────────────────────
class _ReportFoundHeader extends StatelessWidget {
  const _ReportFoundHeader();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          gradient: Luxe.heroGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: .22,
                  child: CustomPaint(painter: HeaderBackdropPainter()),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 26,
              child: IgnorePointer(
                child: Opacity(
                  opacity: .18,
                  child: ShieldMark(size: 72, showCheck: false),
                ),
              ),
            ),
            Positioned(
              right: -8,
              bottom: -10,
              child: IgnorePointer(
                child: Icon(Icons.inventory_2_rounded,
                    color: Colors.white.withValues(alpha: .06), size: 62),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 7, 20, 17),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Back',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Back',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Luxe.primaryDeep, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Report Found Item',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Help return items to their rightful owners',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFoundReminder extends StatelessWidget {
  const _ReportFoundReminder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F5),
        borderRadius: BorderRadius.circular(14),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: .35),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                color: Luxe.primaryDeep, size: 18),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important Reminder',
                  style: TextStyle(
                    color: Luxe.primaryDeep,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'After submitting, hand the item to Lost & Found Office (Block A, Level 1).',
                  style: TextStyle(
                    color: Luxe.inkSoft,
                    fontSize: 11.5,
                    height: 1.3,
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

InputDecoration _foundInputDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Luxe.inkMuted, fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Luxe.inkMuted.withValues(alpha: .34)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Luxe.inkMuted.withValues(alpha: .34)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Luxe.primary, width: 1.5),
    ),
  );
}

class _FoundSelectField extends StatelessWidget {
  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _FoundSelectField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: const TextStyle(
                color: Luxe.ink, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(color: Luxe.inkMuted, fontSize: 14)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Luxe.inkSoft, size: 24),
          style: const TextStyle(
              color: Luxe.ink, fontSize: 14, fontWeight: FontWeight.w500),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          decoration: _foundInputDecoration(),
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _FoundDescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const _FoundDescriptionField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Description',
            style: TextStyle(
                color: Luxe.ink, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Stack(
          children: [
            TextFormField(
              controller: controller,
              minLines: 5,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: Luxe.ink, fontSize: 14),
              decoration: _foundInputDecoration(
                hintText: 'Describe the item in detail…',
              ).copyWith(
                alignLabelWithHint: true,
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 38),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 10,
              child: Text(
                '${controller.text.length}/300',
                style: const TextStyle(color: Luxe.inkSoft, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReportFoundSubmitButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onPressed;

  const _ReportFoundSubmitButton({required this.saving, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Submit Report',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: Luxe.heroGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: Luxe.liftStrong(tint: Luxe.primary),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (saving)
                const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white),
                )
              else
                const Icon(Icons.send_rounded, color: Colors.white, size: 21),
              const SizedBox(width: 10),
              Text(
                saving ? 'Submitting…' : 'Submit Report',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportFoundCancelButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ReportFoundCancelButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.close_rounded, size: 21),
        label: const Text('Cancel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Luxe.primaryDeep,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Luxe.primary, width: 1.2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ── Student-facing lost-report status view ───────────────────────
//
// Students see exactly three buckets for their lost reports, never the raw
// internal lifecycle. Every historic status is collapsed into one of the
// three so no report is ever hidden from the student.

/// True when a lost report has no further student action — the item was
/// returned/claimed (`Resolved`), or the student closed it themselves
/// (`Closed`). These render under the single student-facing label "Closed".
extension LostReportStudentView on Item {
  bool get isLostClosed =>
      status == ItemStatus.resolved ||
      status == ItemStatus.returned ||
      status == ItemStatus.closed;
}

/// A match is "unresolved" while it is not yet completed — a draft
/// (`Proposed`) or a confirmed possible match (`Approved`). Either one keeps
/// its lost report in the student's "Possible Matches" section.
bool _isUnresolvedMatch(LfMatch m) =>
    m.status == MatchStatus.proposed || m.status == MatchStatus.approved;

class MyLostReportsScreen extends StatefulWidget {
  const MyLostReportsScreen({super.key});
  @override
  State<MyLostReportsScreen> createState() => _MyLostReportsScreenState();
}

class _MyLostReportsScreenState extends State<MyLostReportsScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;
  late final Stream<List<LfMatch>> _matches;

  /// Which section is shown. 0 = Possible Matches, 1 = Active, 2 = Closed.
  /// Defaults to Active.
  int _selected = 1;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchMyLostReports();
    _matches = context.read<AppState>().watchMyMatches();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: _reports,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <Item>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        // The service maps every FirebaseException to an AuthFailure, so this
        // message is already safe to show — permission denied, offline and
        // network failures all arrive here with their own wording.
        final error = snapshot.error;
        return StreamBuilder<List<LfMatch>>(
          stream: _matches,
          builder: (context, matchSnap) {
            final matches = matchSnap.data ?? const <LfMatch>[];
            // Count unresolved matches per lost report, so a report moves to
            // Possible Matches the moment any candidate is proposed/approved.
            final unresolved = <String, int>{};
            for (final m in matches) {
              if (_isUnresolvedMatch(m)) {
                unresolved[m.lostReportId] =
                    (unresolved[m.lostReportId] ?? 0) + 1;
              }
            }

            final possible = reports
                .where((r) => !r.isLostClosed && (unresolved[r.id] ?? 0) > 0)
                .toList();
            final active = reports
                .where((r) => !r.isLostClosed && (unresolved[r.id] ?? 0) == 0)
                .toList();
            final closed = reports.where((r) => r.isLostClosed).toList();

            final List<Item> visible = switch (_selected) {
              0 => possible,
              2 => closed,
              _ => active,
            };

            return Scaffold(
              appBar: _gradientAppBar('My Lost Reports', context, actions: [
                TextButton.icon(
                    onPressed: () => context.push('/lost-found/report-lost'),
                    icon: const Icon(Icons.add, color: Colors.white, size: 16),
                    label: const Text('Report',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700))),
              ]),
              body: isLoading && reports.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.red))
                  : error != null
                      ? EmptyState(
                          title: 'Could Not Load Reports',
                          subtitle: error is AuthFailure
                              ? error.message
                              : 'Something went wrong. Please try again.',
                          icon: Icons.cloud_off_rounded,
                        )
                      : Column(children: [
                          _LostSectionSwitcher(
                            possibleCount: possible.length,
                            activeCount: active.length,
                            closedCount: closed.length,
                            selected: _selected,
                            onChanged: (i) => setState(() => _selected = i),
                          ),
                          Expanded(
                            child: visible.isEmpty
                                ? _lostEmptyState(_selected)
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 16),
                                    itemCount: visible.length,
                                    itemBuilder: (ctx, i) {
                                      final r = visible[i];
                                      return _LostReportCard(
                                        report: r,
                                        badgeLabel: _selected == 0
                                            ? 'Possible Match'
                                            : _selected == 2
                                                ? 'Closed'
                                                : r.status ==
                                                        ItemStatus
                                                            .requestedClose
                                                    ? 'Closure Requested'
                                                    : 'Active',
                                        matchCount: unresolved[r.id] ?? 0,
                                        onTap: () => context
                                            .push('/lost-found/lost/${r.id}'),
                                      )
                                          .animate()
                                          .fadeIn(delay: (i * 50).ms)
                                          .slideY(begin: 0.12);
                                    },
                                  ),
                          ),
                        ]),
            );
          },
        );
      },
    );
  }

  Widget _lostEmptyState(int section) {
    return switch (section) {
      0 => const EmptyState(
          title: 'No possible matches yet.', icon: Icons.link_rounded),
      2 => const EmptyState(
          title: 'No closed lost reports yet.', icon: Icons.archive_rounded),
      _ => const EmptyState(
          title: 'No active lost reports.', icon: Icons.search_off_rounded),
    };
  }
}

/// Compact three-option segmented control: Possible Matches / Active / Closed,
/// with live counts. The selected segment uses the app's red-to-pink gradient;
/// there is no fourth option and no filter/overflow affordance.
class _LostSectionSwitcher extends StatelessWidget {
  final int possibleCount;
  final int activeCount;
  final int closedCount;
  final int selected;
  final ValueChanged<int> onChanged;

  const _LostSectionSwitcher({
    required this.possibleCount,
    required this.activeCount,
    required this.closedCount,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          _segment('Possible Matches', possibleCount, 0),
          _segment('Active', activeCount, 1),
          _segment('Closed', closedCount, 2),
        ]),
      ),
    );
  }

  Widget _segment(String label, int count, int index) {
    final isSelected = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One lost report in the student list. Shows the first photo (or a
/// placeholder), category, description, location, reported date and a compact
/// status badge — with no vertical accent line or left-border indicator.
class _LostReportCard extends StatelessWidget {
  final Item report;
  final String badgeLabel;
  final int matchCount;
  final VoidCallback onTap;
  const _LostReportCard({
    required this.report,
    required this.badgeLabel,
    required this.matchCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final closed = report.isLostClosed;
    final returnedAt = report.updatedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.red.withOpacity(0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(report.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.red)),
                      ),
                      StatusBadge(badgeLabel),
                    ]),
                    const SizedBox(height: 4),
                    Text(report.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Lost at ${report.whereLost}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(height: 2),
                    Text('Reported ${fmtDate(report.whenLostLabel)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                    if (matchCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        matchCount == 1
                            ? '1 possible match'
                            : '$matchCount possible matches',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.red),
                      ),
                    ],
                    if (closed && returnedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Item returned on ${fmtDate(returnedAt.toIso8601String())}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final hasPhoto = report.imageUrls.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(
                report.imageUrls.first,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _placeholder(),
                errorBuilder: (context, error, stack) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF0F2F5),
      child:
          const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 26),
    );
  }
}

// ── Student-facing found-report status view ──────────────────────
//
// Students see exactly two buckets for their found reports, never the raw
// internal lifecycle. Every historic status is collapsed into one of the two
// so no report is ever hidden from the student.

/// True when a found report has no further student action — the physical
/// handover has been confirmed (`In Inventory`), the item was returned to its
/// owner (`Returned`), an admin resolved it (`Resolved`), or the student
/// closed it themselves (`Closed`). These all render under the single
/// student-facing label "Closed".
extension FoundReportStudentView on Item {
  bool get isFoundClosed =>
      status == ItemStatus.inInventory ||
      status == ItemStatus.resolved ||
      status == ItemStatus.returned ||
      status == ItemStatus.closed;

  /// The only two labels a student ever sees for a found report. The internal
  /// wire value "Awaiting Handover" is deliberately never surfaced — students
  /// see the short label "Awaiting".
  String get foundStudentStatus => isFoundClosed ? 'Closed' : 'Awaiting';
}

// ── Screen 5: My Found Reports ───────────────────────────────────
class MyFoundReportsScreen extends StatefulWidget {
  const MyFoundReportsScreen({super.key});
  @override
  State<MyFoundReportsScreen> createState() => _MyFoundReportsScreenState();
}

class _MyFoundReportsScreenState extends State<MyFoundReportsScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;

  /// Which section is shown. Defaults to Awaiting.
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchMyFoundReports();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: _reports,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Item>[];
        final awaiting = all.where((r) => !r.isFoundClosed).toList();
        final closed = all.where((r) => r.isFoundClosed).toList();
        final visible = _showClosed ? closed : awaiting;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        // The service maps every FirebaseException to an AuthFailure, so this
        // message is already safe to show — permission denied, offline and
        // network failures all arrive here with their own wording.
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('My Found Reports', context),
          body: isLoading && all.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Reports',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : Column(children: [
                      _FoundSectionSwitcher(
                        awaitingCount: awaiting.length,
                        closedCount: closed.length,
                        showClosed: _showClosed,
                        onChanged: (v) => setState(() => _showClosed = v),
                      ),
                      if (!_showClosed && awaiting.isNotEmpty)
                        const _FoundReminder(),
                      Expanded(
                        child: visible.isEmpty
                            ? EmptyState(
                                title: _showClosed
                                    ? 'No closed found reports yet.'
                                    : 'No items awaiting handover.',
                                icon: _showClosed
                                    ? Icons.archive_rounded
                                    : Icons.inventory_2_rounded,
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: visible.length,
                                itemBuilder: (ctx, i) {
                                  final r = visible[i];
                                  return _FoundReportCard(
                                    report: r,
                                    onTap: () => context
                                        .push('/lost-found/found/${r.id}'),
                                  )
                                      .animate()
                                      .fadeIn(delay: (i * 50).ms)
                                      .slideY(begin: 0.12);
                                },
                              ),
                      ),
                    ]),
        );
      },
    );
  }
}

/// Compact two-option segmented control: Awaiting / Closed, with live counts.
/// The selected segment uses the app's red-to-pink gradient; there is no
/// third option and no overflow/filter affordance.
class _FoundSectionSwitcher extends StatelessWidget {
  final int awaitingCount;
  final int closedCount;
  final bool showClosed;
  final ValueChanged<bool> onChanged;

  const _FoundSectionSwitcher({
    required this.awaitingCount,
    required this.closedCount,
    required this.showClosed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          _segment('Awaiting', awaitingCount,
              selected: !showClosed, onTap: () => onChanged(false)),
          _segment('Closed', closedCount,
              selected: showClosed, onTap: () => onChanged(true)),
        ]),
      ),
    );
  }

  Widget _segment(String label, int count,
      {required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Short reminder shown above the Awaiting list. Deliberately has no left
/// accent border — the screen uses only spacing, typography and the badge to
/// communicate state.
class _FoundReminder extends StatelessWidget {
  const _FoundReminder();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please hand this item to the Lost & Found Office (Block A, Level 1).',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One found report in the student list. Shows the first photo (or a
/// placeholder), category, description, location, submitted date and a compact
/// status badge — with no vertical accent line or left-border indicator.
class _FoundReportCard extends StatelessWidget {
  final Item report;
  final VoidCallback onTap;
  const _FoundReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final closed = report.isFoundClosed;
    // `updatedAt` is the moment the handover/return was confirmed for the two
    // staff-confirmed states; for a student self-close it is not a handover
    // timestamp, so no "Handover completed" line is shown there.
    final bool handoverConfirmed = report.status == ItemStatus.inInventory ||
        report.status == ItemStatus.returned;
    final handoverAt = report.updatedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.red.withOpacity(0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(report.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.red)),
                      ),
                      StatusBadge(report.foundStudentStatus),
                    ]),
                    const SizedBox(height: 4),
                    Text(report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Found at ${report.whereLost}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(height: 2),
                    Text('Submitted ${fmtDate(report.whenLostLabel)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                    if (closed && handoverConfirmed && handoverAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Handover completed on ${fmtDate(handoverAt.toIso8601String())}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final hasPhoto = report.imageUrls.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(
                report.imageUrls.first,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _placeholder(),
                errorBuilder: (context, error, stack) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF0F2F5),
      child: const Icon(Icons.inventory_2_rounded,
          color: AppTheme.textMuted, size: 26),
    );
  }
}

// ── Screen 6: Lost Detail (Student) ─────────────────────────────
class LostDetailScreen extends StatefulWidget {
  final String id;
  const LostDetailScreen({super.key, required this.id});
  @override
  State<LostDetailScreen> createState() => _LostDetailScreenState();
}

class _LostDetailScreenState extends State<LostDetailScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<Item?> _report;

  /// The signed-in student's own matches (Workflow 3) and return QR codes.
  /// The body filters both to this report.
  late final Stream<List<LfMatch>> _matches;
  late final Stream<List<QrTransaction>> _returnQr;

  /// Guards the one-shot "Collected" dialog so it appears exactly once, when
  /// the match first becomes Completed.
  bool _collectedShown = false;

  @override
  void initState() {
    super.initState();
    // The screen knows only the document ID from the route; AppState resolves
    // the stream against the signed-in caller. No Firebase import here.
    _report = context.read<AppState>().watchReport(widget.id);
    _matches = context.read<AppState>().watchMyMatches();
    _returnQr = context.read<AppState>().watchMyActiveQr(QrKind.return_);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Item?>(
      stream: _report,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final r = snapshot.data;

        return Scaffold(
          appBar: _gradientAppBar(r?.id ?? widget.id, context),
          body: isLoading && r == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Report',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : r == null
                      ? const EmptyState(
                          title: 'Report Not Found',
                          subtitle: 'This report may have been removed.',
                          icon: Icons.search_off_rounded,
                        )
                      : r.isDeleted
                          ? const EmptyState(
                              title: 'Report Deleted',
                              subtitle: 'This report is no longer available.',
                              icon: Icons.delete_outline_rounded,
                            )
                          : _lostDetailBody(context, r),
        );
      },
    );
  }

  Widget _lostDetailBody(BuildContext context, Item r) {
    return StreamBuilder<List<LfMatch>>(
      stream: _matches,
      builder: (context, matchSnap) {
        final matches = (matchSnap.data ?? const <LfMatch>[])
            .where((m) => m.lostReportId == widget.id)
            .toList()
          ..sort((a, b) =>
              (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        // Newest first, so the current match drives the summary.
        final LfMatch? match = matches.isEmpty ? null : matches.first;
        final bool approved =
            match != null && match.status == MatchStatus.approved;
        final bool completed =
            match != null && match.status == MatchStatus.completed;
        if (completed && !_collectedShown) {
          _collectedShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showCollectedDialog(context);
          });
        }

        return StreamBuilder<List<QrTransaction>>(
          stream: _returnQr,
          builder: (context, qrSnap) {
            final qrs = qrSnap.data ?? const <QrTransaction>[];
            final forThisReport =
                qrs.where((t) => t.lostReportId == widget.id).toList();
            final QrTransaction? qr =
                forThisReport.isEmpty ? null : forThisReport.first;
            final bool qrIssued = qr != null && qr.status == QrStatus.issued;
            final bool qrScanned = qr != null && qr.status == QrStatus.scanned;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workflow 3 — the admin reviewed a match against this
                  // report. Only a safe summary is shown: never finder
                  // identity or contact details.
                  if (completed) ...[
                    const _StatusBanner(
                        text:
                            'This item has been returned to you — welcome back!'),
                    const SizedBox(height: 10),
                  ] else if (approved) ...[
                    NoticeBox(
                      message:
                          'A possible match was found for your item. Please visit the Inventory Office (Block A, Level 1) to verify ownership.',
                      borderColor: AppTheme.red,
                      icon: Icons.link_rounded,
                    ),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(r.title,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800))),
                            StatusBadge(r.status.wireValue),
                          ]),
                          const Divider(height: 20),
                          InfoRow(label: 'Category', value: r.category),
                          InfoRow(label: 'Where Lost', value: r.whereLost),
                          InfoRow(
                              label: 'When Lost',
                              value: fmtDate(r.whenLostLabel)),
                          const Divider(height: 12),
                          const Text('Description',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMuted)),
                          const SizedBox(height: 8),
                          Text(r.description,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  height: 1.65)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // AI Potential Matches — show proposed AI suggestions with scores.
                  if (r.status == ItemStatus.active ||
                      r.status == ItemStatus.matchedPending) ...[
                    _buildAiSuggestions(matches),
                  ],
                  const SizedBox(height: 10),
                  // Return QR scan section — shown while a return code for
                  // this report is Issued.
                  if (qrIssued) ...[
                    const SectionLabel('Collect Your Item'),
                    _QrScanSection(
                      instruction:
                          'The office has a Return QR ready for you. Tap Scan QR to use your camera (or upload a photo), or tap Input Key and type the key shown under the QR code.',
                      lostReportId: widget.id,
                      onSuccess: () => _toast(context,
                          'Code verified. Please wait for the office to confirm.'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (qrScanned) ...[
                    const _StatusBanner(
                        text:
                            'Collection confirmed — waiting for Admin handover.'),
                    const SizedBox(height: 10),
                  ],
                  if (r.status == ItemStatus.active && !approved)
                    OutlineBtn(
                      label: 'Request to Close',
                      color: AppTheme.danger,
                      onPressed: () => _requestClose(context),
                    )
                  else if (r.status == ItemStatus.requestedClose)
                    NoticeBox(
                      message:
                          'Closure Requested — an admin will review and approve your request.',
                      borderColor: AppTheme.red,
                      icon: Icons.hourglass_top_rounded,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Student confirmation flow for requesting closure of their own lost
  /// report. The request only moves the report to `Requested Close` — an admin
  /// must still approve it, so this never closes the report directly.
  Future<void> _requestClose(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request to Close Report?'),
        content: const Text(
            'Are you sure you want to request closure of this lost report? '
            'An admin must review and approve your request.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request to Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<AppState>();
    try {
      await appState.requestClose(widget.id);
      if (!mounted) return;
      _toast(context, 'Closure requested');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not request closure. Try again.');
    }
  }

  /// The one-shot "Collected" success dialog, shown when the match first
  /// becomes Completed (the item is physically back with the student).
  /// Builds a "Potential Matches" section showing proposed AI matches
  /// with their scores, reason, and match % badge.
  Widget _buildAiSuggestions(List<LfMatch> matches) {
    final aiMatches = matches
        .where((m) =>
            m.isAiMatch &&
            m.status == MatchStatus.proposed &&
            (m.overallScore ?? 0) >= 50)
        .toList();
    if (aiMatches.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Potential Matches'),
        const SizedBox(height: 8),
        ...aiMatches.map((m) => _buildAiMatchCard(m)),
      ],
    );
  }

  Widget _buildAiMatchCard(LfMatch m) {
    final score = m.overallScore ?? 0;
    final scoreColor = score >= 80
        ? AppTheme.success
        : score >= 50
            ? AppTheme.warning
            : AppTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$score% Match',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scoreColor)),
                  ),
                  const SizedBox(width: 8),
                  const StatusBadge('AI Suggested'),
                  const Spacer(),
                  const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: AppTheme.textMuted),
                ],
              ),
              if (m.reason != null && m.reason!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(m.reason!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4)),
              ],
              const SizedBox(height: 4),
              Text('Visit the Inventory Office (Block A, Level 1) to verify.',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.red.withOpacity(0.7),
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCollectedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collected'),
        content: const Text('Your item has been collected successfully.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class FoundDetailScreen extends StatefulWidget {
  final String id;
  const FoundDetailScreen({super.key, required this.id});
  @override
  State<FoundDetailScreen> createState() => _FoundDetailScreenState();
}

class _FoundDetailScreenState extends State<FoundDetailScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<Item?> _report;

  /// The signed-in student's own handover QR transactions (Workflow 2). The
  /// body filters this to the current report by `foundReportId`.
  late final Stream<List<QrTransaction>> _activeQr;

  @override
  void initState() {
    super.initState();
    // Only the route's document ID is needed; AppState resolves the stream. No
    // Firebase import reaches this file.
    _report = context.read<AppState>().watchReport(widget.id);
    _activeQr = context.read<AppState>().watchMyActiveQr(QrKind.handover);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Item?>(
      stream: _report,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final r = snapshot.data;

        return Scaffold(
          appBar: _gradientAppBar(r?.id ?? widget.id, context),
          body: isLoading && r == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Report',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : r == null
                      ? const EmptyState(
                          title: 'Report Not Found',
                          subtitle: 'This report may have been removed.',
                          icon: Icons.search_off_rounded,
                        )
                      : r.isDeleted
                          ? const EmptyState(
                              title: 'Report Deleted',
                              subtitle: 'This report is no longer available.',
                              icon: Icons.delete_outline_rounded,
                            )
                          : _foundDetailBody(context, r),
        );
      },
    );
  }

  Widget _foundDetailBody(BuildContext context, Item r) {
    // Found reports store their location/date in the shared `whereLost` /
    // `whenLost` fields (see `_ReportFoundState._submit`), so those back the
    // "Where Found" / "When Found" rows here.
    final String whereFound = r.whereLost;
    final String whenFound = r.whenLostLabel;

    return StreamBuilder<List<QrTransaction>>(
      stream: _activeQr,
      builder: (context, qrSnap) {
        final qrs = qrSnap.data ?? const <QrTransaction>[];
        // The student's own handover codes, filtered to this report. Newest
        // first, so the most recent Issued/Scanned code drives the UI.
        final forThisReport =
            qrs.where((t) => t.foundReportId == widget.id).toList();
        final QrTransaction? qr =
            forThisReport.isEmpty ? null : forThisReport.first;

        final bool awaiting = r.status == ItemStatus.active ||
            r.status == ItemStatus.awaitingHandover;
        final bool inInventory = r.status == ItemStatus.inInventory;
        final bool returned = r.status == ItemStatus.returned;
        final bool qrIssued = qr != null && qr.status == QrStatus.issued;
        final bool qrScanned = qr != null && qr.status == QrStatus.scanned;

        // The moment the office issues the QR, steps 1-4 (report, visit,
        // hand over, QR issued) are considered done automatically — only
        // "Handover Complete" still awaits the office confirmation.
        // 6 means every step is complete.
        final int step = inInventory || returned
            ? 6
            : (qrIssued || qrScanned)
                ? 5
                : awaiting
                    ? 2
                    : 1;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(r.description,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800))),
                        StatusBadge(r.foundStudentStatus),
                      ]),
                      const Divider(height: 20),
                      InfoRow(label: 'Category', value: r.category),
                      InfoRow(label: 'Where Found', value: whereFound),
                      InfoRow(label: 'When Found', value: fmtDate(whenFound)),
                    ],
                  ),
                ),
              ),

              // Handover Progress Stepper
              const SizedBox(height: 10),
              _HandoverStepper(currentStep: step),

              // QR Scan section — shown while a handover code is Issued.
              if (qrIssued) ...[
                const SectionLabel('Scan QR Code'),
                _QrScanSection(
                  instruction:
                      'The admin has generated a QR code for item handover. Tap Scan QR to use your camera (or upload a photo of the QR), or tap Input Key and type the key shown under the QR code.',
                  onSuccess: () => _showThankYouDialog(context),
                ),
              ],

              if (qrScanned) ...[
                const SizedBox(height: 10),
                const _StatusBanner(
                  text: 'QR Code verified - awaiting office confirmation',
                ),
              ],

              if (inInventory) ...[
                const SizedBox(height: 10),
                const _StatusBanner(
                  text:
                      'Handover complete - thank you for handing over the found item.',
                ),
              ],

              if (returned) ...[
                const SizedBox(height: 10),
                const _StatusBanner(
                  text: 'This item has been returned to its owner.',
                ),
              ],

              // Awaiting handover with no code issued yet.
              if (awaiting && !qrIssued && !qrScanned) ...[
                const SizedBox(height: 10),
                const NoticeBox(
                  message:
                      'Please hand the item to the Lost & Found Office (Block A, Level 1). The admin will generate a QR code for you to scan as proof of handover.',
                  icon: Icons.info_outline_rounded,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// One-shot "Thank You" dialog shown when the student's Handover QR scan is
  /// verified by the backend. It is only reachable from [_QrScanSection]'s
  /// `onSuccess` (a single scan event), so it cannot re-fire on rebuild or on
  /// app reopen. The scan itself completes the physical handover: the report
  /// moves to `In Inventory` (shown to the student as `Closed`) in the same
  /// atomic transaction that confirms the code, so this dialog only appears
  /// after that backend confirmation succeeds.
  void _showThankYouDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Thank You',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: const Text(
          'Thank you for handing over the item to the Lost & Found Office.',
          style: TextStyle(
              fontSize: 13, color: AppTheme.textSecondary, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (context.mounted) context.pop();
            },
            child: const Text('Close',
                style: TextStyle(
                    color: AppTheme.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Screen 8: Notifications ──────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<CampusNotification>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = context.read<AppState>().watchMyCampusNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CampusNotification>>(
      stream: _notifications,
      builder: (context, snap) {
        final list = snap.data ?? const <CampusNotification>[];
        final isLoading =
            snap.connectionState == ConnectionState.waiting && list.isEmpty;
        final error = snap.error;
        final hasUnread = list.any((n) => !n.read);

        return Scaffold(
          appBar: _gradientAppBar('Notifications', context, actions: [
            if (hasUnread)
              TextButton(
                onPressed: () =>
                    context.read<AppState>().markAllCampusNotificationsRead(),
                child: const Text('Mark all read',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          body: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Notifications',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : list.isEmpty
                      ? const EmptyState(
                          title: 'No Notifications',
                          icon: Icons.notifications_off_rounded)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          itemBuilder: (ctx, i) {
                            final n = list[i];
                            return GestureDetector(
                              onTap: () => _onRowTap(context, n),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: n.read
                                      ? AppTheme.bgCard
                                      : _sourceColor(n.source)
                                          .withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: n.read
                                          ? _sourceColor(n.source)
                                              .withOpacity(0.1)
                                          : _sourceColor(n.source)
                                              .withOpacity(0.25)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  leading: CircleAvatar(
                                      backgroundColor: _sourceColor(n.source)
                                          .withOpacity(0.12),
                                      child: Icon(_sourceIcon(n.source),
                                          color: _sourceColor(n.source),
                                          size: 20)),
                                  title: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(n.title,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: n.read
                                                        ? FontWeight.w500
                                                        : FontWeight.w700,
                                                    color:
                                                        AppTheme.textPrimary)),
                                          ),
                                          if (n.adminWorkItem) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.goldDark
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text('ADMIN',
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          AppTheme.goldDark)),
                                            ),
                                          ],
                                        ],
                                      ),
                                  subtitle: n.body.isEmpty
                                      ? Text(_rowTime(n),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textMuted))
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(n.body,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme
                                                        .textSecondary)),
                                            Text(_rowTime(n),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.textMuted)),
                                          ],
                                        ),
                                  trailing: n.read
                                      ? null
                                      : Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                              color: AppTheme.red,
                                              shape: BoxShape.circle)),
                                ),
                              ),
                            )
                                .animate()
                                .fadeIn(delay: (i * 55).ms)
                                .slideX(begin: 0.1);
                          }),
        );
      },
    );
  }

  Future<void> _onRowTap(BuildContext context, CampusNotification n) async {
    if (!n.read) {
      if (n.adminWorkItem) {
        await context.read<AppState>().markAdminNotificationRead(n.id);
      } else {
        switch (n.source) {
          case NotificationSource.lostFound:
            await context.read<AppState>().markLfNotificationRead(n.id);
          case NotificationSource.locker:
            await context.read<AppState>().markLockerNotificationRead(n.id);
          case NotificationSource.event:
          case NotificationSource.issue:
          case NotificationSource.system:
            break; // not yet implemented
        }
      }
    }
    if (!mounted) return;
    final route = n.relatedScreen.isNotEmpty
        ? n.relatedScreen
        : defaultScreenForSource(n.source, n.relatedEntityId);
    context.push(route);
  }

  static String _rowTime(CampusNotification n) => n.createdAt == null
      ? '—'
      : relativeTime(n.createdAt!.toIso8601String());

  static IconData _sourceIcon(NotificationSource source) {
    switch (source) {
      case NotificationSource.lostFound:
        return Icons.link_rounded;
      case NotificationSource.locker:
        return Icons.lock_rounded;
      case NotificationSource.event:
        return Icons.event_rounded;
      case NotificationSource.issue:
        return Icons.report_problem_rounded;
      case NotificationSource.system:
        return Icons.campaign_rounded;
    }
  }

  static Color _sourceColor(NotificationSource source) {
    switch (source) {
      case NotificationSource.lostFound:
        return AppTheme.red;
      case NotificationSource.locker:
        return AppTheme.goldDark;
      case NotificationSource.event:
        return const Color(0xFF2563EB); // blue
      case NotificationSource.issue:
        return const Color(0xFFD97706); // amber
      case NotificationSource.system:
        return AppTheme.textSecondary;
    }
  }
}

// ── Screen 9: Admin L&F Dashboard ───────────────────────────────
class AdminLFDashboardScreen extends StatefulWidget {
  const AdminLFDashboardScreen({super.key});
  @override
  State<AdminLFDashboardScreen> createState() => _AdminLFDashboardScreenState();
}

class _AdminLFDashboardScreenState extends State<AdminLFDashboardScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore. One combined
  /// feed for lost + found, mirroring the student hub on the admin side: the
  /// dashboard splits the result into lost/found by [Item.isLost] /
  /// [Item.isFound] when it needs the breakdown, rather than running two
  /// queries.
  late final Stream<List<Item>> _reports;
  late final Stream<List<LfMatch>> _matches;
  late final Stream<List<InventoryItem>> _inventory;
  late final Stream<List<UserProfile>> _registrations;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchAdminAllReports();
    _matches = context.read<AppState>().watchAllMatches();
    _inventory = context.read<AppState>().watchAllInventoryItems();
    _registrations = context.read<AppState>().watchStudentRegistrations();
  }

  @override
  Widget build(BuildContext context) {
    return _buildAdminDashboard(context);
  }

  Widget _buildAdminDashboard(BuildContext context) {
    return _AdminDashboardBody(
      reports: _reports,
      matches: _matches,
      inventory: _inventory,
      registrations: _registrations,
    );
  }

  /*
    final appState = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LostFoundIdentityRow(includeTopSafeArea: false),
              const AdminBar(), const SizedBox(height: 10),
              // Lost & Found statistics + Quick Actions come from the live
              // Firestore feed. The dashboard shell (AdminBar, Admin Tools,
              // User Analytics) renders immediately and never blocks on this
              // stream, so an admin can still navigate while the counts load.
              StreamBuilder<List<Item>>(
                stream: _reports,
                builder: (context, snapshot) {
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting &&
                          snapshot.data == null;
                  final error = snapshot.error;
                  final all = snapshot.data ?? const <Item>[];

                  // Soft-deleted reports are already excluded by the service
                  // query, so no screen-side isDeleted check is needed here.
                  // The "View Lost Reports" count is the authoritative open
                  // count — Active + Notified. `Requested Close` remains in
                  // Active, so it is included; Closed / Resolved / Returned /
                  // archived reports are excluded.
                  final lost = all
                      .where((r) =>
                          r.isLost &&
                          r.status != ItemStatus.resolved &&
                          r.status != ItemStatus.returned &&
                          r.status != ItemStatus.closed)
                      .length;
                  // Once a found item is handed over to the Inventory Office
                  // (In Inventory) or claimed by its owner (Returned), it no
                  // longer belongs in the "found report" bucket — it lives in
                  // the Inventory Office / Archive instead.
                  final found = all
                      .where((r) =>
                          r.isFound &&
                          r.status != ItemStatus.inInventory &&
                          r.status != ItemStatus.returned)
                      .length;
                  final activeLost = all
                      .where((r) => r.isLost && r.status == ItemStatus.active)
                      .length;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (error != null)
                        // Permission denied / Firestore error — both arrive as
                        // an AuthFailure with a display-ready message.
                        EmptyState(
                          title: 'Could Not Load Statistics',
                          subtitle: error is AuthFailure
                              ? error.message
                              : 'Something went wrong. Please try again.',
                          icon: Icons.cloud_off_rounded,
                        )
                      else if (isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child:
                                CircularProgressIndicator(color: AppTheme.red),
                          ),
                        )
                      else
                        Row(children: [
                          Expanded(
                              child: StatCard(
                                  value: '$activeLost', label: 'Active Lost')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: StatCard(
                                  value: '$found',
                                  label: 'Found Reports',
                                  valueColor: AppTheme.redDark,
                                  bgColor: AppTheme.red.withOpacity(0.07))),
                        ]).animate().fadeIn(delay: 50.ms),
                      const SectionLabel('Quick Actions'),
                      HubButton(
                              icon: Icons.list_alt_rounded,
                              label: 'View Lost Reports',
                              subtitle: isLoading || error != null
                                  ? 'Loading…'
                                  : '$lost open',
                              onTap: () =>
                                  context.push('/admin/lost-found/lost-list'))
                          .animate()
                          .fadeIn(delay: 100.ms),
                      HubButton(
                              icon: Icons.inventory_rounded,
                              label: 'View found report',
                              subtitle: isLoading || error != null
                                  ? 'Loading…'
                                  : '$found items',
                              isAmber: true,
                              onTap: () =>
                                  context.push('/admin/lost-found/found-list'))
                          .animate()
                          .fadeIn(delay: 150.ms),
                    ],
                  );
                },
              ),
              const SectionLabel('Admin Tools'),
              HubButton(
                      icon: Icons.person_add_rounded,
                      label: 'Student Registrations',
                      subtitle:
                          '${appState.pendingStudentAccounts} pending approval',
                      onTap: () => context.push('/admin/registrations'))
                  .animate()
                  .fadeIn(delay: 250.ms),
              // ── Lost & Found workflow tools ──
              const SectionLabel('Lost & Found Workflow'),
              StreamBuilder<List<InventoryItem>>(
                stream: _inventory,
                builder: (context, invSnap) {
                  final inv = invSnap.data ?? const <InventoryItem>[];
                  final inOffice = inv.where((i) => !i.isReturned).length;
                  return HubButton(
                          icon: Icons.inventory_rounded,
                          label: 'Inventory Office',
                          subtitle: '$inOffice items in office',
                          isAmber: true,
                          onTap: () =>
                              context.push('/admin/lost-found/inventory'))
                      .animate()
                      .fadeIn(delay: 300.ms);
                },
              ),
              StreamBuilder<List<LfMatch>>(
                stream: _matches,
                builder: (context, matchSnap) {
                  final matches = matchSnap.data ?? const <LfMatch>[];
                  final aiPending = matches
                      .where((m) =>
                          m.isAiMatch &&
                          m.status == MatchStatus.proposed &&
                          (m.overallScore ?? 0) >= 50)
                      .length;
                  final approvedCount = matches
                      .where((m) => m.status == MatchStatus.approved)
                      .length;
                  return Column(children: [
                    HubButton(
                        icon: Icons.auto_awesome_rounded,
                        label: 'AI Suggested Matches',
                        subtitle: aiPending > 0
                            ? '$aiPending AI-proposed match${aiPending == 1 ? '' : 'es'}'
                            : 'No AI suggestions',
                        isAmber: aiPending > 0,
                        onTap: () => context.push(
                            '/admin/lost-found/match-list')).animate().fadeIn(
                        delay: 340.ms),
                    const SizedBox(height: 8),
                    HubButton(
                        icon: Icons.check_circle_outline,
                        label: 'Approved Matches',
                        subtitle: approvedCount > 0
                            ? '$approvedCount awaiting collection'
                            : 'None awaiting collection',
                        isAmber: approvedCount > 0,
                        onTap: () => context.push(
                            '/admin/lost-found/approved-matches'))
                        .animate()
                        .fadeIn(delay: 350.ms),
                  ]);
                },
              ),
              // ── User Analytics Section ──
              const SectionLabel('User Analytics'),
              Row(children: [
                Expanded(
                    child: StatCard(
                        value: '${appState.totalAccounts}',
                        label: 'Total Accounts',
                        valueColor: const Color(0xFF1B5E20),
                        bgColor: const Color(0x0A4CAF50))),
                const SizedBox(width: 10),
                Expanded(
                    child: StatCard(
                        value: '${appState.totalStudentAccounts}',
                        label: 'Students',
                        valueColor: const Color(0xFF0D47A1),
                        bgColor: const Color(0x0A2196F3))),
                const SizedBox(width: 10),
                Expanded(
                    child: StatCard(
                        value: '${appState.totalAdminAccounts}',
                        label: 'Admins',
                        valueColor: const Color(0xFF6A1B9A),
                        bgColor: const Color(0x0A9C27B0))),
              ]).animate().fadeIn(delay: 300.ms),
            ],
          ),
        ),
      ),
    );
  }
  */
}

// ── Shared admin section switcher + countdown dialog ──────────────

/// The three-section tab bar used by the admin Lost and Found report lists.
/// Unlike the student switchers, the tabs are always Active / Notified /
/// Closed (no vertical indicator lines, matching the student design).
class _AdminDashboardPalette {
  static const background = Color(0xFFFFFCFB);
  static const ink = Color(0xFF15233B);
  static const muted = Color(0xFF64748B);
  static const hairline = Color(0xFFEFE8EA);
  static const pink = Color(0xFFD71958);
  static const pinkBright = Color(0xFFF65E7B);
  static const pinkTint = Color(0xFFFFE8EF);
  static const green = Color(0xFF159447);
  static const greenTint = Color(0xFFE6F5E9);
  static const gold = Color(0xFFA46808);
  static const goldTint = Color(0xFFFFF2DD);
  static const blue = Color(0xFF2E72D3);
  static const blueTint = Color(0xFFEAF2FF);
  static const purple = Color(0xFF7135B8);
  static const purpleTint = Color(0xFFF3EAFF);
}

class _AdminDashboardBody extends StatelessWidget {
  final Stream<List<Item>> reports;
  final Stream<List<LfMatch>> matches;
  final Stream<List<InventoryItem>> inventory;
  final Stream<List<UserProfile>> registrations;

  const _AdminDashboardBody({
    required this.reports,
    required this.matches,
    required this.inventory,
    required this.registrations,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: _AdminDashboardPalette.background,
      drawer: const _AdminDashboardDrawer(),
      body: SafeArea(
        top: true,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 640 ? 28.0 : 20.0;
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal,
                  104 + MediaQuery.paddingOf(context).bottom),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LostFoundIdentityRow(
                      includeTopSafeArea: false,
                      showMenu: false,
                    ),
                    const SizedBox(height: 12),
                    const _AdminModeBanner(),
                    const SizedBox(height: 18),
                    StreamBuilder<List<Item>>(
                      stream: reports,
                      builder: (context, snapshot) {
                        final ready = snapshot.hasData && !snapshot.hasError;
                        final error = snapshot.error;
                        final all = snapshot.data ?? const <Item>[];
                        final lost = all
                            .where((r) =>
                                r.isLost &&
                                r.status != ItemStatus.resolved &&
                                r.status != ItemStatus.returned &&
                                r.status != ItemStatus.closed)
                            .length;
                        final found = all
                            .where((r) =>
                                r.isFound &&
                                r.status != ItemStatus.resolved &&
                                r.status != ItemStatus.inInventory &&
                                r.status != ItemStatus.returned &&
                                r.status != ItemStatus.closed)
                            .length;
                        // Keep the top metric aligned with the open lost
                        // reports shown by the admin lost-report workflow.
                        final activeLost = lost;
                        final activeLostValue = ready ? '$activeLost' : '—';
                        final foundValue = ready ? '$found' : '—';
                        final reportLoadingText =
                            error != null ? '—' : 'Loading…';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _AdminMetricCard(
                                    icon: Icons.business_center_outlined,
                                    value: activeLostValue,
                                    title: 'Active Lost Items',
                                    subtitle: 'Currently tracked',
                                    accent: _AdminDashboardPalette.pink,
                                    tint: _AdminDashboardPalette.pinkTint,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _AdminMetricCard(
                                    icon: Icons.bookmark_border_rounded,
                                    value: foundValue,
                                    title: 'Found Reports',
                                    subtitle: 'Awaiting review',
                                    accent: _AdminDashboardPalette.green,
                                    tint: _AdminDashboardPalette.greenTint,
                                  ),
                                ),
                              ],
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              _AdminDashboardError(
                                message: error is AuthFailure
                                    ? error.message
                                    : 'Something went wrong. Please try again.',
                              ),
                            ],
                            _AdminDashboardSectionHeader(
                              'Quick Actions',
                              onViewAll: () =>
                                  context.push('/admin/lost-found/lost-list'),
                            ),
                            _AdminActionGroup(
                              rows: [
                                _AdminActionRowData(
                                  icon: Icons.description_outlined,
                                  label: 'View Lost Reports',
                                  subtitle: ready
                                      ? '$lost open reports'
                                      : reportLoadingText,
                                  onTap: () => context
                                      .push('/admin/lost-found/lost-list'),
                                ),
                                _AdminActionRowData(
                                  icon: Icons.find_in_page_outlined,
                                  label: 'View Found Report',
                                  subtitle: ready
                                      ? '$found ${found == 1 ? 'item reported' : 'items reported'}'
                                      : reportLoadingText,
                                  emphasis: true,
                                  onTap: () => context
                                      .push('/admin/lost-found/found-list'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    _AdminDashboardSectionHeader(
                      'Admin Tools',
                      onViewAll: () => context.push('/admin/registrations'),
                    ),
                    StreamBuilder<List<UserProfile>>(
                      stream: registrations,
                      builder: (context, registrationSnapshot) {
                        final ready = registrationSnapshot.hasData &&
                            !registrationSnapshot.hasError;
                        final error = registrationSnapshot.error;
                        final registrationData =
                            registrationSnapshot.data ?? const <UserProfile>[];
                        final pending = registrationData
                            .where((registration) => registration.isPending)
                            .length;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AdminActionGroup(
                              rows: [
                                _AdminActionRowData(
                                  icon: Icons.group_add_outlined,
                                  label: 'Student Registrations',
                                  subtitle: ready
                                      ? '$pending pending approval'
                                      : error != null
                                          ? '—'
                                          : 'Loading…',
                                  onTap: () =>
                                      context.push('/admin/registrations'),
                                ),
                              ],
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              _AdminDashboardError(
                                message: error is AuthFailure
                                    ? error.message
                                    : 'Could not load student registrations.',
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const _AdminDashboardSectionHeader(
                      'Lost & Found Workflow',
                      fontSize: 13,
                      letterSpacing: 1.1,
                    ),
                    StreamBuilder<List<InventoryItem>>(
                      stream: inventory,
                      builder: (context, invSnapshot) {
                        final inventoryReady =
                            invSnapshot.hasData && !invSnapshot.hasError;
                        final inventoryError = invSnapshot.error;
                        final inv = invSnapshot.data ?? const <InventoryItem>[];
                        final inOffice = inv.where((i) => !i.isReturned).length;
                        return StreamBuilder<List<LfMatch>>(
                          stream: matches,
                          builder: (context, matchSnapshot) {
                            final matchesReady = matchSnapshot.hasData &&
                                !matchSnapshot.hasError;
                            final matchError = matchSnapshot.error;
                            final currentMatches =
                                matchSnapshot.data ?? const <LfMatch>[];
                            final aiPending = currentMatches
                                .where((m) =>
                                    m.isAiMatch &&
                                    m.status == MatchStatus.proposed &&
                                    (m.overallScore ?? 0) >= 50)
                                .length;
                            final approvedCount = currentMatches
                                .where((m) => m.status == MatchStatus.approved)
                                .length;
                            final workflowError = inventoryError ?? matchError;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AdminWorkflowCard(
                                  rows: [
                                    _AdminWorkflowRowData(
                                      icon: Icons.account_balance_outlined,
                                      label: 'Inventory Office',
                                      subtitle: inventoryReady
                                          ? '$inOffice items in office'
                                          : inventoryError != null
                                              ? '—'
                                              : 'Loading…',
                                      count: inventoryReady ? '$inOffice' : '—',
                                      color: _AdminDashboardPalette.gold,
                                      tint: _AdminDashboardPalette.goldTint,
                                      onTap: () => context
                                          .push('/admin/lost-found/inventory'),
                                    ),
                                    _AdminWorkflowRowData(
                                      icon: Icons.auto_awesome_rounded,
                                      label: 'AI Suggested Matches',
                                      subtitle: matchesReady
                                          ? aiPending > 0
                                              ? '$aiPending AI-proposed match${aiPending == 1 ? '' : 'es'}'
                                              : 'No AI suggestions'
                                          : matchError != null
                                              ? '—'
                                              : 'Loading…',
                                      count: matchesReady ? '$aiPending' : '—',
                                      color: _AdminDashboardPalette.pink,
                                      tint: _AdminDashboardPalette.pinkTint,
                                      onTap: () => context
                                          .push('/admin/lost-found/match-list'),
                                    ),
                                    _AdminWorkflowRowData(
                                      icon: Icons.check_circle_outline_rounded,
                                      label: 'Approved Matches',
                                      subtitle: matchesReady
                                          ? approvedCount > 0
                                              ? '$approvedCount awaiting collection'
                                              : 'None awaiting collection'
                                          : matchError != null
                                              ? '—'
                                              : 'Loading…',
                                      count:
                                          matchesReady ? '$approvedCount' : '—',
                                      color: _AdminDashboardPalette.green,
                                      tint: _AdminDashboardPalette.greenTint,
                                      onTap: () => context.push(
                                          '/admin/lost-found/approved-matches'),
                                    ),
                                  ],
                                ),
                                if (workflowError != null) ...[
                                  const SizedBox(height: 12),
                                  _AdminDashboardError(
                                    message: workflowError is AuthFailure
                                        ? workflowError.message
                                        : 'Could not load workflow data.',
                                  ),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const _AdminDashboardSectionHeader(
                      'User Analytics',
                      fontSize: 13,
                      letterSpacing: 1.1,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _AdminAnalyticsCard(
                            icon: Icons.people_alt_outlined,
                            value: appState.accountStatsReady
                                ? '${appState.totalAccounts}'
                                : '—',
                            title: 'Total Accounts',
                            subtitle: 'All platform users',
                            accent: _AdminDashboardPalette.blue,
                            tint: _AdminDashboardPalette.blueTint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AdminAnalyticsCard(
                            icon: Icons.school_outlined,
                            value: appState.accountStatsReady
                                ? '${appState.totalStudentAccounts}'
                                : '—',
                            title: 'Students',
                            subtitle: 'Registered students',
                            accent: _AdminDashboardPalette.green,
                            tint: _AdminDashboardPalette.greenTint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AdminAnalyticsCard(
                            icon: Icons.shield_outlined,
                            value: appState.accountStatsReady
                                ? '${appState.totalAdminAccounts}'
                                : '—',
                            title: 'Admins',
                            subtitle: 'System administrators',
                            accent: _AdminDashboardPalette.purple,
                            tint: _AdminDashboardPalette.purpleTint,
                          ),
                        ),
                      ],
                    ),
                    if (appState.accountStatsError != null) ...[
                      const SizedBox(height: 12),
                      _AdminDashboardError(
                        message: appState.accountStatsError is AuthFailure
                            ? (appState.accountStatsError as AuthFailure)
                                .message
                            : 'Could not load account analytics.',
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminModeBanner extends StatelessWidget {
  const _AdminModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _AdminDashboardPalette.goldTint.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFFFC96C).withValues(alpha: .82)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _AdminDashboardPalette.goldTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.shield_outlined,
                color: _AdminDashboardPalette.gold, size: 25),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADMIN MODE',
                  style: TextStyle(
                    color: _AdminDashboardPalette.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'You have full access to manage the platform.',
                  style: TextStyle(
                    color: _AdminDashboardPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: _AdminDashboardPalette.gold, size: 25),
        ],
      ),
    );
  }
}

class _AdminMetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String title;
  final String subtitle;
  final Color accent;
  final Color tint;

  const _AdminMetricCard({
    required this.icon,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: accent.withValues(alpha: .11)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 31,
              height: .98,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AdminDashboardPalette.ink,
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AdminDashboardPalette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardSectionHeader extends StatelessWidget {
  final String label;
  final VoidCallback? onViewAll;
  final double fontSize;
  final double letterSpacing;

  const _AdminDashboardSectionHeader(
    this.label, {
    this.onViewAll,
    this.fontSize = 12,
    this.letterSpacing = 1.15,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: _AdminDashboardPalette.muted,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
              ),
            ),
          ),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        color: _AdminDashboardPalette.pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: _AdminDashboardPalette.pink, size: 13),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminActionRowData {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool emphasis;
  final VoidCallback onTap;

  const _AdminActionRowData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.emphasis = false,
  });
}

class _AdminActionGroup extends StatelessWidget {
  final List<_AdminActionRowData> rows;

  const _AdminActionGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _AdminDashboardPalette.hairline),
        boxShadow: [
          BoxShadow(
            color: _AdminDashboardPalette.ink.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _AdminActionRow(data: rows[i]),
            if (i < rows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _AdminActionRow extends StatelessWidget {
  final _AdminActionRowData data;

  const _AdminActionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final foreground =
        data.emphasis ? Colors.white : _AdminDashboardPalette.ink;
    final secondary = data.emphasis
        ? Colors.white.withValues(alpha: .82)
        : _AdminDashboardPalette.muted;
    final iconColor =
        data.emphasis ? Colors.white : _AdminDashboardPalette.pink;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: data.emphasis ? null : Colors.white,
            gradient: data.emphasis
                ? const LinearGradient(
                    colors: [
                      _AdminDashboardPalette.pinkBright,
                      _AdminDashboardPalette.pink,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: data.emphasis
                      ? Colors.white.withValues(alpha: .18)
                      : _AdminDashboardPalette.pinkTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: data.emphasis
                      ? Colors.white
                      : _AdminDashboardPalette.muted,
                  size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWorkflowRowData {
  final IconData icon;
  final String label;
  final String subtitle;
  final String count;
  final Color color;
  final Color tint;
  final VoidCallback onTap;

  const _AdminWorkflowRowData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.tint,
    required this.onTap,
  });
}

class _AdminWorkflowCard extends StatelessWidget {
  final List<_AdminWorkflowRowData> rows;

  const _AdminWorkflowCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _AdminDashboardPalette.hairline),
        boxShadow: [
          BoxShadow(
            color: _AdminDashboardPalette.ink.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _AdminWorkflowRow(data: rows[i]),
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                indent: 56,
                color: _AdminDashboardPalette.hairline,
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminWorkflowRow extends StatelessWidget {
  final _AdminWorkflowRowData data;

  const _AdminWorkflowRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: data.color, size: 25),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminDashboardPalette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminDashboardPalette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: data.tint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  data.count,
                  style: TextStyle(
                    color: data.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              const Icon(Icons.chevron_right_rounded,
                  color: _AdminDashboardPalette.muted, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminAnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String title;
  final String subtitle;
  final Color accent;
  final Color tint;

  const _AdminAnalyticsCard({
    required this.icon,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 12, 9, 11),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 28,
              height: .95,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AdminDashboardPalette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AdminDashboardPalette.muted,
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardError extends StatelessWidget {
  final String message;

  const _AdminDashboardError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AdminDashboardPalette.pinkTint.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _AdminDashboardPalette.pink.withValues(alpha: .14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: _AdminDashboardPalette.pink, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _AdminDashboardPalette.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardDrawer extends StatelessWidget {
  const _AdminDashboardDrawer();

  @override
  Widget build(BuildContext context) {
    void open(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    return Drawer(
      backgroundColor: _AdminDashboardPalette.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Row(
              children: [
                Icon(Icons.school_rounded,
                    color: _AdminDashboardPalette.pink, size: 27),
                SizedBox(width: 10),
                Text(
                  'Admin tools',
                  style: TextStyle(
                    color: _AdminDashboardPalette.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _AdminDrawerItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              onTap: () => open('/lost-found'),
            ),
            _AdminDrawerItem(
              icon: Icons.description_outlined,
              label: 'Lost Reports',
              onTap: () => open('/admin/lost-found/lost-list'),
            ),
            _AdminDrawerItem(
              icon: Icons.find_in_page_outlined,
              label: 'Found Reports',
              onTap: () => open('/admin/lost-found/found-list'),
            ),
            _AdminDrawerItem(
              icon: Icons.account_balance_outlined,
              label: 'Inventory Office',
              onTap: () => open('/admin/lost-found/inventory'),
            ),
            _AdminDrawerItem(
              icon: Icons.group_add_outlined,
              label: 'Student Registrations',
              onTap: () => open('/admin/registrations'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AdminDrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: _AdminDashboardPalette.pink, size: 22),
        title: Text(
          label,
          style: const TextStyle(
            color: _AdminDashboardPalette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: _AdminDashboardPalette.muted),
      ),
    );
  }
}

class _AdminSectionSwitcher extends StatelessWidget {
  final int activeCount;
  final int notifiedCount;
  final int closedCount;
  final int selected;
  final ValueChanged<int> onChanged;

  const _AdminSectionSwitcher({
    required this.activeCount,
    required this.notifiedCount,
    required this.closedCount,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          _segment('Active', activeCount, 0),
          _segment('Notified', notifiedCount, 1),
          _segment('Closed', closedCount, 2),
        ]),
      ),
    );
  }

  Widget _segment(String label, int count, int index) {
    final isSelected = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-section tab bar (Active / Closed) for the admin found-report list.
/// Found reports have no "Notified" section — a handed-over item stays in
/// Active until it is closed/returned/resolved.
class _AdminFoundSectionSwitcher extends StatelessWidget {
  final int activeCount;
  final int closedCount;
  final int selected;
  final ValueChanged<int> onChanged;

  const _AdminFoundSectionSwitcher({
    required this.activeCount,
    required this.closedCount,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          _segment('Active', activeCount, 0),
          _segment('Closed', closedCount, 1),
        ]),
      ),
    );
  }

  Widget _segment(String label, int count, int index) {
    final isSelected = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A mandatory 3-second confirmation countdown for consequential admin
/// actions (e.g. "Mark as Resolved"). The confirm button stays disabled until
/// the countdown reaches zero, forcing a deliberate pause before the write.
/// Pops `true` once the admin confirms; the caller performs the actual write.
class _ConfirmCountdownDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;

  const _ConfirmCountdownDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  @override
  State<_ConfirmCountdownDialog> createState() =>
      _ConfirmCountdownDialogState();
}

class _ConfirmCountdownDialogState extends State<_ConfirmCountdownDialog> {
  int _remaining = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
      if (_remaining == 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed:
              _remaining == 0 ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            _remaining == 0
                ? widget.confirmLabel
                : '${widget.confirmLabel} ($_remaining)',
          ),
        ),
      ],
    );
  }
}

/// Whether a lost report belongs in the "Notified" section: it has at least
/// one approved match, meaning its owner has been told about the possible
/// match.
bool _lostReportNotified(Item r, List<LfMatch> matches) => matches
    .any((m) => m.lostReportId == r.id && m.status == MatchStatus.approved);

/// Admin-facing status label. `Requested Close` is shown to admins as
/// `Req for Close` (the student sees `Closure Requested` instead).
String _adminStatusLabel(ItemStatus s) =>
    s == ItemStatus.requestedClose ? 'Req for Close' : s.wireValue;

/// Smart title-case for free-text titles: capitalises the first letter of any
/// all-lowercase word and leaves already-mixed-case words (acronyms like "HP",
/// brands like "iPhone") untouched. "Hp laptop" → "Hp Laptop".
String _titleCase(String s) {
  final words = s.trim().split(RegExp(r'\s+'));
  return words.map((w) {
    if (w.isEmpty) return w;
    if (w == w.toLowerCase()) return w[0].toUpperCase() + w.substring(1);
    return w;
  }).join(' ');
}

/// Horizontal strip of a report's photos. Shows nothing when there are none,
/// and renders each `imageUrls` entry with a graceful loading/error fallback
/// (the same pattern as the list thumbnails).
class _PhotoStrip extends StatelessWidget {
  final List<String> urls;
  const _PhotoStrip({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    const double thumb = 112;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Photos',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        if (urls.length == 1)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: thumb,
              height: thumb,
              child: _image(urls.first),
            ),
          )
        else
          SizedBox(
            height: thumb,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: thumb,
                  height: thumb,
                  child: _image(urls[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _image(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _photoPlaceholder(),
        errorBuilder: (context, error, stack) => _photoPlaceholder(),
      );

  Widget _photoPlaceholder() => Container(
        color: const Color(0xFFF0F2F5),
        child: const Icon(Icons.image_rounded,
            color: AppTheme.textMuted, size: 26),
      );
}

/// Student-name row for the admin detail pages. Prefers the immutable
/// `reportedByName`; for legacy reports without it, resolves the name from the
/// reporter's profile on demand. Never falls back to the Student ID.
class _ReporterNameInfoRow extends StatefulWidget {
  final Item report;
  const _ReporterNameInfoRow({required this.report});
  @override
  State<_ReporterNameInfoRow> createState() => _ReporterNameInfoRowState();
}

class _ReporterNameInfoRowState extends State<_ReporterNameInfoRow> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    if (widget.report.reportedByName.isEmpty) _resolve();
  }

  Future<void> _resolve() async {
    final name = await context
        .read<AppState>()
        .fetchReporterName(widget.report.reportedByUid);
    if (!mounted) return;
    setState(() => _resolved = name ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final name =
        r.reportedByName.isNotEmpty ? r.reportedByName : (_resolved ?? '');
    return InfoRow(label: 'Reported by', value: name.isEmpty ? '—' : name);
  }
}

// ── Screen 10: Admin Lost List ───────────────────────────────────
class AdminLostListScreen extends StatefulWidget {
  const AdminLostListScreen({super.key});
  @override
  State<AdminLostListScreen> createState() => _AdminLostListScreenState();
}

class _AdminLostListScreenState extends State<AdminLostListScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;
  late final Stream<List<LfMatch>> _matches;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchAdminLostReports();
    _matches = context.read<AppState>().watchAllMatches();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: _reports,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <Item>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        // The service maps every FirebaseException to an AuthFailure, so this
        // message is already safe to show — permission denied, offline and
        // network failures all arrive here with their own wording.
        final error = snapshot.error;
        return StreamBuilder<List<LfMatch>>(
          stream: _matches,
          builder: (context, matchSnap) {
            final matches = matchSnap.data ?? const <LfMatch>[];
            final active = <Item>[];
            final notified = <Item>[];
            final closed = <Item>[];
            for (final r in data) {
              if (r.status == ItemStatus.resolved ||
                  r.status == ItemStatus.returned ||
                  r.status == ItemStatus.closed) {
                closed.add(r);
              } else if (_lostReportNotified(r, matches)) {
                notified.add(r);
              } else {
                active.add(r);
              }
            }
            final shown = _selected == 0
                ? active
                : _selected == 1
                    ? notified
                    : closed;
            return Scaffold(
              appBar: _gradientAppBar('All Lost Reports', context),
              body: Column(children: [
                const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: AdminBar()),
                _AdminSectionSwitcher(
                  activeCount: active.length,
                  notifiedCount: notified.length,
                  closedCount: closed.length,
                  selected: _selected,
                  onChanged: (i) => setState(() => _selected = i),
                ),
                Expanded(
                    child: isLoading && data.isEmpty
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: AppTheme.red))
                        : error != null
                            ? EmptyState(
                                title: 'Could Not Load Reports',
                                subtitle: error is AuthFailure
                                    ? error.message
                                    : 'Something went wrong. Please try again.',
                                icon: Icons.cloud_off_rounded,
                              )
                            : shown.isEmpty
                                ? EmptyState(
                                    title: _selected == 0
                                        ? 'No Active Lost Reports'
                                        : _selected == 1
                                            ? 'No Notified Lost Reports'
                                            : 'No Closed Lost Reports',
                                    icon: Icons.search_off_rounded)
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: shown.length,
                                    itemBuilder: (ctx, i) {
                                      final r = shown[i];
                                      return CardRow(
                                        // `title` is the report's headline; `reportedByStudentId`
                                        // backs the "S220101 · Category" subtitle the original
                                        // showed via AdminLostReport.studentId.
                                        title: r.title,
                                        subtitle:
                                            '${r.reportedByStudentId} · ${r.category}',
                                        // `whenLostLabel` (YYYY-MM-DD) is the closest
                                        // counterpart to the mock's `createdDate`; fmtDate
                                        // renders it as "20 Mar 2026".
                                        extra: fmtDate(r.whenLostLabel),
                                        status: _adminStatusLabel(r.status),
                                        onTap: () => context.push(
                                            '/admin/lost-found/lost/${r.id}'),
                                      )
                                          .animate()
                                          .fadeIn(delay: (i * 55).ms)
                                          .slideY(begin: 0.12);
                                    })),
              ]),
            );
          },
        );
      },
    );
  }
}

// ── Screen 11: Admin Found List ──────────────────────────────────
class AdminFoundListScreen extends StatefulWidget {
  const AdminFoundListScreen({super.key});
  @override
  State<AdminFoundListScreen> createState() => _AdminFoundListScreenState();
}

class _AdminFoundListScreenState extends State<AdminFoundListScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchAdminFoundReports();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: _reports,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <Item>[];
        final active = <Item>[];
        final closed = <Item>[];
        for (final r in data) {
          if (r.status == ItemStatus.resolved ||
              r.status == ItemStatus.returned ||
              r.status == ItemStatus.closed ||
              r.status == ItemStatus.inInventory) {
            // Closed — resolved, returned, closed, and In Inventory (handover
            // completed). A handed-over item has left the active found queue.
            closed.add(r);
          } else {
            // Active — Awaiting Handover, Active, and Matched - Pending.
            active.add(r);
          }
        }
        final shown = _selected == 0 ? active : closed;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('View Found Reports', context),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
            _AdminFoundSectionSwitcher(
              activeCount: active.length,
              closedCount: closed.length,
              selected: _selected,
              onChanged: (i) => setState(() => _selected = i),
            ),
            Expanded(
                child: isLoading && data.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.red))
                    : error != null
                        ? EmptyState(
                            title: 'Could Not Load Reports',
                            subtitle: error is AuthFailure
                                ? error.message
                                : 'Something went wrong. Please try again.',
                            icon: Icons.cloud_off_rounded,
                          )
                        : shown.isEmpty
                            ? EmptyState(
                                title: _selected == 0
                                    ? 'No Active Found Reports'
                                    : 'No Closed Found Reports',
                                icon: Icons.inventory_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: shown.length,
                                itemBuilder: (ctx, i) {
                                  final r = shown[i];
                                  // Found reports store location/date in the shared
                                  // `whereLost` / `whenLost` fields (see Phase 4's
                                  // `_ReportFoundState._submit`), so those back the
                                  // subtitle and date column the mock filled from
                                  // `whereFound` / `whenFound`.
                                  return CardRow(
                                    title: r.description,
                                    subtitle: '${r.category} · ${r.whereLost}',
                                    extra: fmtDate(r.whenLostLabel),
                                    status: r.status.wireValue,
                                    onTap: () => context.push(
                                        '/admin/lost-found/found/${r.id}'),
                                  ).animate().fadeIn(delay: (i * 55).ms);
                                })),
          ]),
        );
      },
    );
  }
}

// ── Screen 12: Admin Lost Detail ─────────────────────────────────
class AdminLostDetailScreen extends StatefulWidget {
  final String id;
  const AdminLostDetailScreen({super.key, required this.id});
  @override
  State<AdminLostDetailScreen> createState() => _AdminLostDetailScreenState();
}

class _AdminLostDetailScreenState extends State<AdminLostDetailScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore. Same shape
  /// as the student [LostDetailScreen] — only the body differs.
  late final Stream<Item?> _report;

  @override
  void initState() {
    super.initState();
    _report = context.read<AppState>().watchReport(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Item?>(
      stream: _report,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final r = snapshot.data;

        return Scaffold(
          appBar: _gradientAppBar(r?.id ?? widget.id, context),
          body: isLoading && r == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Report',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : r == null
                      ? const EmptyState(
                          title: 'Report Not Found',
                          subtitle: 'This report may have been removed.',
                          icon: Icons.search_off_rounded,
                        )
                      : r.isDeleted
                          ? const EmptyState(
                              title: 'Report Deleted',
                              subtitle: 'This report is no longer available.',
                              icon: Icons.delete_outline_rounded,
                            )
                          : _adminLostDetailBody(context, r),
        );
      },
    );
  }

  Widget _adminLostDetailBody(BuildContext context, Item r) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminBar(), const SizedBox(height: 8),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text(r.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800))),
                      StatusBadge(_adminStatusLabel(r.status))
                    ]),
                    const Divider(height: 18),
                    _ReporterNameInfoRow(report: r),
                    InfoRow(label: 'Student ID', value: r.reportedByStudentId),
                    InfoRow(label: 'Category', value: r.category),
                    InfoRow(label: 'Where Lost', value: r.whereLost),
                    InfoRow(
                        label: 'Submitted', value: fmtDate(r.whenLostLabel)),
                    const Divider(height: 12),
                    const Text('Description',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    Text(r.description,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.65)),
                    const SizedBox(height: 12),
                    _PhotoStrip(urls: r.imageUrls),
                  ]))),
          const SizedBox(height: 10),
          // Closure request approval — the report is in Requested Close.
          if (r.status == ItemStatus.requestedClose)
            GradientButton(
                label: 'Close', onPressed: () => _confirmApproveClose(context)),
          // Mark as Resolved — guarded by a mandatory 3-second countdown.
          if (r.status == ItemStatus.active ||
              r.status == ItemStatus.matchedPending)
            GradientButton(
                label: 'Mark as Resolved',
                onPressed: () => _confirmResolve(context)),
        ],
      ),
    );
  }

  Future<void> _confirmResolve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ConfirmCountdownDialog(
        title: 'Mark as Resolved',
        message:
            'This will mark the report as resolved. This action cannot be undone.',
        confirmLabel: 'Resolve',
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<AppState>();
    try {
      await appState.markAsResolved(widget.id);
      if (!mounted) return;
      _toast(context, 'Report marked as resolved');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not update status. Try again.');
    }
  }

  /// Admin approval of a student's closure request, guarded by the same
  /// 3-second countdown. Moves the report to Closed with
  /// `STUDENT_REQUEST_APPROVED`.
  Future<void> _confirmApproveClose(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ConfirmCountdownDialog(
        title: 'Close Report',
        message:
            'Approve this closure request? The report will be closed and the student notified.',
        confirmLabel: 'Close',
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<AppState>();
    try {
      await appState.approveCloseRequest(widget.id);
      if (!mounted) return;
      _toast(context, 'Closure request approved');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not close report. Try again.');
    }
  }
}

// ── Screen 13: Admin Found Detail ───────────────────────────────
class AdminFoundDetailScreen extends StatefulWidget {
  final String id;
  const AdminFoundDetailScreen({super.key, required this.id});
  @override
  State<AdminFoundDetailScreen> createState() => _AdminFoundDetailScreenState();
}

class _AdminFoundDetailScreenState extends State<AdminFoundDetailScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore. Mirrors the
  /// student [FoundDetailScreen].
  late final Stream<Item?> _report;

  @override
  void initState() {
    super.initState();
    _report = context.read<AppState>().watchReport(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Item?>(
      stream: _report,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final r = snapshot.data;

        return Scaffold(
          appBar: _gradientAppBar('Found Item Details', context),
          body: isLoading && r == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Report',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : r == null
                      ? const EmptyState(
                          title: 'Report Not Found',
                          subtitle: 'This report may have been removed.',
                          icon: Icons.search_off_rounded,
                        )
                      : r.isDeleted
                          ? const EmptyState(
                              title: 'Report Deleted',
                              subtitle: 'This report is no longer available.',
                              icon: Icons.delete_outline_rounded,
                            )
                          : _adminFoundDetailBody(context, r),
        );
      },
    );
  }

  Widget _adminFoundDetailBody(BuildContext context, Item r) {
    // Found reports store their location/date in the shared `whereLost` /
    // `whenLost` fields (see `_ReportFoundState._submit`), so those back the
    // "Where Found" / "When Found" rows here.
    final String whereFound = r.whereLost;
    final String whenFound = r.whenLostLabel;
    // Found reports store the item name in both `title` and `description`
    // (see `_ReportFoundState._submit`), so a Description row is only shown
    // when it carries information beyond the title — never a blank or
    // duplicate row.
    final bool hasDescription = r.description.trim().isNotEmpty &&
        r.description.trim() != r.title.trim();
    // Found reports are born Active (or the legacy Awaiting Handover status);
    // both are open and eligible for the physical handover workflow.
    final bool eligibleForHandover = r.status == ItemStatus.active ||
        r.status == ItemStatus.awaitingHandover;
    // Open reports an admin may resolve. Handover-eligible reports also show
    // this, so the admin can resolve without going through handover.
    final bool openForResolve = r.status == ItemStatus.active ||
        r.status == ItemStatus.awaitingHandover ||
        r.status == ItemStatus.matchedPending;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminBar(),
          const SizedBox(height: 8),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(_titleCase(r.title),
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800))),
                              const SizedBox(width: 8),
                              StatusBadge(_adminStatusLabel(r.status)),
                            ]),
                        const SizedBox(height: 4),
                        Text('Report ID: ${r.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                        const Divider(height: 18),
                        _ReporterNameInfoRow(report: r),
                        InfoRow(
                            label: 'Student ID', value: r.reportedByStudentId),
                        InfoRow(label: 'Category', value: r.category),
                        InfoRow(label: 'Where Found', value: whereFound),
                        InfoRow(label: 'When Found', value: fmtDate(whenFound)),
                        if (hasDescription)
                          InfoRow(label: 'Description', value: r.description),
                        _PhotoStrip(urls: r.imageUrls),
                      ]))),
          const SizedBox(height: 10),
          // Workflow 2 — handover controls while the item awaits handover.
          if (eligibleForHandover) _handoverControls(context, r),
          // Single secondary action: resolve an open report. Closed / resolved
          // / returned / in-inventory reports render read-only below.
          if (openForResolve) ...[
            const SizedBox(height: 10),
            OutlineBtn(
                label: 'Mark as Resolved',
                onPressed: () => _confirmResolve(context)),
          ],
          if (r.status == ItemStatus.inInventory) ...[
            const SizedBox(height: 10),
            const _StatusBanner(
                text:
                    'Handover confirmed — this item is in the Inventory Office.'),
            const SizedBox(height: 10),
            OutlineBtn(
                label: 'View in Inventory',
                onPressed: () => context.push('/admin/lost-found/inventory')),
          ],
          if (r.status == ItemStatus.returned) ...[
            const SizedBox(height: 10),
            const _StatusBanner(
                text: 'This item has been returned to its owner.'),
          ],
          if (r.status == ItemStatus.resolved) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                  'This item has been resolved and claimed.',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green),
                )),
              ]),
            ),
          ],
          if (r.status == ItemStatus.closed) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.archive_rounded, color: Colors.grey, size: 24),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                  'This report has been closed.',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey),
                )),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  /// "Mark as Resolved" guarded by a mandatory 3-second countdown.
  Future<void> _confirmResolve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ConfirmCountdownDialog(
        title: 'Mark as Resolved',
        message:
            'This will mark the report as resolved. This action cannot be undone.',
        confirmLabel: 'Mark as Resolved',
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<AppState>();
    try {
      await appState.markAsResolved(widget.id);
      if (!mounted) return;
      _toast(context, 'Report marked as resolved');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not update status. Try again.');
    }
  }

  /// Cached so rebuilds of the report stream do not re-subscribe.
  Stream<List<QrTransaction>>? _handoverQrStream;

  /// Workflow 2 admin controls: generate the Handover QR, watch its live
  /// Issued → Scanned state, confirm the handover, or cancel an unused code.
  Widget _handoverControls(BuildContext context, Item r) {
    final stream = _handoverQrStream ??=
        context.read<AppState>().watchHandoverQrForReport(r.id);
    return StreamBuilder<List<QrTransaction>>(
      stream: stream,
      builder: (context, snapshot) {
        final qrs = snapshot.data ?? const <QrTransaction>[];
        // The newest code that is still actionable drives the controls.
        QrTransaction? active;
        for (final t in qrs) {
          if (t.status == QrStatus.issued || t.status == QrStatus.scanned) {
            active = t;
            break;
          }
        }
        if (active == null) {
          return Column(children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.qr_code_2_rounded,
                      size: 16, color: AppTheme.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Generate a Handover QR for the finder to scan when they hand over the item at the office. The code expires in 10 minutes and can only be scanned by this finder.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            GradientButton(
                label: 'Generate Handover QR',
                onPressed: () => _generateHandoverQr(context, r)),
          ]);
        }
        final txn = active;
        if (txn.status == QrStatus.issued) {
          return Column(children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8)),
                          child: QrImageView(
                              data: txn.token,
                              version: QrVersions.auto,
                              size: 72,
                              backgroundColor: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Handover QR issued',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                  'For ${txn.intendedStudentId} · expires in ${_qrMinutesLeft(txn)} min',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted)),
                            ])),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.red.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          'Key: ${txn.token}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: GradientButton(
                                label: 'Show Full QR & Key',
                                onPressed: () => _showQRDialog(
                                    context,
                                    'Handover QR',
                                    txn.token,
                                    'Ask ${txn.intendedStudentId} to scan this code in the app, or give them the key to enter under "Input Key". It expires in 10 minutes.'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: OutlineBtn(
                                label: 'Cancel Code',
                                color: AppTheme.danger,
                                onPressed: () => _cancelQr(context, txn.id))),
                      ]),
                    ]))),
            const SizedBox(height: 10),
            const NoticeBox(
                message:
                    'Waiting for the finder to scan this code. After they scan, confirm the physical handover below.',
                icon: Icons.hourglass_top_rounded),
          ]);
        }
        // Scanned — ready to confirm.
        return Column(children: [
          const _StatusBanner(
              text:
                  'The finder scanned the code. Verify the physical item, then confirm the handover.'),
          const SizedBox(height: 10),
          GradientButton(
              label: 'Confirm Handover',
              onPressed: () => _confirmHandover(context, txn.id)),
        ]);
      },
    );
  }

  static String _qrMinutesLeft(QrTransaction txn) {
    final expires = txn.expiresAt;
    if (expires == null) return '0';
    final left = expires.difference(DateTime.now()).inMinutes;
    return left <= 0 ? '0' : '$left';
  }

  Future<void> _generateHandoverQr(BuildContext context, Item r) async {
    final appState = context.read<AppState>();
    try {
      final txn = await appState.issueHandoverQr(r);
      if (!mounted) return;
      _showQRDialog(
        context,
        'Handover QR',
        txn.token,
        'Show this code to ${r.reportedByStudentId}. They scan it in the app to confirm handover. The code expires in 10 minutes.',
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not generate the QR code. Try again.');
    }
  }

  Future<void> _confirmHandover(BuildContext context, String txnId) async {
    final appState = context.read<AppState>();
    try {
      await appState.confirmHandover(txnId);
      if (!mounted) return;
      _toast(context,
          'Handover confirmed — the item is now in the Inventory Office.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not confirm handover. Try again.');
    }
  }

  Future<void> _cancelQr(BuildContext context, String txnId) async {
    final appState = context.read<AppState>();
    try {
      await appState.cancelQrCode(txnId);
      if (!mounted) return;
      _toast(context, 'QR code cancelled.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not cancel the code. Try again.');
    }
  }
}

Future<void> _showQRDialog(
    BuildContext context, String title, String code, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // The QR image encodes only the opaque token — no personal data,
          // no write authority. Scanning it alone never changes a status.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            // The fixed SizedBox matters: QrImageView builds with an internal
            // LayoutBuilder, and AlertDialog measures its content through an
            // intrinsic-width pass that LayoutBuilder cannot answer. A tight
            // box returns its size without querying the child, so the dialog
            // can lay out.
            child: SizedBox(
              width: 190,
              height: 190,
              child: QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 190,
                backgroundColor: Colors.white,
                errorStateBuilder: (context, error) => Container(
                  width: 190,
                  height: 190,
                  alignment: Alignment.center,
                  color: Colors.white,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'QR preview unavailable — use the key below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('KEY',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.red.withOpacity(0.25)),
                ),
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: AppTheme.textPrimary),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Copy key',
              icon: const Icon(Icons.copy_rounded, color: AppTheme.red),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) _toast(ctx, 'Key copied');
              },
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'If the QR does not work, give the student this key — they enter it under "Input Key" in the app.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, height: 1.55),
              textAlign: TextAlign.center),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close',
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: AppTheme.red)),
        ),
      ],
    ),
  );
}

// ── Screen 14: Admin Inventory ────────────────────────────────────
class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});
  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<InventoryItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = context.read<AppState>().watchAllInventoryItems();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InventoryItem>>(
      stream: _items,
      builder: (context, snapshot) {
        // Only items currently sitting in the office (In Inventory) belong
        // here. Items claimed by their owner (Returned) move to the Archive.
        final data = (snapshot.data ?? const <InventoryItem>[])
            .where((item) => !item.isReturned)
            .toList();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('Inventory Office', context),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppTheme.red,
            foregroundColor: Colors.white,
            onPressed: () =>
                context.push('/admin/lost-found/inventory/archive'),
            child: const Icon(Icons.archive_rounded),
          ),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
            Expanded(
                child: isLoading && data.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.red))
                    : error != null
                        ? EmptyState(
                            title: 'Could Not Load Inventory',
                            subtitle: error is AuthFailure
                                ? error.message
                                : 'Something went wrong. Please try again.',
                            icon: Icons.cloud_off_rounded,
                          )
                        : data.isEmpty
                            ? const EmptyState(
                                title: 'No Inventory Items',
                                subtitle:
                                    'Items handed over at the office appear here.',
                                icon: Icons.inventory_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: data.length,
                                itemBuilder: (ctx, i) {
                                  final item = data[i];
                                  return CardRow(
                                    title: item.title,
                                    subtitle:
                                        '${item.category} · Finder ${item.finderStudentId}',
                                    extra: item.handedOverAt == null
                                        ? null
                                        : 'Handed over ${fmtDate(item.handedOverAt!.toIso8601String())}',
                                    status: item.status.wireValue,
                                    onTap: () => context.push(
                                        '/admin/lost-found/inventory/${item.id}'),
                                  ).animate().fadeIn(delay: (i * 55).ms);
                                })),
          ]),
        );
      },
    );
  }
}

// ── Screen 15: Admin Inventory Archive ────────────────────────────
class AdminInventoryArchiveScreen extends StatefulWidget {
  const AdminInventoryArchiveScreen({super.key});
  @override
  State<AdminInventoryArchiveScreen> createState() =>
      _AdminInventoryArchiveScreenState();
}

class _AdminInventoryArchiveScreenState
    extends State<AdminInventoryArchiveScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<InventoryItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = context.read<AppState>().watchAllInventoryItems();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InventoryItem>>(
      stream: _items,
      builder: (context, snapshot) {
        // The archive holds only items that have been claimed by their owner
        // (Returned). Everything still in the office stays on the Inventory
        // Office screen.
        final data = (snapshot.data ?? const <InventoryItem>[])
            .where((item) => item.isReturned)
            .toList();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('Archive', context),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
            Expanded(
                child: isLoading && data.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.red))
                    : error != null
                        ? EmptyState(
                            title: 'Could Not Load Archive',
                            subtitle: error is AuthFailure
                                ? error.message
                                : 'Something went wrong. Please try again.',
                            icon: Icons.cloud_off_rounded,
                          )
                        : data.isEmpty
                            ? const EmptyState(
                                title: 'No Archived Items',
                                subtitle:
                                    'Items claimed by their owner appear here.',
                                icon: Icons.archive_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: data.length,
                                itemBuilder: (ctx, i) {
                                  final item = data[i];
                                  return CardRow(
                                    title: item.title,
                                    subtitle:
                                        '${item.category} · Finder ${item.finderStudentId}',
                                    extra: item.returnedAt == null
                                        ? null
                                        : 'Returned ${fmtDate(item.returnedAt!.toIso8601String())}',
                                    status: item.status.wireValue,
                                    onTap: () => context.push(
                                        '/admin/lost-found/inventory/${item.id}'),
                                  ).animate().fadeIn(delay: (i * 55).ms);
                                })),
          ]),
        );
      },
    );
  }
}

// ── Screen 16: Admin Inventory Detail ─────────────────────────────
class AdminInventoryDetailScreen extends StatefulWidget {
  final String id;
  const AdminInventoryDetailScreen({super.key, required this.id});
  @override
  State<AdminInventoryDetailScreen> createState() =>
      _AdminInventoryDetailScreenState();
}

class _AdminInventoryDetailScreenState
    extends State<AdminInventoryDetailScreen> {
  late final Stream<InventoryItem?> _item;
  late final Stream<List<LfMatch>> _matches;
  late final Stream<List<Item>> _reports;

  @override
  void initState() {
    super.initState();
    _item = context.read<AppState>().watchInventoryItem(widget.id);
    _matches = context.read<AppState>().watchAllMatches();
    _reports = context.read<AppState>().watchAdminAllReports();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<InventoryItem?>(
      stream: _item,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final item = snapshot.data;
        return Scaffold(
          appBar: _gradientAppBar('Inventory Item', context),
          body: isLoading && item == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Item',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : item == null
                      ? const EmptyState(
                          title: 'Item Not Found',
                          icon: Icons.search_off_rounded)
                      : StreamBuilder<List<Item>>(
                          stream: _reports,
                          builder: (context, reportsSnap) {
                            final reports = reportsSnap.data ?? const <Item>[];
                            final reportMap = <String, Item>{
                              for (final r in reports) r.id: r
                            };
                            return _inventoryDetailBody(
                                context, item, reportMap);
                          },
                        ),
        );
      },
    );
  }

  Widget _inventoryDetailBody(
      BuildContext context, InventoryItem item, Map<String, Item> reportMap) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminBar(),
          const SizedBox(height: 8),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    // Photo gallery — at the top of the card.
                    _InventoryPhotoGallery(urls: item.imageUrls),
                    const SizedBox(height: 12),
                    // Title row with badge.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Item Title',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted)),
                        StatusBadge(item.status.wireValue),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const Divider(height: 18),
                    InfoRow(label: 'Category', value: item.category),
                    InfoRow(label: 'Finder ID', value: item.finderStudentId),
                    InfoRow(
                        label: 'Handed Over',
                        value: item.handedOverAt == null
                            ? '—'
                            : fmtDate(item.handedOverAt!.toIso8601String())),
                    if (item.matchedLostReportId != null)
                      InfoRow(
                          label: 'Matched Lost Report',
                          value: item.matchedLostReportId!),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Description',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted)),
                      const SizedBox(height: 6),
                      Text(item.description,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.55)),
                    ],
                  ]))),
          // Match actions — driven by existing matches for this item.
          StreamBuilder<List<LfMatch>>(
            stream: _matches,
            builder: (context, snap) {
              final all = snap.data ?? const <LfMatch>[];
              final mine =
                  all.where((m) => m.inventoryItemId == item.id).toList();
              final hasActive = mine.any((m) =>
                  m.status == MatchStatus.proposed ||
                  m.status == MatchStatus.approved);
              // Item is returned — nothing to show.
              if (item.isReturned) return const SizedBox.shrink();
              return Column(children: [
                // Show Create Match only when no active match exists.
                if (!hasActive) _createMatchSection(context, item),
                // Show match history when any matches exist.
                if (mine.isNotEmpty) ...[
                  const SectionLabel('Matches'),
                  ...mine.map((m) => _matchCard(context, m,
                      lostTitle: reportMap[m.lostReportId]?.title)),
                ],
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _createMatchSection(BuildContext context, InventoryItem item) {
    return Column(children: [
      const NoticeBox(
        message:
            'If this item matches a lost report, create a match. Approving it notifies the lost report owner.',
        icon: Icons.compare_arrows_rounded,
      ),
      GradientButton(
          label: 'Create Match',
          onPressed: () => _pickLostReport(context, item)),
    ]);
  }

  Future<void> _pickLostReport(BuildContext context, InventoryItem item) async {
    final lost = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => const _LostReportPickerSheet(),
    );
    if (lost == null || !mounted) return;
    final appState = context.read<AppState>();
    try {
      await appState.createMatch(LfMatch(
        lostReportId: lost.id,
        inventoryItemId: item.id,
        lostOwnerUid: lost.reportedByUid,
        lostOwnerStudentId: lost.reportedByStudentId,
        status: MatchStatus.proposed,
        notes: '${item.title} ↔ ${lost.title}',
      ));
      if (!mounted) return;
      _toast(context, 'Match created. Approve it to notify the student.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not create the match. Try again.');
    }
  }
}

// ── Screen 16: Match Review ───────────────────────────────────────
class AdminMatchListScreen extends StatefulWidget {
  const AdminMatchListScreen({super.key});
  @override
  State<AdminMatchListScreen> createState() => _AdminMatchListScreenState();
}

class _AdminMatchListScreenState extends State<AdminMatchListScreen> {
  late final Stream<List<LfMatch>> _aiMatches;
  late final Stream<List<Item>> _reports;
  late final Stream<List<InventoryItem>> _inventory;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _aiMatches = appState.watchAiProposedMatches();
    _reports = appState.watchAdminAllReports();
    _inventory = appState.watchAllInventoryItems();
  }

  // ── Build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _gradientAppBar('Review Matches', context),
      body: StreamBuilder<List<Item>>(
        stream: _reports,
        builder: (ctx, reportsSnap) {
          final reports = reportsSnap.data ?? const <Item>[];
          final reportMap = <String, Item>{for (final r in reports) r.id: r};

          return StreamBuilder<List<InventoryItem>>(
            stream: _inventory,
            builder: (ctx, invSnap) {
              final inventory = invSnap.data ?? const <InventoryItem>[];
              final invMap = <String, InventoryItem>{
                for (final i in inventory) i.id: i
              };

              return Column(children: [
                const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: AdminBar()),
                // ── AI Suggested Matches ──────────────────────────
                Expanded(
                  child: _AiSection(
                    stream: _aiMatches,
                    reportMap: reportMap,
                    invMap: invMap,
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}

// ── AI Suggested Matches section (inline) ────────────────────────────

class _AiSection extends StatelessWidget {
  final Stream<List<LfMatch>> stream;
  final Map<String, Item> reportMap;
  final Map<String, InventoryItem> invMap;

  const _AiSection({
    required this.stream,
    required this.reportMap,
    required this.invMap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LfMatch>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[AI MATCH] _AiSection stream error: ${snap.error}');
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could not load AI matches.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ]),
          );
        }
        final data = (snap.data ?? const <LfMatch>[])
            .where((m) =>
                m.isAiMatch &&
                m.status == MatchStatus.proposed &&
                (m.overallScore ?? 0) >= 50)
            .toList();
        if (data.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No AI matches yet',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          itemCount: data.length + 1, // +1 for divider
          itemBuilder: (ctx, i) {
            if (i == 0) return const Divider(indent: 16, endIndent: 16);
            final m = data[i - 1];
            return _MatchRow(
              match: m,
              lostTitle: reportMap[m.lostReportId]?.title ?? 'Lost Report',
              foundTitle: invMap[m.inventoryItemId]?.title ?? 'Inventory Item',
              category: reportMap[m.lostReportId]?.category,
              location: reportMap[m.lostReportId]?.whereLost,
              ownerLabel: _ownerLabel(reportMap[m.lostReportId]?.reportedByName,
                  m.lostOwnerStudentId),
            );
          },
        );
      },
    );
  }
}

// ── Screen: Approved Matches (admin-only) ──────────────────────────

class ApprovedMatchesScreen extends StatefulWidget {
  const ApprovedMatchesScreen({super.key});
  @override
  State<ApprovedMatchesScreen> createState() => _ApprovedMatchesScreenState();
}

class _ApprovedMatchesScreenState extends State<ApprovedMatchesScreen> {
  late final Stream<List<LfMatch>> _matches;
  late final Stream<List<Item>> _reports;
  late final Stream<List<InventoryItem>> _inventory;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _matches = appState.watchApprovedMatches();
    _reports = appState.watchAdminAllReports();
    _inventory = appState.watchAllInventoryItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _gradientAppBar('Approved Matches', context),
      body: StreamBuilder<List<Item>>(
        stream: _reports,
        builder: (ctx, reportsSnap) {
          final reports = reportsSnap.data ?? const <Item>[];
          final reportMap = <String, Item>{for (final r in reports) r.id: r};

          return StreamBuilder<List<InventoryItem>>(
            stream: _inventory,
            builder: (ctx, invSnap) {
              final inventory = invSnap.data ?? const <InventoryItem>[];
              final invMap = <String, InventoryItem>{
                for (final i in inventory) i.id: i
              };

              return StreamBuilder<List<LfMatch>>(
                stream: _matches,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.check_circle_outline,
                            size: 18, color: AppTheme.textSecondary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Could not load approved matches.',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 13)),
                        ),
                      ]),
                    );
                  }
                  final data = snap.data ?? const <LfMatch>[];
                  if (data.isEmpty) {
                    return const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.check_circle_outline,
                            size: 18, color: AppTheme.textSecondary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('No approved matches yet.',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 13)),
                        ),
                      ]),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                    itemCount: data.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0)
                        return const Divider(indent: 16, endIndent: 16);
                      final m = data[i - 1];
                      return _MatchRow(
                        match: m,
                        lostTitle:
                            reportMap[m.lostReportId]?.title ?? 'Lost Report',
                        foundTitle: invMap[m.inventoryItemId]?.title ??
                            'Inventory Item',
                        category: reportMap[m.lostReportId]?.category,
                        location: reportMap[m.lostReportId]?.whereLost,
                        ownerLabel: _ownerLabel(
                            reportMap[m.lostReportId]?.reportedByName,
                            m.lostOwnerStudentId),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ── Single match row card ────────────────────────────────────────────

class _MatchRow extends StatelessWidget {
  final LfMatch match;
  final String lostTitle;
  final String foundTitle;
  final String? category;
  final String? location;
  final String ownerLabel;

  const _MatchRow({
    required this.match,
    required this.lostTitle,
    required this.foundTitle,
    this.category,
    this.location,
    required this.ownerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isAi = match.isAiMatch;
    final score = match.overallScore ?? 0;
    final scoreColor = score >= 80
        ? AppTheme.success
        : score >= 50
            ? AppTheme.warning
            : AppTheme.textMuted;

    // Build the category · location subtitle line.
    final detailParts = <String>[];
    if (category != null && category!.isNotEmpty) detailParts.add(category!);
    if (location != null && location!.isNotEmpty) detailParts.add(location!);
    final detailLine = detailParts.join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: InkWell(
        onTap: () => context.push('/admin/lost-found/match/${match.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent bar — stretches to the full row height.
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: isAi
                        ? const LinearGradient(colors: [
                            AppTheme.gold,
                            AppTheme.goldDark,
                          ])
                        : AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                // Main content.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1 — lost item title (bold).
                      Text(lostTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 3),
                      // Row 2 — category · location (muted).
                      if (detailLine.isNotEmpty)
                        Text(detailLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                      // Row 3 — owner.
                      Text('Owner: $ownerLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(height: 2),
                      // Row 4 — matched found item.
                      Text('↔ $foundTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Right side — score + status.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isAi)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: scoreColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$score%',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scoreColor)),
                      ),
                    const SizedBox(height: 5),
                    StatusBadge(match.status.wireValue),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns [name] if non-empty, otherwise falls back to [studentId].
String _ownerLabel(String? name, String studentId) {
  if (name != null && name.isNotEmpty) return name;
  return studentId;
}

class AdminMatchDetailScreen extends StatefulWidget {
  final String id;
  const AdminMatchDetailScreen({super.key, required this.id});
  @override
  State<AdminMatchDetailScreen> createState() => _AdminMatchDetailScreenState();
}

class _AdminMatchDetailScreenState extends State<AdminMatchDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return StreamBuilder<LfMatch?>(
      stream: appState.watchMatch(widget.id),
      builder: (context, matchSnap) {
        final isLoading = matchSnap.connectionState == ConnectionState.waiting;
        final error = matchSnap.error;
        final m = matchSnap.data;

        Widget body;
        if (isLoading && m == null) {
          body = const Center(
              child: CircularProgressIndicator(color: AppTheme.red));
        } else if (error != null) {
          body = EmptyState(
            title: 'Could Not Load Match',
            subtitle: error is AuthFailure
                ? error.message
                : 'Something went wrong. Please try again.',
            icon: Icons.cloud_off_rounded,
          );
        } else if (m == null) {
          body = const EmptyState(
              title: 'Match Not Found', icon: Icons.search_off_rounded);
        } else {
          body = StreamBuilder<Item?>(
            stream: appState.watchReport(m.lostReportId),
            builder: (context, reportSnap) {
              return StreamBuilder<InventoryItem?>(
                stream: appState.watchInventoryItem(m.inventoryItemId),
                builder: (context, invSnap) {
                  return _matchDetailBody(
                    context,
                    m,
                    report: reportSnap.data,
                    inventory: invSnap.data,
                  );
                },
              );
            },
          );
        }

        return Scaffold(
          appBar: _gradientAppBar('Match Review', context),
          body: body,
        );
      },
    );
  }

  // ── Card hierarchy ────────────────────────────────────────────────

  Widget _matchDetailBody(
    BuildContext context,
    LfMatch m, {
    required Item? report,
    required InventoryItem? inventory,
  }) {
    final isAi = m.isAiMatch;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminBar(),
          const SizedBox(height: 8),
          _buildMatchOverview(context, m, report, inventory),
          const SizedBox(height: 10),
          _buildLostItemCard(report, m),
          const SizedBox(height: 10),
          _buildFoundItemCard(inventory),
          if (isAi) ...[
            const SizedBox(height: 10),
            _buildMatchAnalysisCard(m),
          ],
          if (isAi &&
              ((m.reason != null && m.reason!.isNotEmpty) ||
                  (m.evidence != null &&
                      (m.evidence!.matchingFeatures.isNotEmpty ||
                          m.evidence!.conflictingFeatures.isNotEmpty)))) ...[
            const SizedBox(height: 10),
            _buildWhyThisMatchCard(m),
          ],
          const SizedBox(height: 10),
          _MatchActions(match: m),
        ],
      ),
    );
  }

  // ── 1. Match Overview ─────────────────────────────────────────────

  Widget _buildMatchOverview(
    BuildContext context,
    LfMatch m,
    Item? report,
    InventoryItem? inventory,
  ) {
    final isAi = m.isAiMatch;
    final lostTitle = report?.title ?? 'Item information unavailable';
    final foundTitle = inventory?.title ?? 'Item information unavailable';
    final score = m.overallScore ?? 0;
    final scoreColor = score >= 80
        ? AppTheme.success
        : score >= 50
            ? AppTheme.warning
            : AppTheme.textMuted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — resolved titles + status badge.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lostTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.swap_horiz_rounded,
                            size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(foundTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary)),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isAi)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scoreColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$score%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scoreColor)),
                      ),
                    const SizedBox(height: 5),
                    StatusBadge(m.status.wireValue),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            // Meta rows.
            if (isAi)
              InfoRow(
                  label: 'Source',
                  value:
                      'AI Suggested · ${m.confidence != null ? "${m.confidence}% confidence" : "automated"}'),
            if (!isAi) const InfoRow(label: 'Source', value: 'Manual'),
            if (m.createdAt != null)
              InfoRow(label: 'Matched', value: _dateLabel(m.createdAt!)),
            if (report != null && report.whenLost != null)
              InfoRow(label: 'Date Lost', value: report.whenLostLabel),
            if (inventory != null && inventory.handedOverAt != null)
              InfoRow(
                  label: 'Handed Over',
                  value: _dateLabel(inventory.handedOverAt!)),
            if (m.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppTheme.creamLight,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(m.notes,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.55)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 2. Lost Item ──────────────────────────────────────────────────

  Widget _buildLostItemCard(Item? report, LfMatch m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.search_rounded,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              const Text('Lost Item',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 18),
            if (report == null)
              const _UnavailableNotice()
            else ...[
              _maybeInfoRow('Title', report.title),
              _maybeInfoRow('Category', report.category),
              if (report.whereLost.isNotEmpty)
                _maybeInfoRow('Location', report.whereLost),
              InfoRow(
                  label: 'Owner',
                  value:
                      _ownerLabel(report.reportedByName, m.lostOwnerStudentId)),
              if (report.whenLost != null)
                InfoRow(label: 'Date Lost', value: report.whenLostLabel),
              const SizedBox(height: 8),
              if (report.imageUrls.isNotEmpty)
                _PhotoStrip(urls: report.imageUrls)
              else
                const _NoImageNotice(),
            ],
          ],
        ),
      ),
    );
  }

  // ── 3. Found Item ─────────────────────────────────────────────────

  Widget _buildFoundItemCard(InventoryItem? inventory) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.inventory_2_rounded,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              const Text('Found Item',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 18),
            if (inventory == null)
              const _UnavailableNotice()
            else ...[
              _maybeInfoRow('Title', inventory.title),
              _maybeInfoRow('Category', inventory.category),
              if (inventory.finderStudentId.isNotEmpty)
                InfoRow(
                    label: 'Handed Over By', value: inventory.finderStudentId),
              if (inventory.handedOverAt != null)
                InfoRow(
                    label: 'Date Handed Over',
                    value: _dateLabel(inventory.handedOverAt!)),
              const SizedBox(height: 8),
              if (inventory.imageUrls.isNotEmpty)
                _PhotoStrip(urls: inventory.imageUrls)
              else
                const _NoImageNotice(),
            ],
          ],
        ),
      ),
    );
  }

  // ── 4. Match Analysis (AI only) ───────────────────────────────────

  Widget _buildMatchAnalysisCard(LfMatch m) {
    final score = m.overallScore ?? 0;
    final scoreColor = score >= 80
        ? AppTheme.success
        : score >= 50
            ? AppTheme.warning
            : AppTheme.textMuted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.insights_rounded,
                  size: 18, color: AppTheme.goldDark),
              const SizedBox(width: 8),
              const Text('Match Analysis',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 18),
            // Overall score row.
            Row(children: [
              const Text('Overall Score',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$score%',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scoreColor)),
              ),
            ]),
            const SizedBox(height: 12),
            // Per-factor breakdown.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (m.titleScore != null) _miniChip('Title', m.titleScore!),
                if (m.descriptionScore != null)
                  _miniChip('Description', m.descriptionScore!),
                if (m.visualScore != null) _miniChip('Visual', m.visualScore!),
                if (m.categoryScore != null)
                  _miniChip('Category', m.categoryScore!),
                if (m.locationScore != null)
                  _miniChip('Location', m.locationScore!),
                if (m.timeScore != null) _miniChip('Time', m.timeScore!),
                if (m.confidence != null)
                  _miniChip('Confidence', m.confidence!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 5. Why This Match (AI only) ───────────────────────────────────

  Widget _buildWhyThisMatchCard(LfMatch m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.psychology_outlined,
                  size: 18, color: AppTheme.goldDark),
              const SizedBox(width: 8),
              const Text('Why This Match',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 18),
            if (m.reason != null && m.reason!.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m.reason!,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                            height: 1.5)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (m.evidence != null) ...[
              if (m.evidence!.matchingFeatures.isNotEmpty) ...[
                const Text('Matching Features',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                ...m.evidence!.matchingFeatures.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 14, color: AppTheme.success),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(f,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary))),
                      ]),
                    )),
              ],
              if (m.evidence!.conflictingFeatures.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Conflicting Features',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                ...m.evidence!.conflictingFeatures.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: AppTheme.warning),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(f,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary))),
                      ]),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static InfoRow _maybeInfoRow(String label, String value) {
    if (value.isEmpty) return const InfoRow(label: '', value: '');
    return InfoRow(label: label, value: value);
  }

  static String _dateLabel(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d  $h:$min';
  }
}

// ── Unavailable / No-image fallbacks ────────────────────────────────

class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.creamLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textMuted),
          SizedBox(width: 8),
          Text('Item information unavailable',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

class _NoImageNotice extends StatelessWidget {
  const _NoImageNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text('No image available',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ),
    );
  }
}

// ── Inventory photo gallery ───────────────────────────────────────

/// Photo gallery for the Admin Inventory Item detail screen. Shows larger
/// tappable thumbnails that open a full-screen viewer with pinch-to-zoom.
/// Falls back to [_NoImageNotice] when there are no photos.
class _InventoryPhotoGallery extends StatelessWidget {
  final List<String> urls;
  const _InventoryPhotoGallery({required this.urls});

  static const double _photoHeight = 180;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const _NoImageNotice();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Photos',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        SizedBox(
          height: _photoHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _showViewer(context, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: _photoWidth(context),
                  height: _photoHeight,
                  child: _image(urls[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _photoWidth(BuildContext context) {
    final screen = MediaQuery.of(context).size.width;
    // Card has 16px padding on each side, plus 16px screen padding.
    final available = screen - 64;
    return available < 240 ? available : 240;
  }

  Widget _image(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
        errorBuilder: (context, error, stack) => _placeholder(),
      );

  Widget _placeholder() => Container(
        color: const Color(0xFFF0F2F5),
        child: const Center(
          child: Icon(Icons.image_rounded, color: AppTheme.textMuted, size: 32),
        ),
      );

  void _showViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoViewerDialog(
        urls: urls,
        initialIndex: initialIndex,
      ),
      fullscreenDialog: true,
    ));
  }
}

/// Full-screen photo viewer with pinch-to-zoom and swipe navigation.
class _PhotoViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _PhotoViewerDialog({required this.urls, required this.initialIndex});

  @override
  State<_PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<_PhotoViewerDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.urls.length}',
            style: const TextStyle(fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
              errorBuilder: (context, error, stack) => const Center(
                child: Icon(Icons.broken_image_rounded,
                    color: Colors.white38, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card wrapping one match plus its admin actions, shared by the inventory
/// detail and match detail screens.
Widget _matchCard(BuildContext context, LfMatch m, {String? lostTitle}) {
  final isAi = m.isAiMatch;
  final score = m.overallScore ?? 0;
  final scoreColor = isAi
      ? (score >= 80
          ? AppTheme.success
          : score >= 50
              ? AppTheme.warning
              : AppTheme.textMuted)
      : AppTheme.textMuted;

  final displayTitle =
      (lostTitle != null && lostTitle.isNotEmpty) ? lostTitle : 'Lost Report';

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Lost Item',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted)),
                  const SizedBox(height: 2),
                  Text(displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ])),
            if (isAi) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$score%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scoreColor)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
            ],
            StatusBadge(m.status.wireValue),
          ]),
          if (isAi && m.reason != null && m.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.psychology_outlined,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(m.reason!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontStyle: FontStyle.italic,
                          height: 1.4))),
            ]),
          ],
          if (isAi) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (m.visualScore != null) _miniChip('Visual', m.visualScore!),
                if (m.titleScore != null) _miniChip('Title', m.titleScore!),
                if (m.descriptionScore != null)
                  _miniChip('Desc', m.descriptionScore!),
                if (m.categoryScore != null)
                  _miniChip('Category', m.categoryScore!),
                if (m.locationScore != null)
                  _miniChip('Location', m.locationScore!),
                if (m.timeScore != null) _miniChip('Time', m.timeScore!),
                if (m.confidence != null)
                  _miniChip('Confidence', m.confidence!),
              ],
            ),
          ],
          if (!isAi) ...[
            const SizedBox(height: 6),
            InfoRow(label: 'Owner', value: m.lostOwnerStudentId),
          ],
          if (m.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(m.notes,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
          ],
          const SizedBox(height: 10),
          _MatchActions(match: m),
        ],
      ),
    ),
  );
}

Widget _miniChip(String label, int score) {
  final color = score >= 80
      ? AppTheme.success
      : score >= 50
          ? AppTheme.warning
          : AppTheme.textMuted;
  return Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text('$label $score',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    ),
  );
}

/// Workflow 3 admin actions for one match: approve + notify, generate the
/// Return QR, watch its live state, and confirm the physical return.
class _MatchActions extends StatefulWidget {
  final LfMatch match;
  const _MatchActions({required this.match});

  @override
  State<_MatchActions> createState() => _MatchActionsState();
}

class _MatchActionsState extends State<_MatchActions> {
  bool _busy = false;
  Stream<List<QrTransaction>>? _returnQrStream;

  Future<void> _approve() async {
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.approveMatchWithNotification(widget.match.id);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Match approved — the student has been notified.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Could not approve the match. Try again.');
    }
  }

  Future<void> _reject() async {
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.rejectMatch(widget.match.id);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Match rejected — the item is available again.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Could not reject the match. Try again.');
    }
  }

  Future<void> _generateReturnQr() async {
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final txn = await appState.issueReturnQr(widget.match);
      if (!mounted) return;
      setState(() => _busy = false);
      _showQRDialog(
        context,
        'Return QR',
        txn.token,
        'Show this code to ${widget.match.lostOwnerStudentId} when they collect the item. It expires in 10 minutes.',
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Could not generate the QR code. Try again.');
    }
  }

  Future<void> _confirmReturn(String txnId) async {
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.confirmReturn(txnId);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Return confirmed — the item is back with its owner.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Could not confirm the return. Try again.');
    }
  }

  Future<void> _cancelQr(String txnId) async {
    final appState = context.read<AppState>();
    try {
      await appState.cancelQrCode(txnId);
      if (!mounted) return;
      _toast(context, 'QR code cancelled.');
    } on AuthFailure catch (e) {
      if (!mounted) return;
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _toast(context, 'Could not cancel the code. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return Column(children: [
      if (m.status == MatchStatus.proposed) ...[
        if (m.isAiMatch) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppTheme.textMuted),
              SizedBox(width: 6),
              Text('AI Suggested Match',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic)),
            ]),
          ),
        ],
        GradientButton(
            label: 'Approve Match & Notify Student',
            onPressed: _busy ? null : _approve),
        const SizedBox(height: 10),
        OutlineBtn(
            label: 'Reject Match',
            color: AppTheme.danger,
            onPressed: _busy ? null : _reject),
      ],
      if (m.status == MatchStatus.approved) _returnQrSection(),
      if (m.status == MatchStatus.completed) ...[
        const _StatusBanner(
            text: 'Return completed — this item is back with its owner.'),
      ],
      if (m.status == MatchStatus.rejected) ...[
        const _StatusBanner(
            text: 'This match was rejected — the item is available again.'),
      ],
    ]);
  }

  Widget _returnQrSection() {
    final stream = _returnQrStream ??= context
        .read<AppState>()
        .watchReturnQrForInventory(widget.match.inventoryItemId);
    return StreamBuilder<List<QrTransaction>>(
      stream: stream,
      builder: (context, snapshot) {
        final qrs = snapshot.data ?? const <QrTransaction>[];
        QrTransaction? active;
        for (final t in qrs) {
          if (t.lostReportId == widget.match.lostReportId &&
              (t.status == QrStatus.issued || t.status == QrStatus.scanned)) {
            active = t;
            break;
          }
        }
        if (active == null) {
          return Column(children: [
            const NoticeBox(
                message:
                    'Generate a Return QR for the student to scan when they collect the item. The code expires in 10 minutes.',
                icon: Icons.qr_code_2_rounded),
            GradientButton(
                label: 'Generate Return QR',
                onPressed: _busy ? null : _generateReturnQr),
          ]);
        }
        final txn = active;
        if (txn.status == QrStatus.issued) {
          return Column(children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8)),
                          child: QrImageView(
                              data: txn.token,
                              version: QrVersions.auto,
                              size: 72,
                              backgroundColor: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Return QR issued',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                  'For ${txn.intendedStudentId} · expires in ${_AdminFoundDetailScreenState._qrMinutesLeft(txn)} min',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted)),
                            ])),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.red.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          'Key: ${txn.token}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: GradientButton(
                                label: 'Show Full QR & Key',
                                onPressed: () => _showQRDialog(
                                    context,
                                    'Return QR',
                                    txn.token,
                                    'Ask ${txn.intendedStudentId} to scan this code in the app when collecting the item, or give them the key to enter under "Input Key". It expires in 10 minutes.'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: OutlineBtn(
                                label: 'Cancel Code',
                                color: AppTheme.danger,
                                onPressed: () => _cancelQr(txn.id))),
                      ]),
                    ]))),
          ]);
        }
        return Column(children: [
          const _StatusBanner(
              text:
                  'The student scanned the code. Verify their identity and the item, then confirm the return.'),
          const SizedBox(height: 10),
          GradientButton(
              label: 'Confirm Return',
              onPressed: _busy ? null : () => _confirmReturn(txn.id)),
        ]);
      },
    );
  }
}

/// Bottom sheet listing active lost reports so an admin can pick the one an
/// inventory item matches. Pops with the chosen [Item].
class _LostReportPickerSheet extends StatefulWidget {
  const _LostReportPickerSheet();

  @override
  State<_LostReportPickerSheet> createState() => _LostReportPickerSheetState();
}

class _LostReportPickerSheetState extends State<_LostReportPickerSheet> {
  late final Stream<List<Item>> _lost;

  @override
  void initState() {
    super.initState();
    _lost = context.read<AppState>().watchAdminLostReports();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Text('Select a Lost Report',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(
            child: StreamBuilder<List<Item>>(
              stream: _lost,
              builder: (context, snapshot) {
                final data = snapshot.data ?? const <Item>[];
                final active =
                    data.where((r) => r.status == ItemStatus.active).toList();
                if (active.isEmpty) {
                  return const EmptyState(
                      title: 'No Active Lost Reports',
                      icon: Icons.search_off_rounded);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: active.length,
                  itemBuilder: (ctx, i) {
                    final r = active[i];
                    return CardRow(
                      title: r.title,
                      subtitle: '${r.reportedByStudentId} · ${r.category}',
                      extra: fmtDate(r.whenLostLabel),
                      status: r.status.wireValue,
                      onTap: () => Navigator.of(context).pop(r),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bottom sheet listing inventory items (In Inventory, not reserved) so an
/// admin can pick the one that matches a lost report. Includes a search box.
/// Pops with the chosen [InventoryItem].
class _InventoryPickerSheet extends StatefulWidget {
  const _InventoryPickerSheet();

  @override
  State<_InventoryPickerSheet> createState() => _InventoryPickerSheetState();
}

class _InventoryPickerSheetState extends State<_InventoryPickerSheet> {
  late final Stream<List<InventoryItem>> _items;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _items = context.read<AppState>().watchAllInventoryItems();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Text('Find a Matching Item',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by title or category',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<InventoryItem>>(
              stream: _items,
              builder: (context, snapshot) {
                final data = snapshot.data ?? const <InventoryItem>[];
                final available = data
                    .where((item) => item.status == InventoryStatus.inInventory)
                    .where((item) =>
                        _query.isEmpty ||
                        item.title.toLowerCase().contains(_query) ||
                        item.category.toLowerCase().contains(_query))
                    .toList();
                if (available.isEmpty) {
                  return const EmptyState(
                      title: 'No Available Items',
                      subtitle: 'Items handed over at the office appear here.',
                      icon: Icons.inventory_rounded);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: available.length,
                  itemBuilder: (ctx, i) {
                    final item = available[i];
                    return CardRow(
                      title: item.title,
                      subtitle:
                          '${item.category} · Finder ${item.finderStudentId}',
                      extra: item.handedOverAt == null
                          ? null
                          : 'Handed over ${fmtDate(item.handedOverAt!.toIso8601String())}',
                      status: item.status.wireValue,
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Shared Private Widgets ────────────────────────────────────────
class _Drop extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final void Function(String?) onChanged;
  const _Drop(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged));
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final String? Function(String?)? validator;
  const _Field(
      {required this.label,
      required this.hint,
      required this.ctrl,
      this.validator});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: ctrl,
          validator: validator,
          decoration: InputDecoration(labelText: label, hintText: hint)));
}

class _Area extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  const _Area({required this.label, required this.hint, required this.ctrl});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
              labelText: label, hintText: hint, alignLabelWithHint: true)));
}

class _PhotoBox extends StatefulWidget {
  final ValueChanged<List<File>> onImagesChanged;
  final bool polished;
  final bool foundStyle;
  const _PhotoBox({
    required this.onImagesChanged,
    this.polished = false,
    this.foundStyle = false,
  });

  @override
  State<_PhotoBox> createState() => _PhotoBoxState();
}

class _PhotoBoxState extends State<_PhotoBox> {
  final List<File> _images = [];
  static const int _maxImages = 3;

  Future<void> _pickImage(ImageSourceVia source) async {
    final appState = context.read<AppState>();
    try {
      final file = source == ImageSourceVia.gallery
          ? await appState.pickReportImageFromGallery()
          : await appState.pickReportImageFromCamera();
      if (file == null) return;
      setState(() {
        _images.add(file);
        if (_images.length > _maxImages) _images.removeAt(0);
      });
      widget.onImagesChanged(_images);
    } on CloudinaryException catch (e) {
      _toast(context, e.message);
    } catch (_) {
      _toast(context, 'Could not pick image. Please try again.');
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
    widget.onImagesChanged(_images);
  }

  void _showSourceSheet() {
    if (_images.length >= _maxImages) {
      _toast(context, 'Maximum $_maxImages photos allowed');
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Choose from Gallery'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickImage(ImageSourceVia.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('Take a Photo'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickImage(ImageSourceVia.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.close_rounded),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(sheetCtx).pop(),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      if (widget.foundStyle) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FoundPhotoLabel(count: _images.length),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _showSourceSheet,
              child: CustomPaint(
                painter: const _ReportLostDashedBorderPainter(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      _FoundPhotoUploadTile(),
                      SizedBox(height: 10),
                      Text('Tap to add photos',
                          style: TextStyle(
                              color: Luxe.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('You can add up to 3 photos',
                          style: TextStyle(color: Luxe.inkSoft, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }
      if (widget.polished) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add Photos (Optional)',
                style: TextStyle(
                    color: Luxe.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _showSourceSheet,
              child: CustomPaint(
                painter: const _ReportLostDashedBorderPainter(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: Luxe.primary.withValues(alpha: .025),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      _ReportLostUploadTile(),
                      SizedBox(height: 10),
                      Text('Tap to add photos',
                          style: TextStyle(
                              color: Luxe.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('You can add up to 3 photos',
                          style: TextStyle(color: Luxe.inkSoft, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return GestureDetector(
        onTap: _showSourceSheet,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.04),
              border: Border.all(
                  color: AppTheme.red.withValues(alpha: 0.25), width: 1.5),
              borderRadius: BorderRadius.circular(14)),
          child: const Column(children: [
            Icon(Icons.add_photo_alternate_rounded,
                size: 36, color: AppTheme.textMuted),
            SizedBox(height: 8),
            Text('Tap to add photo',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            Text('Optional · Up to $_maxImages photos',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
          ]),
        ),
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length + (_images.length < _maxImages ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              if (i < _images.length) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_images[i],
                          width: 100, height: 100, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(i),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return GestureDetector(
                onTap: _showSourceSheet,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.04),
                      border: Border.all(
                          color: AppTheme.red.withValues(alpha: 0.25),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_rounded,
                      size: 32, color: AppTheme.textMuted),
                ),
              );
            },
          ),
        ),
      ],
    );
    if (widget.foundStyle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FoundPhotoLabel(count: _images.length),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Luxe.primary.withValues(alpha: .12)),
            ),
            child: content,
          ),
        ],
      );
    }
    if (!widget.polished) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Add Photos (Optional)',
            style: TextStyle(
                color: Luxe.ink, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Luxe.primary.withValues(alpha: .12)),
          ),
          child: content,
        ),
      ],
    );
  }
}

class _FoundPhotoLabel extends StatelessWidget {
  final int count;

  const _FoundPhotoLabel({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Add Photos (Optional)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Luxe.ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$count/3',
              style: const TextStyle(
                  color: Luxe.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _FoundPhotoUploadTile extends StatelessWidget {
  const _FoundPhotoUploadTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: .10),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.add_a_photo_outlined,
          color: Luxe.primaryDeep, size: 29),
    );
  }
}

class _ReportLostUploadTile extends StatelessWidget {
  const _ReportLostUploadTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
      ),
      child:
          const Icon(Icons.cloud_upload_rounded, color: Luxe.primary, size: 28),
    );
  }
}

class _ReportLostDashedBorderPainter extends CustomPainter {
  const _ReportLostDashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Luxe.primary.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(16)));
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 10) {
        final end = (distance + 5).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReportLostDashedBorderPainter oldDelegate) =>
      false;
}

enum ImageSourceVia { gallery, camera }

class _SuccessView extends StatelessWidget {
  final String title, msg;
  final VoidCallback onHome;
  final VoidCallback? onSub;
  final String? subLabel;
  const _SuccessView(
      {required this.title,
      required this.msg,
      required this.onHome,
      this.onSub,
      this.subLabel});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              AppTheme.red.withOpacity(0.2),
                              AppTheme.redLight.withOpacity(0.15)
                            ]),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.red.withOpacity(0.3))),
                        child: const Icon(Icons.check_rounded,
                            color: AppTheme.red, size: 40))
                    .animate()
                    .scale(
                        delay: 100.ms,
                        duration: 400.ms,
                        curve: Curves.elasticOut),
                const SizedBox(height: 24),
                Text(title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary))
                    .animate()
                    .fadeIn(delay: 200.ms),
                const SizedBox(height: 12),
                Text(msg,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.65))
                    .animate()
                    .fadeIn(delay: 300.ms),
                const SizedBox(height: 28),
                GradientButton(label: 'Back to Hub', onPressed: onHome),
                if (onSub != null) ...[
                  const SizedBox(height: 10),
                  OutlineBtn(label: subLabel!, onPressed: onSub)
                ],
              ]))));
}

// ── Handover Stepper Widget ─────────────────────────────────────────
class _HandoverStepper extends StatelessWidget {
  final int currentStep; // 1-5
  const _HandoverStepper({required this.currentStep});

  static const _steps = [
    {'title': 'Report Submitted', 'subtitle': 'Found item report created'},
    {'title': 'Visit Inventory Office', 'subtitle': 'Block A, Level 1'},
    {'title': 'Hand Over Item', 'subtitle': 'Give item to staff'},
    {'title': 'QR Verification', 'subtitle': 'Scan staff QR code'},
    {'title': 'Handover Complete', 'subtitle': 'All done!'},
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.timeline_rounded, color: AppTheme.red, size: 20),
              SizedBox(width: 8),
              Text('Handover Progress',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 16),
            ...List.generate(_steps.length, (i) {
              final stepNum = i + 1;
              final isCompleted = stepNum < currentStep;
              final isActive = stepNum == currentStep;
              final isPending = stepNum > currentStep;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Circle indicator
                      Column(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isCompleted
                                ? const LinearGradient(colors: [
                                    Color(0xFF4CAF50),
                                    Color(0xFF66BB6A)
                                  ])
                                : isActive
                                    ? const LinearGradient(colors: [
                                        Color(0xFFC41E3A),
                                        Color(0xFFE8475F)
                                      ])
                                    : null,
                            color: isPending ? const Color(0xFFB0BEC5) : null,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                        color: AppTheme.red.withOpacity(0.3),
                                        blurRadius: 8)
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isCompleted
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 16)
                                : Text('$stepNum',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: isPending
                                            ? Colors.white70
                                            : Colors.white)),
                          ),
                        ),
                        // Connector line (not on last step)
                        if (i < _steps.length - 1)
                          Container(
                            width: 2,
                            height: 28,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? const Color(0xFF4CAF50)
                                  : isActive
                                      ? AppTheme.red
                                      : const Color(0xFFE0E0E0),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                      ]),
                      const SizedBox(width: 14),
                      // Text content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _steps[i]['title']!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isCompleted
                                      ? const Color(0xFF4CAF50)
                                      : isActive
                                          ? AppTheme.red
                                          : AppTheme.textMuted,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _steps[i]['subtitle']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isActive
                                      ? AppTheme.textSecondary
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Shared Workflow Widgets ─────────────────────────────────────────
// Used by both the student found-detail (Handover QR) and the student
// lost-detail (Return QR): a green status banner, the manual-entry +
// camera scan section, and the camera scanner sheet itself.

/// Green success banner used for handover/return lifecycle milestones.
class _StatusBanner extends StatelessWidget {
  final String text;
  const _StatusBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.green))),
      ]),
    );
  }
}

/// Student scan section: two front doors to the same single-use token check
/// — "Scan QR" (camera, with a gallery-image fallback) and "Input Key"
/// (manual entry of the key shown under the office QR). Both paths call
/// [AppState.scanQrCode], so the Firestore rules are the gate for every
/// write no matter which door is used.
class _QrScanSection extends StatefulWidget {
  final String instruction;
  final VoidCallback onSuccess;

  /// For return QRs (Workflow 3): the lost report the student is scanning
  /// from. The QR's stored `lostReportId` must match, preventing cross-report
  /// scanning. Pass `null` for handover scans (Workflow 2).
  final String? lostReportId;
  const _QrScanSection({
    required this.instruction,
    required this.onSuccess,
    this.lostReportId,
  });

  @override
  State<_QrScanSection> createState() => _QrScanSectionState();
}

class _QrScanSectionState extends State<_QrScanSection> {
  final _codeController = TextEditingController();
  bool _busy = false;
  bool _showKeyInput = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(String token) async {
    if (_busy) return;
    final code = token.trim();
    if (code.isEmpty) {
      _toast(context, 'Please enter the key or scan the QR code');
      return;
    }
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final outcome =
          await appState.scanQrCode(code, lostReportId: widget.lostReportId);
      if (!mounted) return;
      setState(() => _busy = false);
      if (outcome.success) {
        _codeController.clear();
        widget.onSuccess();
      } else {
        _toast(context, outcome.message);
      }
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Could not verify the code. Please try again.');
    }
  }

  void _scanWithCamera() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => _QrScannerSheet(
        onDetect: (code) {
          Navigator.of(sheetCtx).pop();
          _submit(code);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NoticeBox(
                message: widget.instruction,
                icon: Icons.qr_code_scanner_rounded,
              ),
              const SizedBox(height: 14),
              // Option 1 — Scan QR: live camera with a gallery fallback.
              GradientButton(
                label: _busy ? 'Verifying…' : 'Scan QR',
                onPressed: _busy ? null : _scanWithCamera,
              ),
              const SizedBox(height: 10),
              // Option 2 — Input Key: the same token the QR encodes, for
              // when the camera cannot read the code.
              OutlineBtn(
                label: _showKeyInput ? 'Hide Key Input' : 'Input Key',
                onPressed: _busy
                    ? null
                    : () => setState(() => _showKeyInput = !_showKeyInput),
              ),
              if (_showKeyInput) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter the key shown under the QR code…',
                    prefixIcon:
                        const Icon(Icons.key_rounded, color: AppTheme.red),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppTheme.red.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.red, width: 2)),
                  ),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1),
                  onSubmitted:
                      _busy ? null : (_) => _submit(_codeController.text),
                ),
                const SizedBox(height: 10),
                GradientButton(
                  label: _busy ? 'Verifying…' : 'Verify Key',
                  onPressed: _busy ? null : () => _submit(_codeController.text),
                ),
              ],
            ])));
  }
}

/// Camera scanner bottom sheet. The camera is live on top; a gallery button
/// below lets the user upload a photo of the QR instead. Either way the first
/// raw code detected is delivered exactly once (extra frames are ignored
/// while the caller submits the scan).
class _QrScannerSheet extends StatefulWidget {
  final void Function(String code) onDetect;
  const _QrScannerSheet({required this.onDetect});

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  final ImagePicker _picker = ImagePicker();
  bool _handled = false;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code =
        capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    _handled = true;
    widget.onDetect(code);
  }

  /// Decodes a QR from a photo picked from the gallery — the fallback for
  /// when the live camera cannot read the code.
  Future<void> _pickFromGallery() async {
    if (_handled || _picking) return;
    setState(() => _picking = true);
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final capture = await _controller.analyzeImage(picked.path);
      if (!mounted) return;
      setState(() => _picking = false);
      final code = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (code == null || code.isEmpty) {
        _toast(context, 'No QR code found in that image. Please try another.');
        return;
      }
      if (_handled) return;
      _handled = true;
      widget.onDetect(code);
    } catch (_) {
      if (!mounted) return;
      setState(() => _picking = false);
      _toast(context, 'Could not read that image. Please try a clearer photo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              const Text('Scan QR Code',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.no_photography_rounded,
                            color: Colors.white70, size: 40),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Camera unavailable. Upload a photo of the QR from the gallery, or use Input Key instead.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                                height: 1.5),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(children: [
              OutlineBtn(
                label: _picking ? 'Reading image…' : 'Upload QR from Gallery',
                onPressed: _picking ? null : _pickFromGallery,
              ),
              const SizedBox(height: 8),
              const Text(
                'Point the camera at the office QR code, or upload a photo of it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Found Report Stepper View (after submission) ─────────────────────
class _FoundReportStepperView extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback? onViewReports;
  const _FoundReportStepperView({required this.onHome, this.onViewReports});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Success icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppTheme.red.withOpacity(0.2),
                    AppTheme.redLight.withOpacity(0.15)
                  ]),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppTheme.red, size: 40),
              ).animate().scale(
                  delay: 100.ms, duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 20),
              const Text('Found Item Reported!',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary))
                  .animate()
                  .fadeIn(delay: 200.ms),
              const SizedBox(height: 8),
              const Text('Your report is saved with status: Awaiting',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary))
                  .animate()
                  .fadeIn(delay: 250.ms),
              const SizedBox(height: 8),
              const Text('Follow these steps to complete the handover:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary))
                  .animate()
                  .fadeIn(delay: 300.ms),
              const SizedBox(height: 20),

              // Stepper showing step 1 completed, step 2 active
              const _HandoverStepper(currentStep: 2),

              const SizedBox(height: 24),
              GradientButton(
                  label: 'View My Found Reports',
                  onPressed: onViewReports ?? onHome),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Back to Hub', onPressed: onHome),
            ],
          ),
        ),
      ),
    );
  }
}
