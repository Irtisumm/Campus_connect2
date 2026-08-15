import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/item.dart';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';
import '../../services/data_service.dart';
import '../../services/lost_found_service.dart';
import '../../services/app_state.dart';
import '../../services/cloudinary_service.dart';
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
                const SizedBox(height: Luxe.s1),
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
                      subtitle: "I've lost something on campus",
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
                      subtitle: 'I found something on campus',
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
                    lost: lost.length, found: found.length, active: active),
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

  const _LostFoundIdentityRow({this.includeTopSafeArea = true});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final tiny = constraints.maxWidth < 350;
        final logoSize = tiny
            ? 44.0
            : compact
                ? 46.0
                : 52.0;
        final controlSize = tiny
            ? 36.0
            : compact
                ? 38.0
                : 44.0;
        final iconSize = tiny
            ? 18.0
            : compact
                ? 20.0
                : 23.0;
        final gap = tiny
            ? 3.0
            : compact
                ? 4.0
                : 8.0;
        final roleWidth = tiny
            ? 66.0
            : compact
                ? 74.0
                : 132.0;

        final row = Padding(
          padding: EdgeInsets.only(
            top: tiny ? 3 : 7,
            bottom: tiny ? 3 : 5,
          ),
          child: Row(
            children: [
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
                          fontSize: compact ? 17 : 19,
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
                                fontSize: compact ? 10 : 10.5,
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
              Consumer2<DataService, AppState>(
                builder: (context, dataService, appState, child) {
                  final unreadCount =
                      dataService.unreadNotificationCountForUser(
                          appState.userId, appState.isAdmin);
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
                                    color: Colors.white.withValues(alpha: .9),
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

class _LostFoundHero extends StatelessWidget {
  const _LostFoundHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        return SizedBox(
          height: compact ? 140 : 148,
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
                          'Report lost or found items and help our campus community.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Luxe.body.copyWith(
                            color: Luxe.inkSoft,
                            fontSize: compact ? 14 : 15,
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
                top: compact ? 6 : 8,
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
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LuxeSecurityChip('Secure'),
                    SizedBox(width: Luxe.s2),
                    LuxeSecurityChip('Encrypted'),
                    SizedBox(width: Luxe.s2),
                    LuxeSecurityChip('Trusted'),
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
  final String title, subtitle;
  final IconData icon;
  final Gradient gradient;
  final Color glow;
  final List<IconData> illustration;
  final VoidCallback onTap;

  const _HeroActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.illustration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final helperText = subtitle.replaceFirst(' on campus', '\non campus');
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowCard = constraints.maxWidth < 170;
        final cardHeight = narrowCard ? 116.0 : 112.0;
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
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title,
                              maxLines: 1,
                              style: Luxe.cardTitle.copyWith(
                                  fontSize: 14.5, color: Colors.white)),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(right: 36),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(helperText,
                                maxLines: 2,
                                style: Luxe.body.copyWith(
                                    fontSize: 11,
                                    height: 1.25,
                                    color:
                                        Colors.white.withValues(alpha: 0.90))),
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
                        width: 48,
                        height: 48,
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
    return Scaffold(
      appBar: _gradientAppBar('Report Found Item', context),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            NoticeBox(
                message:
                    'Please hand the item to Lost & Found Office (Block A, Level 1) after submitting.',
                borderColor: AppTheme.red,
                bgColor: AppTheme.red.withOpacity(0.08),
                textColor: const Color(0xFF8B1428)),
            _Drop(
                label: 'Category',
                value: _cat,
                items: _cats,
                onChanged: (v) => setState(() => _cat = v)),
            _Area(
                label: 'Description',
                hint: 'Describe what you found',
                ctrl: _descC),
            _Drop(
                label: 'Where Found',
                value: _loc,
                items: _locs,
                onChanged: (v) => setState(() => _loc = v)),
            _PhotoBox(
                onImagesChanged: (imgs) => _images
                  ..clear()
                  ..addAll(imgs)),
            const SizedBox(height: 16),
            GradientButton(
                label: 'Submit Report', onPressed: _saving ? null : _submit),
            const SizedBox(height: 10),
            OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
          ])),
    );
  }
}

// ── Screen 4: My Lost Reports ────────────────────────────────────
class MyLostReportsScreen extends StatefulWidget {
  const MyLostReportsScreen({super.key});
  @override
  State<MyLostReportsScreen> createState() => _MyLostReportsScreenState();
}

class _MyLostReportsScreenState extends State<MyLostReportsScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Item>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchMyLostReports();
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
        return Scaffold(
          appBar: _gradientAppBar('My Lost Reports', context, actions: [
            TextButton.icon(
                onPressed: () => context.push('/lost-found/report-lost'),
                icon: const Icon(Icons.add, color: Colors.white, size: 16),
                label: const Text('Report',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
          ]),
          body: isLoading && data.isEmpty
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
                  : data.isEmpty
                      ? const EmptyState(
                          title: 'No Lost Reports',
                          icon: Icons.search_off_rounded)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: data.length,
                          itemBuilder: (ctx, i) {
                            final r = data[i];
                            return CardRow(
                                    title: r.title,
                                    subtitle: '${r.category} · ${r.whereLost}',
                                    extra: relativeTime(r.whenLostLabel),
                                    status: r.status.wireValue,
                                    onTap: () => context
                                        .push('/lost-found/lost/${r.id}'))
                                .animate()
                                .fadeIn(delay: (i * 60).ms)
                                .slideY(begin: 0.15);
                          }),
        );
      },
    );
  }
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
        final data = snapshot.data ?? const <Item>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        // The service maps every FirebaseException to an AuthFailure, so this
        // message is already safe to show — permission denied, offline and
        // network failures all arrive here with their own wording.
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('My Found Reports', context),
          body: isLoading && data.isEmpty
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
                  : data.isEmpty
                      ? const EmptyState(
                          title: 'No Found Reports',
                          icon: Icons.upload_file_rounded)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: data.length,
                          itemBuilder: (ctx, i) {
                            final r = data[i];
                            return CardRow(
                              title: r.description,
                              subtitle: '${r.category} · ${r.whereLost}',
                              extra: relativeTime(r.whenLostLabel),
                              status: r.status.wireValue,
                              onTap: () =>
                                  context.push('/lost-found/found/${r.id}'),
                            )
                                .animate()
                                .fadeIn(delay: (i * 60).ms)
                                .slideY(begin: 0.15);
                          }),
        );
      },
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
                  // Return QR scan section — shown while a return code for
                  // this report is Issued.
                  if (qrIssued) ...[
                    const SectionLabel('Collect Your Item'),
                    _QrScanSection(
                      instruction:
                          'The office has a Return QR ready for you. Scan it with your camera or enter the code when you collect your item.',
                      onSuccess: () => _toast(context,
                          'Code verified. Please wait for the office to confirm.'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (qrScanned) ...[
                    const _StatusBanner(
                        text:
                            'Code verified — the office will confirm your collection.'),
                    const SizedBox(height: 10),
                  ],
                  if (r.status == ItemStatus.active)
                    OutlineBtn(
                      label: 'Close Report',
                      color: AppTheme.danger,
                      onPressed: () async {
                        final appState = context.read<AppState>();
                        try {
                          await appState.closeReport(widget.id);
                          if (!mounted) return;
                          _toast(context, 'Report closed');
                        } on AuthFailure catch (e) {
                          if (!mounted) return;
                          _toast(context, e.message);
                        } catch (_) {
                          if (!mounted) return;
                          _toast(context, 'Could not close report. Try again.');
                        }
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Screen 7: Found Detail (Student) ────────────────────────────
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

  /// Guards the one-shot "handover confirmed" dialog so it fires only on the
  /// Awaiting Handover → In Inventory transition, not on every rebuild.
  bool _handoverDialogShown = false;

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

        final bool awaiting = r.status == ItemStatus.awaitingHandover;
        final bool inInventory = r.status == ItemStatus.inInventory;
        final bool returned = r.status == ItemStatus.returned;
        final bool qrIssued = qr != null && qr.status == QrStatus.issued;
        final bool qrScanned = qr != null && qr.status == QrStatus.scanned;

        // One-shot success dialog on the Awaiting Handover → In Inventory
        // transition (the admin has confirmed the physical handover).
        if (inInventory && !_handoverDialogShown) {
          _handoverDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showHandoverSuccessDialog(context);
          });
        }

        final int step = inInventory || returned
            ? 5
            : (qrIssued || qrScanned)
                ? 4
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
                        StatusBadge(r.status.wireValue),
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
                      'The admin has generated a QR code for item handover. Scan it with your camera or enter the code to confirm you have handed over the item.',
                  onSuccess: () => _toast(context,
                      'Code verified. Please wait for the office to confirm.'),
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

  void _showHandoverSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
          SizedBox(width: 10),
          Text('Done!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Item handover has been confirmed successfully.\n\nThank you for handing over the found item. You can track the progress in "My Found Reports".',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.55)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
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

/// One merged row: either a Firestore `lfNotifications` document (match
/// alerts, Workflow 3) or a derived report notification.
class _NotifRow {
  final bool isLf;
  final String title;
  final String body;
  final DateTime? at;
  final bool read;
  final String lfId;
  final String derivedReportId;
  final String relatedReportId;

  const _NotifRow({
    required this.isLf,
    required this.title,
    required this.body,
    required this.at,
    required this.read,
    this.lfId = '',
    this.derivedReportId = '',
    this.relatedReportId = '',
  });
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<AppNotification>> _notifications;
  late final Stream<List<LfNotification>> _lfNotifications;

  /// Derived-notification rows the user has tapped, by report ID.
  ///
  /// Read state for derived rows lives here rather than in Firestore:
  /// notifications are derived from the `items` documents, and `Item` has no
  /// `read` field to write to, so marking them read is session-local. Match
  /// alerts (`lfNotifications`) persist their read state in Firestore.
  final Set<String> _read = <String>{};

  @override
  void initState() {
    super.initState();
    _notifications = context.read<AppState>().watchNotifications();
    _lfNotifications = context.read<AppState>().watchMyLfNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LfNotification>>(
      stream: _lfNotifications,
      builder: (context, lfSnap) {
        final lfNs = lfSnap.data ?? const <LfNotification>[];
        return StreamBuilder<List<AppNotification>>(
          stream: _notifications,
          builder: (context, snapshot) {
            final ns = snapshot.data ?? const <AppNotification>[];
            final isLoading =
                (snapshot.connectionState == ConnectionState.waiting ||
                        lfSnap.connectionState == ConnectionState.waiting) &&
                    ns.isEmpty &&
                    lfNs.isEmpty;
            // The services map every FirebaseException to an AuthFailure, so
            // these messages are already safe to show — permission denied,
            // offline and network failures all arrive with their own wording.
            final error = snapshot.error ?? lfSnap.error;

            final rows = <_NotifRow>[
              for (final lf in lfNs)
                _NotifRow(
                  isLf: true,
                  title: lf.title,
                  body: lf.body,
                  at: lf.createdAt,
                  read: lf.read,
                  lfId: lf.id,
                  relatedReportId: lf.relatedReportId,
                ),
              for (final n in ns)
                _NotifRow(
                  isLf: false,
                  title: n.text,
                  body: '',
                  at: n.at,
                  read: _read.contains(n.id),
                  derivedReportId: n.id,
                ),
            ]..sort((a, b) => (b.at ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(a.at ?? DateTime.fromMillisecondsSinceEpoch(0)));

            return Scaffold(
              appBar: _gradientAppBar('Notifications', context),
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
                      : rows.isEmpty
                          ? const EmptyState(
                              title: 'No Notifications',
                              icon: Icons.notifications_off_rounded)
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: rows.length,
                              itemBuilder: (ctx, i) {
                                final row = rows[i];
                                return GestureDetector(
                                  onTap: () => _onRowTap(context, row),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: row.read
                                          ? AppTheme.bgCard
                                          : AppTheme.red.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: row.read
                                              ? AppTheme.red.withOpacity(0.1)
                                              : AppTheme.red.withOpacity(0.25)),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 6),
                                      leading: CircleAvatar(
                                          backgroundColor: row.isLf
                                              ? AppTheme.red.withOpacity(0.12)
                                              : AppTheme.gold.withOpacity(0.2),
                                          child: Icon(
                                              row.isLf
                                                  ? Icons.link_rounded
                                                  : Icons.campaign_rounded,
                                              color: row.isLf
                                                  ? AppTheme.red
                                                  : AppTheme.goldDark,
                                              size: 20)),
                                      title: Text(row.title,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: row.read
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              color: AppTheme.textPrimary)),
                                      subtitle: row.body.isEmpty
                                          ? Text(_rowTime(row),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted))
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(row.body,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppTheme
                                                            .textSecondary)),
                                                Text(_rowTime(row),
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppTheme
                                                            .textMuted)),
                                              ],
                                            ),
                                      trailing: row.read
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
      },
    );
  }

  Future<void> _onRowTap(BuildContext context, _NotifRow row) async {
    if (row.isLf) {
      // Match alerts persist read state in Firestore; tapping also opens the
      // linked lost report when one is attached.
      if (!row.read) {
        await context.read<AppState>().markLfNotificationRead(row.lfId);
      }
      if (!mounted) return;
      if (row.relatedReportId.isNotEmpty) {
        context.push('/lost-found/lost/${row.relatedReportId}');
      }
      return;
    }
    if (!row.read) {
      setState(() => _read.add(row.derivedReportId));
    }
  }

  /// Same wording as every other Lost & Found list ('Today' / 'Yesterday' /
  /// 'N days ago'). A row whose server timestamp has not resolved yet has no
  /// date to show.
  static String _rowTime(_NotifRow row) =>
      row.at == null ? '—' : relativeTime(row.at!.toIso8601String());
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

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchAdminAllReports();
    _matches = context.read<AppState>().watchAllMatches();
    _inventory = context.read<AppState>().watchAllInventoryItems();
  }

  @override
  Widget build(BuildContext context) {
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
                  final lost = all.where((r) => r.isLost).length;
                  final found = all.where((r) => r.isFound).length;
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
                                  label: 'In Inventory',
                                  valueColor: AppTheme.redDark,
                                  bgColor: AppTheme.red.withOpacity(0.07))),
                        ]).animate().fadeIn(delay: 50.ms),
                      const SectionLabel('Quick Actions'),
                      HubButton(
                              icon: Icons.list_alt_rounded,
                              label: 'View Lost Reports',
                              subtitle: isLoading || error != null
                                  ? 'Loading…'
                                  : '$lost total',
                              onTap: () =>
                                  context.push('/admin/lost-found/lost-list'))
                          .animate()
                          .fadeIn(delay: 100.ms),
                      HubButton(
                              icon: Icons.inventory_rounded,
                              label: 'Found / Inventory',
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
                  final pending = matches
                      .where((m) => m.status == MatchStatus.proposed)
                      .length;
                  return HubButton(
                          icon: Icons.compare_arrows_rounded,
                          label: 'Review Matches',
                          subtitle: '$pending pending approval',
                          onTap: () =>
                              context.push('/admin/lost-found/match-list'))
                      .animate()
                      .fadeIn(delay: 350.ms);
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

  @override
  void initState() {
    super.initState();
    _reports = context.read<AppState>().watchAdminLostReports();
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
        return Scaffold(
          appBar: _gradientAppBar('All Lost Reports', context),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
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
                        : data.isEmpty
                            ? const EmptyState(
                                title: 'No Lost Reports',
                                icon: Icons.search_off_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: data.length,
                                itemBuilder: (ctx, i) {
                                  final r = data[i];
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
                                    status: r.status.wireValue,
                                    onTap: () => context
                                        .push('/admin/lost-found/lost/${r.id}'),
                                  )
                                      .animate()
                                      .fadeIn(delay: (i * 55).ms)
                                      .slideY(begin: 0.12);
                                })),
          ]),
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
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('Found / Inventory', context),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
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
                        : data.isEmpty
                            ? const EmptyState(
                                title: 'No Found Reports',
                                icon: Icons.inventory_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: data.length,
                                itemBuilder: (ctx, i) {
                                  final r = data[i];
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
    // `aiScore`, `matchedFoundId` and `matches` have no Firestore counterpart
    // yet — AI matching is out of scope for this phase. Held as inert locals so
    // the original AI / Potential Matches sections keep their place in the tree
    // but render only when data backs them, which is never for a plain
    // Firestore document today.
    final int? aiScore = null;
    final String? matchedFoundId = null;
    final List<Object> matchList = const [];

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
                      StatusBadge(r.status.wireValue)
                    ]),
                    const Divider(height: 18),
                    InfoRow(label: 'Student ID', value: r.reportedByStudentId),
                    InfoRow(label: 'Category', value: r.category),
                    InfoRow(label: 'Where Lost', value: r.whereLost),
                    InfoRow(
                        label: 'Submitted', value: fmtDate(r.whenLostLabel)),
                  ]))),
          if (aiScore != null) ...[
            const SectionLabel('AI Match Score'),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppTheme.red.withOpacity(0.08),
                      AppTheme.redLight.withOpacity(0.06)
                    ]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.red.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.psychology_rounded,
                      color: AppTheme.red, size: 28),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI Confidence',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.red)),
                        Text(
                            '$aiScore% match with ${matchedFoundId ?? "found item"}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                      ])
                ])),
          ],
          if (matchList.isNotEmpty) ...[
            const SectionLabel('Potential Matches'),
            // Out of scope this phase; the list is always empty against a plain
            // Firestore document, so nothing renders here today.
            ...matchList.map((m) => const SizedBox.shrink()),
          ],
          const SizedBox(height: 10),
          // The "Mark as Resolved" action writes status, which has no Firestore
          // path yet (status transitions are out of scope for this phase). The
          // button is kept visually unchanged per the no-redesign rule, but its
          // tap surfaces the situation instead of calling DataService.
          if (r.status != ItemStatus.resolved)
            GradientButton(
                label: 'Mark as Resolved',
                onPressed: () async {
                  final appState = context.read<AppState>();
                  try {
                    await appState.resolveReport(widget.id);
                    if (!mounted) return;
                    _toast(context, 'Report marked as resolved');
                  } on AuthFailure catch (e) {
                    if (!mounted) return;
                    _toast(context, e.message);
                  } catch (_) {
                    if (!mounted) return;
                    _toast(context, 'Could not update status. Try again.');
                  }
                }),
        ],
      ),
    );
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const AdminBar(), const SizedBox(height: 8),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text(r.description,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800))),
                      StatusBadge(r.status.wireValue)
                    ]),
                    const Divider(height: 18),
                    InfoRow(label: 'Finder ID', value: r.reportedByStudentId),
                    InfoRow(label: 'Category', value: r.category),
                    InfoRow(label: 'Where Found', value: whereFound),
                    InfoRow(label: 'When Found', value: fmtDate(whenFound)),
                  ]))),
          const SizedBox(height: 10),
          // Workflow 2 — handover controls while the item awaits handover.
          if (r.status == ItemStatus.awaitingHandover)
            _handoverControls(context, r),
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
          // Status-based fallbacks. Admins can resolve or close any report.
          if (r.status == ItemStatus.active ||
              r.status == ItemStatus.matchedPending) ...[
            GradientButton(
                label: 'Mark as Resolved',
                onPressed: () async {
                  final appState = context.read<AppState>();
                  try {
                    await appState.resolveReport(widget.id);
                    if (!mounted) return;
                    _toast(context, 'Report marked as resolved');
                  } on AuthFailure catch (e) {
                    if (!mounted) return;
                    _toast(context, e.message);
                  } catch (_) {
                    if (!mounted) return;
                    _toast(context, 'Could not update status. Try again.');
                  }
                }),
            const SizedBox(height: 10),
            OutlineBtn(
                label: 'Close Report',
                color: AppTheme.danger,
                onPressed: () async {
                  final appState = context.read<AppState>();
                  try {
                    await appState.closeReport(widget.id);
                    if (!mounted) return;
                    _toast(context, 'Report closed');
                  } on AuthFailure catch (e) {
                    if (!mounted) return;
                    _toast(context, e.message);
                  } catch (_) {
                    if (!mounted) return;
                    _toast(context, 'Could not close report. Try again.');
                  }
                }),
          ],
          if (r.status == ItemStatus.resolved) ...[
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
            const SizedBox(height: 10),
            OutlineBtn(
                label: 'Close Report',
                color: AppTheme.danger,
                onPressed: () async {
                  final appState = context.read<AppState>();
                  try {
                    await appState.closeReport(widget.id);
                    if (!mounted) return;
                    _toast(context, 'Report closed');
                  } on AuthFailure catch (e) {
                    if (!mounted) return;
                    _toast(context, e.message);
                  } catch (_) {
                    if (!mounted) return;
                    _toast(context, 'Could not close report. Try again.');
                  }
                }),
          ],
          if (r.status == ItemStatus.closed) ...[
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
            const NoticeBox(
              message:
                  'Generate a Handover QR for the finder to scan when they hand over the item at the office. The code expires in 10 minutes and can only be scanned by this finder.',
              icon: Icons.qr_code_2_rounded,
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
                      Row(children: [
                        Expanded(
                            child: OutlineBtn(
                                label: 'Show Full QR',
                                onPressed: () => _showQRDialog(
                                    context,
                                    'Handover QR',
                                    txn.token,
                                    'Ask ${txn.intendedStudentId} to scan this code in the app to confirm handover. It expires in 10 minutes.'))),
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

void _showQRDialog(
    BuildContext context, String title, String code, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.qr_code_2_rounded, color: AppTheme.red, size: 28),
        const SizedBox(width: 10),
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.red.withOpacity(0.08),
              AppTheme.redLight.withOpacity(0.05)
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.red.withOpacity(0.3), width: 2),
          ),
          child: Column(children: [
            // The QR image encodes only the opaque token — no personal data,
            // no write authority. Scanning it alone never changes a status.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(message,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.55),
            textAlign: TextAlign.center),
      ]),
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
        final data = snapshot.data ?? const <InventoryItem>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('Inventory Office', context),
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

// ── Screen 15: Admin Inventory Detail ─────────────────────────────
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

  @override
  void initState() {
    super.initState();
    _item = context.read<AppState>().watchInventoryItem(widget.id);
    _matches = context.read<AppState>().watchAllMatches();
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
                      : _inventoryDetailBody(context, item),
        );
      },
    );
  }

  Widget _inventoryDetailBody(BuildContext context, InventoryItem item) {
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
                    Row(children: [
                      Expanded(
                          child: Text(item.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800))),
                      StatusBadge(item.status.wireValue),
                    ]),
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
                    const SizedBox(height: 8),
                    Text(item.description,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.55)),
                  ]))),
          const SizedBox(height: 10),
          if (!item.isReturned) _createMatchSection(context, item),
          // Matches already linked to this inventory item.
          StreamBuilder<List<LfMatch>>(
            stream: _matches,
            builder: (context, snap) {
              final all = snap.data ?? const <LfMatch>[];
              final mine =
                  all.where((m) => m.inventoryItemId == item.id).toList();
              if (mine.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Matches'),
                  ...mine.map((m) => _matchCard(context, m)),
                ],
              );
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
  late final Stream<List<LfMatch>> _matches;

  @override
  void initState() {
    super.initState();
    _matches = context.read<AppState>().watchAllMatches();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LfMatch>>(
      stream: _matches,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <LfMatch>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _gradientAppBar('Review Matches', context),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
            Expanded(
                child: isLoading && data.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.red))
                    : error != null
                        ? EmptyState(
                            title: 'Could Not Load Matches',
                            subtitle: error is AuthFailure
                                ? error.message
                                : 'Something went wrong. Please try again.',
                            icon: Icons.cloud_off_rounded,
                          )
                        : data.isEmpty
                            ? const EmptyState(
                                title: 'No Matches',
                                icon: Icons.compare_arrows_rounded)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: data.length,
                                itemBuilder: (ctx, i) {
                                  final m = data[i];
                                  return CardRow(
                                    title:
                                        'Lost ${m.lostReportId} ↔ Item ${m.inventoryItemId}',
                                    subtitle: 'Owner ${m.lostOwnerStudentId}',
                                    status: m.status.wireValue,
                                    onTap: () => context.push(
                                        '/admin/lost-found/match/${m.id}'),
                                  ).animate().fadeIn(delay: (i * 60).ms);
                                })),
          ]),
        );
      },
    );
  }
}

class AdminMatchDetailScreen extends StatefulWidget {
  final String id;
  const AdminMatchDetailScreen({super.key, required this.id});
  @override
  State<AdminMatchDetailScreen> createState() => _AdminMatchDetailScreenState();
}

class _AdminMatchDetailScreenState extends State<AdminMatchDetailScreen> {
  late final Stream<LfMatch?> _match;

  @override
  void initState() {
    super.initState();
    _match = context.read<AppState>().watchMatch(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LfMatch?>(
      stream: _match,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final m = snapshot.data;
        return Scaffold(
          appBar: _gradientAppBar('Match Review', context),
          body: isLoading && m == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Match',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : m == null
                      ? const EmptyState(
                          title: 'Match Not Found',
                          icon: Icons.search_off_rounded)
                      : _matchDetailBody(context, m),
        );
      },
    );
  }

  Widget _matchDetailBody(BuildContext context, LfMatch m) {
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
                    Row(children: [
                      Expanded(
                          child: Text(
                              'Lost ${m.lostReportId} ↔ Item ${m.inventoryItemId}',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800))),
                      StatusBadge(m.status.wireValue),
                    ]),
                    const Divider(height: 18),
                    InfoRow(label: 'Lost Report', value: m.lostReportId),
                    InfoRow(label: 'Inventory Item', value: m.inventoryItemId),
                    InfoRow(label: 'Owner', value: m.lostOwnerStudentId),
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
                                  height: 1.55))),
                    ],
                  ]))),
          const SizedBox(height: 10),
          _MatchActions(match: m),
        ],
      ),
    );
  }
}

/// A card wrapping one match plus its admin actions, shared by the inventory
/// detail and match detail screens.
Widget _matchCard(BuildContext context, LfMatch m) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Lost ${m.lostReportId}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800))),
            StatusBadge(m.status.wireValue),
          ]),
          const SizedBox(height: 6),
          InfoRow(label: 'Owner', value: m.lostOwnerStudentId),
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
      if (m.status == MatchStatus.proposed)
        GradientButton(
            label: 'Approve Match & Notify Student',
            onPressed: _busy ? null : _approve),
      if (m.status == MatchStatus.approved) _returnQrSection(),
      if (m.status == MatchStatus.completed) ...[
        const _StatusBanner(
            text: 'Return completed — this item is back with its owner.'),
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
                      Row(children: [
                        Expanded(
                            child: OutlineBtn(
                                label: 'Show Full QR',
                                onPressed: () => _showQRDialog(
                                    context,
                                    'Return QR',
                                    txn.token,
                                    'Ask ${txn.intendedStudentId} to scan this code in the app when collecting the item. It expires in 10 minutes.'))),
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
  const _PhotoBox({required this.onImagesChanged, this.polished = false});

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

/// Student scan section: manual token entry plus a camera scan button.
///
/// Both paths call [AppState.scanQrCode], so the Firestore rules are the
/// gate for every write — the camera and the text field are two front doors
/// to the same single-use, intended-student-only token check.
class _QrScanSection extends StatefulWidget {
  final String instruction;
  final VoidCallback onSuccess;
  const _QrScanSection({required this.instruction, required this.onSuccess});

  @override
  State<_QrScanSection> createState() => _QrScanSectionState();
}

class _QrScanSectionState extends State<_QrScanSection> {
  final _codeController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(String token) async {
    if (_busy) return;
    final code = token.trim();
    if (code.isEmpty) {
      _toast(context, 'Please enter or scan the QR code');
      return;
    }
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final outcome = await appState.scanQrCode(code);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, outcome.message);
      if (outcome.success) {
        _codeController.clear();
        widget.onSuccess();
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
    showModalBottomSheet(
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
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  hintText: 'Enter QR code here...',
                  prefixIcon:
                      const Icon(Icons.qr_code_rounded, color: AppTheme.red),
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
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: OutlineBtn(
                        label: 'Scan with Camera',
                        onPressed: _busy ? null : _scanWithCamera)),
                const SizedBox(width: 10),
                Expanded(
                    child: GradientButton(
                        label: _busy ? 'Verifying…' : 'Verify Code',
                        onPressed: _busy
                            ? null
                            : () => _submit(_codeController.text))),
              ]),
            ])));
  }
}

/// Camera scanner bottom sheet. Pops itself and delivers the first raw code
/// it detects exactly once (extra frames are ignored while the caller
/// submits the scan).
class _QrScannerSheet extends StatefulWidget {
  final void Function(String code) onDetect;
  const _QrScannerSheet({required this.onDetect});

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                            'Camera unavailable. Enter the code manually instead.',
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
              const Text('Your report is saved with status: Awaiting Handover',
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
