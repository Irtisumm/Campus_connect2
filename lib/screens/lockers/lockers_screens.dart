import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../widgets/release_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';
import '../../services/app_state.dart';
import '../../services/locker_pricing.dart';

/// Status colour for locker issue badges / icons.
Color _issueColor(String status) {
  switch (status) {
    case 'Reported':
      return AppTheme.goldDark;
    case 'Under Review':
      return const Color(0xFF1565C0);
    case 'Resolved':
      return const Color(0xFF2E7D32);
    default:
      return AppTheme.textMuted;
  }
}

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

/// Locker IDs with an unblock write currently in flight. Guards against a
/// double submit producing two "Locker unblocked" history entries — the
/// service-side guard alone cannot catch it, because both calls read the same
/// stale `Blocked` snapshot before either write lands.
final Set<String> _unblockInFlight = <String>{};

/// Dialog for an admin to unblock a previously blocked locker.
///
/// Shared by the Blocked tab of [AdminLockersListScreen] and the admin locker
/// detail screen, so both entry points enforce the same validation and write
/// the same history. Shows radio-button reasons (matching the block dialog
/// pattern) with an "Other" free-text fallback, then calls
/// [AppState.unblockLocker], which flips the status to 'Available', writes a
/// history entry, and notifies the student if the locker still has a tenant.
void _showUnblockLockerDialog(BuildContext context, Locker lk) {
  // Validation guard: cannot unblock a locker that isn't blocked. This also
  // covers "already Available" and blocks a second unblock of the same locker.
  if (lk.status != 'Blocked') {
    _toast(context, 'Locker is not blocked.');
    return;
  }
  if (_unblockInFlight.contains(lk.id)) {
    _toast(context, 'Unblock already in progress for ${lk.id}.');
    return;
  }
  String? selectedReason;
  final otherController = TextEditingController();
  const reasons = [
    'Maintenance Completed',
    'Locker Repaired',
    'Cleaning Finished',
    'Security Issue Resolved',
    'Administrative Decision',
    'Other',
  ];

  showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.lock_open_rounded, color: Color(0xFF2E7D32), size: 24),
          SizedBox(width: 8),
          Text('Unblock Locker',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unblock locker ${lk.id} and make it available again?',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                const NoticeBox(
                  message:
                      'The locker will become available for new bookings immediately.',
                  borderColor: Color(0xFF2E7D32),
                  bgColor: Color(0x112E7D32),
                  textColor: Color(0xFF1E5A23),
                  icon: Icons.info_outline_rounded,
                ),
                if (lk.studentId != null) ...[
                  const SizedBox(height: 8),
                  NoticeBox(
                    message:
                        'This locker still lists ${lk.studentId} as its tenant. '
                        'They will be notified that it has been reopened.',
                    borderColor: AppTheme.goldDark,
                    bgColor: AppTheme.gold.withOpacity(0.12),
                    textColor: const Color(0xFF7A5B00),
                    icon: Icons.info_outline_rounded,
                  ),
                ],
                const SizedBox(height: 14),
                const Text('Reason for unblocking (required):',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...reasons.map((r) => RadioListTile<String>(
                      value: r,
                      groupValue: selectedReason,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      title: Text(r, style: const TextStyle(fontSize: 13)),
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                    )),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: otherController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Please specify the reason...',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: AppTheme.textMuted),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () async {
              if (selectedReason == null) {
                _toast(ctx, 'Please select a reason for unblocking.');
                return;
              }
              String reason = selectedReason!;
              if (reason == 'Other') {
                final custom = otherController.text.trim();
                if (custom.isEmpty) {
                  _toast(ctx, 'Please specify the reason for "Other".');
                  return;
                }
                reason = custom;
              }
              if (!_unblockInFlight.add(lk.id)) return;
              Navigator.pop(ctx);
              try {
                final ok = await context
                    .read<AppState>()
                    .unblockLocker(lk, reason: reason);
                if (!context.mounted) return;
                _toast(
                    context,
                    ok
                        ? 'Locker ${lk.id} unblocked and available.'
                        : 'Failed to unblock locker. Please try again.');
              } finally {
                _unblockInFlight.remove(lk.id);
              }
            },
            child: const Text('Unblock Locker',
                style: TextStyle(
                    color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}

// ── Screen 28: Locker Hub ────────────────────────────────────────
class LockerHubScreen extends StatefulWidget {
  const LockerHubScreen({super.key});
  @override
  State<LockerHubScreen> createState() => _LockerHubScreenState();
}

class _LockerHubScreenState extends State<LockerHubScreen> {
  late final Stream<List<LockerBooking>> _myBookings;
  late final Stream<List<Locker>> _lockers;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _myBookings = appState.watchMyLockerBookings();
    _lockers = appState.watchLockers();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LockerBooking>>(
      stream: _myBookings,
      builder: (context, bookingsSnap) {
        final myBookings = bookingsSnap.data ?? const <LockerBooking>[];
        final booking = myBookings
            .where((b) => b.status != 'Completed' && b.status != 'Rejected')
            .firstOrNull;
        final hasActiveBooking = myBookings.any((b) =>
            b.status == 'Active' ||
            b.status == 'Pending Pickup' ||
            b.status == 'Waiting Approval');
        return StreamBuilder<List<Locker>>(
          stream: _lockers,
          builder: (context, lockersSnap) {
            final lockers = lockersSnap.data ?? const <Locker>[];
            final availableCount =
                lockers.where((l) => l.status == 'Available').length;
            return Scaffold(
              backgroundColor: Luxe.bg,
              body: SafeArea(
                top: false,
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LockerStatusCard(
                        booking: booking,
                        hasActiveBooking: hasActiveBooking,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'SERVICES',
                        style: Luxe.sectionLabel.copyWith(
                          color: Luxe.inkSoft,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _LockerServiceCard(
                        icon: Icons.grid_view_rounded,
                        title: 'Browse Available Lockers',
                        subtitle: hasActiveBooking
                            ? 'You already have a locker'
                            : '$availableCount available now',
                        isPrimary: true,
                        onTap: () => context.push('/lockers/browse'),
                      ),
                      const SizedBox(height: 12),
                      _LockerServiceCard(
                        icon: Icons.manage_accounts_rounded,
                        title: 'My Locker',
                        subtitle: booking == null
                            ? 'No active booking'
                            : '${booking.lockerId} - ${booking.location}',
                        onTap: () => context.push('/lockers/my-locker'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LockerStatusCard extends StatelessWidget {
  final LockerBooking? booking;
  final bool hasActiveBooking;

  const _LockerStatusCard({
    required this.booking,
    required this.hasActiveBooking,
  });

  @override
  Widget build(BuildContext context) {
    final copy = _LockerStatusCopy.fromBooking(
      booking,
      hasActiveBooking: hasActiveBooking,
    );

    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Luxe.primary.withValues(alpha: 0.16)),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(copy.icon, color: Luxe.primary, size: 25),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Luxe.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  copy.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: Luxe.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _LockerMiniIllustration(),
        ],
      ),
    );
  }
}

class _LockerStatusCopy {
  final String title;
  final String subtitle;
  final IconData icon;

  const _LockerStatusCopy({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  factory _LockerStatusCopy.fromBooking(
    LockerBooking? booking, {
    required bool hasActiveBooking,
  }) {
    if (booking == null) {
      return const _LockerStatusCopy(
        title: 'You don\'t have an active locker.',
        subtitle: 'You can browse and book one below.',
        icon: Icons.info_outline_rounded,
      );
    }

    if (booking.status == 'Waiting Approval') {
      return _LockerStatusCopy(
        title: 'Your locker request is pending.',
        subtitle:
            'We are reviewing ${booking.lockerId}. Check My Locker for updates.',
        icon: Icons.hourglass_top_rounded,
      );
    }

    if (booking.status == 'Pending Pickup') {
      return _LockerStatusCopy(
        title: 'Your locker is ready for pickup.',
        subtitle: '${booking.lockerId} - ${booking.location}',
        icon: Icons.key_rounded,
      );
    }

    if (hasActiveBooking || booking.status == 'Active') {
      return _LockerStatusCopy(
        title: 'You have an active locker.',
        subtitle:
            '${booking.lockerId} is assigned to you. Manage it in My Locker.',
        icon: Icons.check_circle_outline_rounded,
      );
    }

    return _LockerStatusCopy(
      title: 'Your locker booking is in progress.',
      subtitle: 'Check My Locker for the latest update on ${booking.lockerId}.',
      icon: Icons.sync_rounded,
    );
  }
}

class _LockerServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  const _LockerServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final titleColor = isPrimary ? Colors.white : Luxe.ink;
    final subtitleColor =
        isPrimary ? Colors.white.withValues(alpha: 0.88) : Luxe.inkSoft;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 116,
        decoration: BoxDecoration(
          gradient: isPrimary ? Luxe.lostGradient : null,
          color: isPrimary ? null : Luxe.surface,
          borderRadius: radius,
          border: isPrimary
              ? null
              : Border.all(color: Luxe.primary.withValues(alpha: 0.06)),
          boxShadow: isPrimary
              ? Luxe.liftStrong(tint: Luxe.primary)
              : Luxe.lift(tint: Luxe.primary, strength: 0.8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isPrimary)
                const Positioned(
                  right: -4,
                  bottom: -20,
                  child: Opacity(
                    opacity: 0.18,
                    child: _LockerBackdrop(color: Colors.white),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isPrimary
                            ? Colors.white.withValues(alpha: 0.18)
                            : Luxe.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(
                        icon,
                        size: 26,
                        color: isPrimary ? Colors.white : Luxe.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16.5,
                                  height: 1.18,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isPrimary
                            ? Colors.white.withValues(alpha: 0.94)
                            : Luxe.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 25,
                        color: Luxe.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockerMiniIllustration extends StatelessWidget {
  const _LockerMiniIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            top: 3,
            child: _LockerDoor(
              width: 20,
              height: 42,
              color: Luxe.primary.withValues(alpha: 0.14),
              stroke: Luxe.primary.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: _LockerDoor(
              width: 20,
              height: 42,
              color: Luxe.primary.withValues(alpha: 0.08),
              stroke: Luxe.primary.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockerBackdrop extends StatelessWidget {
  final Color color;

  const _LockerBackdrop({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _LockerDoor(
          width: 50,
          height: 96,
          color: color.withValues(alpha: 0.10),
          stroke: color.withValues(alpha: 0.24),
        ),
        const SizedBox(width: 5),
        _LockerDoor(
          width: 50,
          height: 96,
          color: color.withValues(alpha: 0.07),
          stroke: color.withValues(alpha: 0.20),
        ),
      ],
    );
  }
}

class _LockerDoor extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final Color stroke;

  const _LockerDoor({
    required this.width,
    required this.height,
    required this.color,
    required this.stroke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: stroke, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 11,
          decoration: BoxDecoration(
            color: stroke,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

// ── Screen 29: Browse / Available Lockers ────────────────────────
class BrowseLockersScreen extends StatefulWidget {
  const BrowseLockersScreen({super.key});
  @override
  State<BrowseLockersScreen> createState() => _BrowseLockersScreenState();
}

class _BrowseLockersScreenState extends State<BrowseLockersScreen> {
  late final Stream<List<LockerBooking>> _myBookings;
  late final Stream<List<Locker>> _lockers;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _myBookings = appState.watchMyLockerBookings();
    _lockers = appState.watchLockers();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LockerBooking>>(
      stream: _myBookings,
      builder: (context, bookingsSnap) {
        final myBookings = bookingsSnap.data ?? const <LockerBooking>[];
        final hasActiveBooking = myBookings.any((b) =>
            b.status == 'Active' ||
            b.status == 'Pending Pickup' ||
            b.status == 'Waiting Approval');
        return StreamBuilder<List<Locker>>(
          stream: _lockers,
          builder: (context, lockersSnap) {
            final lockers = lockersSnap.data ?? const <Locker>[];
            final groupedLockers = <String, List<Locker>>{};
            for (final locker in lockers) {
              groupedLockers
                  .putIfAbsent(locker.location, () => <Locker>[])
                  .add(locker);
            }
            final blockEntries = groupedLockers.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));
            final monthlyRent =
                lockers.isNotEmpty ? lockers.first.monthlyRent : 10.0;
            final deposit = lockers.isNotEmpty ? lockers.first.deposit : 100.0;
            return Scaffold(
              backgroundColor: Luxe.bg,
              body: SafeArea(
                top: false,
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AvailableLockerInfoCard(
                        isWarning: hasActiveBooking,
                        title: hasActiveBooking
                            ? 'You already have an active locker.'
                            : 'Locker rentals: 2-12 months,',
                        subtitle: hasActiveBooking
                            ? 'Release your current locker before booking another.'
                            : 'RM${monthlyRent.toStringAsFixed(0)}/month + RM${deposit.toStringAsFixed(0)} refundable deposit.',
                        footer: hasActiveBooking
                            ? 'Only one locker per student is allowed.'
                            : 'Tap an available locker to book.',
                      ),
                      const SizedBox(height: 22),
                      if (blockEntries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No lockers are available right now.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Luxe.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ...blockEntries.map((entry) {
                        final blockLockers = [...entry.value]
                          ..sort((a, b) => a.id.compareTo(b.id));
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _AvailableLockerBlockHeader(entry.key),
                              const SizedBox(height: 10),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: blockLockers.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  mainAxisExtent: 116,
                                ),
                                itemBuilder: (context, index) {
                                  final locker = blockLockers[index];
                                  final isAvailable =
                                      locker.status == 'Available';
                                  final canBook =
                                      isAvailable && !hasActiveBooking;
                                  final onTap = canBook
                                      ? () => context
                                          .push('/lockers/detail/${locker.id}')
                                      : (isAvailable && hasActiveBooking
                                          ? () => _toast(
                                                context,
                                                'You already have a locker. Max 1 per student.',
                                              )
                                          : null);
                                  return _AvailableLockerCard(
                                    code: locker.id.split('-').last,
                                    lockType: locker.lockType == 'digital'
                                        ? 'D'
                                        : 'K',
                                    isAvailable: isAvailable,
                                    onTap: onTap,
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              const _AvailableLockerLegend(),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AvailableLockerInfoCard extends StatelessWidget {
  final bool isWarning;
  final String title;
  final String subtitle;
  final String footer;

  const _AvailableLockerInfoCard({
    required this.isWarning,
    required this.title,
    required this.subtitle,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isWarning ? const Color(0xFFE38A22) : Luxe.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 136),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: Luxe.lift(tint: accent, strength: 0.7),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWarning ? Icons.warning_amber_rounded : Icons.info_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Luxe.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: Luxe.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: Luxe.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isWarning) const _AvailableLockerIllustration(),
        ],
      ),
    );
  }
}

class _AvailableLockerIllustration extends StatelessWidget {
  const _AvailableLockerIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 78,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _LockerDoor(
                  width: 24,
                  height: 68,
                  color: Luxe.primary.withValues(alpha: 0.08),
                  stroke: Luxe.primary.withValues(alpha: 0.22),
                ),
                const SizedBox(width: 3),
                _LockerDoor(
                  width: 24,
                  height: 68,
                  color: Luxe.primary.withValues(alpha: 0.12),
                  stroke: Luxe.primary.withValues(alpha: 0.28),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.local_florist_outlined,
              color: Color(0xFFE9899C),
              size: 25,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableLockerBlockHeader extends StatelessWidget {
  final String title;

  const _AvailableLockerBlockHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Luxe.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.apartment_rounded,
            color: Luxe.primary,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16.5,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: Luxe.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _AvailableLockerCard extends StatelessWidget {
  final String code;
  final String lockType;
  final bool isAvailable;
  final VoidCallback? onTap;

  const _AvailableLockerCard({
    required this.code,
    required this.lockType,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isAvailable ? const Color(0xFF3FAE52) : Luxe.primary;
    final radius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: Luxe.surface,
          borderRadius: radius,
          border: Border.all(color: statusColor.withValues(alpha: 0.08)),
          boxShadow: Luxe.lift(tint: statusColor, strength: 0.7),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.28),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isAvailable
                          ? Icons.lock_open_rounded
                          : Icons.lock_rounded,
                      color: Luxe.primary,
                      size: 24,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      code,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Luxe.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lockType,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Luxe.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailableLockerLegend extends StatelessWidget {
  const _AvailableLockerLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: const [
        _AvailableLockerLegendItem(
          color: Color(0xFF3FAE52),
          label: 'Available',
        ),
        _AvailableLockerLegendItem(
          color: Luxe.primary,
          label: 'Booked',
        ),
        Text(
          'D = Digital Lock',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Luxe.inkSoft,
          ),
        ),
        Text(
          'K = Key Lock',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Luxe.inkSoft,
          ),
        ),
      ],
    );
  }
}

class _AvailableLockerLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _AvailableLockerLegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 5),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Luxe.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ── Screen 30: Locker Booking (with duration picker + pricing) ───
class LockerBookingScreen extends StatefulWidget {
  final String id;
  const LockerBookingScreen({super.key, required this.id});
  @override
  State<LockerBookingScreen> createState() => _LockerBookingScreenState();
}

class _LockerBookingScreenState extends State<LockerBookingScreen> {
  int _durationMonths = 6;
  bool _agreed = false;
  bool _submitting = false;
  late final Stream<List<LockerBooking>> _myBookings;
  late final Stream<Locker?> _locker;

  // Pricing is derived from the Locker document (Firestore) via LockerPricing.
  // The defaults below are only used until the first locker snapshot arrives.
  LockerPricing _pricing = const LockerPricing(
    deposit: 100.0,
    monthlyRent: 10.0,
    durationMonths: 6,
  );

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _myBookings = appState.watchMyLockerBookings();
    _locker = appState.watchLocker(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LockerBooking>>(
      stream: _myBookings,
      builder: (context, bookingsSnap) {
        final myBookings = bookingsSnap.data ?? const <LockerBooking>[];
        final hasActiveBooking = myBookings.any((b) =>
            b.status == 'Active' ||
            b.status == 'Pending Pickup' ||
            b.status == 'Waiting Approval');
        return StreamBuilder<Locker?>(
          stream: _locker,
          builder: (context, lockerSnap) {
            final lk = lockerSnap.data ??
                const Locker(
                    id: '',
                    location: '',
                    status: '',
                    studentId: null,
                    endDate: '',
                    daysLeft: null);

            // Sync pricing from the locker document whenever it changes.
            if (lk.id.isNotEmpty) {
              _pricing = LockerPricing.fromLocker(lk, _durationMonths);
            }

            if (lk.id.isEmpty) {
              return Scaffold(
                appBar: _appBar('Book Locker', context),
                body: const EmptyState(
                    title: 'Locker Not Found',
                    subtitle: 'This locker does not exist.',
                    icon: Icons.error_outline_rounded),
              );
            }

            if (hasActiveBooking) {
              return Scaffold(
                appBar: _appBar('Book Locker', context),
                body: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const EmptyState(
                          title: 'Already Have a Locker',
                          subtitle:
                              'You can only have 1 locker at a time. Release your current locker first.',
                          icon: Icons.lock_rounded),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: OutlineBtn(
                              label: 'Go to My Locker',
                              onPressed: () =>
                                  context.go('/lockers/my-locker'))),
                    ]),
              );
            }

            if (lk.status != 'Available') {
              return Scaffold(
                appBar: _appBar('Book Locker', context),
                body: const EmptyState(
                    title: 'Locker Unavailable',
                    subtitle: 'This locker is no longer available for booking.',
                    icon: Icons.lock_outline_rounded),
              );
            }

            return Scaffold(
              appBar: _appBar('Book Locker', context),
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    // Locker info card
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              Row(children: [
                                Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                        gradient: AppTheme.primaryGradient,
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    child: const Icon(Icons.lock_rounded,
                                        color: Colors.white, size: 28)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(lk.id,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800)),
                                      Text(lk.location,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textMuted)),
                                      const SizedBox(height: 6),
                                      Row(children: [
                                        StatusBadge(lk.status),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: lk.lockType == 'digital'
                                                ? AppTheme.red.withOpacity(0.1)
                                                : AppTheme.gold
                                                    .withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                    lk.lockType == 'digital'
                                                        ? Icons.dialpad_rounded
                                                        : Icons.key_rounded,
                                                    size: 11,
                                                    color: lk.lockType ==
                                                            'digital'
                                                        ? AppTheme.red
                                                        : AppTheme.goldDark),
                                                const SizedBox(width: 4),
                                                Text(
                                                    lk.lockType == 'digital'
                                                        ? 'Digital Lock'
                                                        : 'Key Lock',
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: lk.lockType ==
                                                                'digital'
                                                            ? AppTheme.red
                                                            : AppTheme
                                                                .goldDark)),
                                              ]),
                                        ),
                                      ]),
                                    ])),
                              ]),
                            ]))).animate().fadeIn(delay: 50.ms),

                    const SizedBox(height: 12),

                    // Duration picker
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Select Duration',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textPrimary)),
                                  const SizedBox(height: 4),
                                  const Text(
                                      'Choose your rental period (2-12 months)',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted)),
                                  const SizedBox(height: 14),
                                  Row(children: [
                                    Text('$_durationMonths months',
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.red)),
                                    const Spacer(),
                                    _DurationBtn(
                                        icon: Icons.remove,
                                        onTap: _durationMonths > 2
                                            ? () => setState(
                                                () => _durationMonths--)
                                            : null),
                                    const SizedBox(width: 8),
                                    _DurationBtn(
                                        icon: Icons.add,
                                        onTap: _durationMonths < 12
                                            ? () => setState(
                                                () => _durationMonths++)
                                            : null),
                                  ]),
                                  const SizedBox(height: 10),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: AppTheme.red,
                                      inactiveTrackColor:
                                          AppTheme.red.withOpacity(0.15),
                                      thumbColor: AppTheme.red,
                                      overlayColor:
                                          AppTheme.red.withOpacity(0.1),
                                      trackHeight: 4,
                                    ),
                                    child: Slider(
                                      value: _durationMonths.toDouble(),
                                      min: 2,
                                      max: 12,
                                      divisions: 10,
                                      label: '$_durationMonths months',
                                      onChanged: (v) => setState(
                                          () => _durationMonths = v.round()),
                                    ),
                                  ),
                                  const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('2 months',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.textMuted)),
                                        Text('12 months',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.textMuted)),
                                      ]),
                                ]))).animate().fadeIn(delay: 100.ms),

                    const SizedBox(height: 12),

                    // Pricing breakdown — clearly distinguishes total rental cost,
                    // refundable deposit, and the full amount due today.
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pricing Breakdown',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textPrimary)),
                                  const Divider(height: 20),
                                  _PriceRow('Monthly Rent',
                                      'RM${_pricing.monthlyRent.toStringAsFixed(0)}/month'),
                                  _PriceRow('Duration',
                                      '${_pricing.durationMonths} months'),
                                  _PriceRow('Total Rental Cost',
                                      'RM${_pricing.totalRentalCost.toStringAsFixed(0)}'),
                                  const Divider(height: 16),
                                  _PriceRow('Deposit (refundable)',
                                      'RM${_pricing.deposit.toStringAsFixed(0)}',
                                      isBold: true),
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.primaryGradient,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Amount Due Today',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white)),
                                          Text(
                                              'RM${_pricing.amountDueToday.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white)),
                                        ]),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                      '* Full rental amount plus deposit is paid upfront. Deposit is refundable upon locker return.',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textMuted,
                                          fontStyle: FontStyle.italic)),
                                ]))).animate().fadeIn(delay: 150.ms),

                    const SizedBox(height: 12),

                    // Lock type info
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(
                                        lk.lockType == 'digital'
                                            ? Icons.dialpad_rounded
                                            : Icons.key_rounded,
                                        color: AppTheme.red,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                        lk.lockType == 'digital'
                                            ? 'Digital Lock Info'
                                            : 'Key Lock Info',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textPrimary)),
                                  ]),
                                  const SizedBox(height: 10),
                                  if (lk.lockType == 'digital')
                                    NoticeBox(
                                      message:
                                          'After payment, your booking will be reviewed by admin. Once approved, your digital lock password will appear under "My Locker". You can access it anytime.',
                                      borderColor: AppTheme.red,
                                      bgColor: AppTheme.red.withOpacity(0.06),
                                      textColor: AppTheme.textSecondary,
                                      icon: Icons.smartphone_rounded,
                                    )
                                  else
                                    NoticeBox(
                                      message:
                                          'After payment, your booking will be reviewed by admin. Once approved, please visit the Inventory Manager at Facilities Office, Block A Level 1, to collect your key within 3 working days.',
                                      borderColor: AppTheme.goldDark,
                                      bgColor: AppTheme.gold.withOpacity(0.12),
                                      textColor: const Color(0xFF7A5B00),
                                      icon: Icons.key_rounded,
                                    ),
                                ]))).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 12),

                    // Agreement checkbox
                    Card(
                        child: InkWell(
                      onTap: () => setState(() => _agreed = !_agreed),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Checkbox(
                              value: _agreed,
                              onChanged: (v) =>
                                  setState(() => _agreed = v ?? false),
                              activeColor: AppTheme.red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                              'I agree to the Locker Rental Policy and understand the deposit of RM${_pricing.deposit.toStringAsFixed(0)} is refundable upon proper locker return.',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  height: 1.4),
                            )),
                          ])),
                    )).animate().fadeIn(delay: 250.ms),

                    const SizedBox(height: 16),

                    // Action buttons
                    GradientButton(
                      label:
                          'Confirm & Pay RM${_pricing.amountDueToday.toStringAsFixed(0)}',
                      onPressed: (_agreed && !_submitting)
                          ? () async {
                              setState(() => _submitting = true);
                              // Step 1: Show payment summary dialog.
                              if (!context.mounted) return;
                              final proceed = await _showPaymentSummaryDialog(
                                  context, lk, _durationMonths);
                              if (!proceed) {
                                if (mounted)
                                  setState(() => _submitting = false);
                                return;
                              }
                              // Step 2: Show demo card payment dialog.
                              if (!context.mounted) return;
                              final paymentResult =
                                  await _showCardPaymentDialog(
                                      context, lk, _durationMonths);
                              if (paymentResult == null ||
                                  !paymentResult.isSuccess) {
                                if (mounted)
                                  setState(() => _submitting = false);
                                if (paymentResult != null) {
                                  _toast(
                                      context,
                                      paymentResult.error ??
                                          'Payment failed. Please try again.');
                                }
                                return;
                              }
                              // Step 3: Create the booking with status 'Waiting Approval'.
                              final result = await context
                                  .read<AppState>()
                                  .completeLockerBooking(lk, _durationMonths,
                                      payment: paymentResult.payment);
                              if (!context.mounted) return;
                              if (!result.isSuccess) {
                                setState(() => _submitting = false);
                                _toast(
                                    context,
                                    result.error ??
                                        'Booking failed. Please try again.');
                                return;
                              }
                              // Step 4: Show success dialog.
                              _showBookingSubmittedDialog(
                                  context, lk, paymentResult.payment);
                            }
                          : null,
                    ),
                    const SizedBox(height: 10),
                    OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
                  ])),
            );
          },
        );
      },
    );
  }

  /// Step 1: Payment summary dialog — shows the full pricing breakdown
  /// (total rental cost, refundable deposit, amount due today). Returns
  /// `true` if the user taps "Pay Now", `false` if they cancel.
  Future<bool> _showPaymentSummaryDialog(
      BuildContext context, Locker locker, int durationMonths) async {
    final pricing = LockerPricing.fromLocker(locker, durationMonths);
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.receipt_long_rounded, color: AppTheme.red, size: 28),
              SizedBox(width: 10),
              Text('Payment Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PaymentLine(label: 'Locker', value: locker.location),
                  _PaymentLine(
                      label: 'Duration',
                      value: '${pricing.durationMonths} month(s)'),
                  _PaymentLine(
                      label: 'Total Rental Cost',
                      value: 'RM${pricing.totalRentalCost.toStringAsFixed(0)}'),
                  const Divider(height: 20),
                  _PaymentLine(
                      label: 'Refundable Deposit',
                      value: 'RM${pricing.deposit.toStringAsFixed(0)}'),
                  _PaymentLine(
                      label: 'Amount Due Today',
                      value: 'RM${pricing.amountDueToday.toStringAsFixed(0)}',
                      bold: true),
                  const SizedBox(height: 8),
                  const Text(
                      '* Full rental amount plus deposit is paid upfront. Deposit is refundable upon locker return.',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontStyle: FontStyle.italic)),
                ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600)),
              ),
              GradientButton(
                label: 'Pay Now',
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Step 2: Demo card payment dialog — professional card payment form with
  /// cardholder name, card number (auto-spaced every 4 digits), expiry
  /// month/year dropdowns, CVV, country dropdown, and ZIP. Runs the demo
  /// payment gateway and returns the [PaymentResult]. Returns `null` if the
  /// user cancels.
  ///
  /// The dialog is fully responsive:
  /// - Uses [LayoutBuilder] + [MediaQuery] to adapt to screen size.
  /// - Body is wrapped in [SingleChildScrollView] so it scrolls when the
  ///   keyboard is open.
  /// - The Month / Year / CVV row uses [Expanded] + fixed-width [SizedBox]
  ///   so it never overflows.
  /// - Error messages use reserved space (fixed-height containers) so the
  ///   layout never jumps when validation appears.
  /// - The Cancel / Pay action bar is always visible at the bottom.
  Future<PaymentResult?> _showCardPaymentDialog(
      BuildContext context, Locker locker, int durationMonths) async {
    final pricing = LockerPricing.fromLocker(locker, durationMonths);
    final nameController = TextEditingController();
    final cardController = TextEditingController();
    final cvvController = TextEditingController();
    final zipController = TextEditingController();
    String? expiryMonth;
    String? expiryYear;
    String country = 'Malaysia';
    String cardType = '';
    String? cardError;
    String? nameError;
    String? cvvError;
    String? expiryError;
    String? zipError;
    bool processing = false;
    bool submitting = false;

    const countries = [
      'Malaysia',
      'Singapore',
      'Indonesia',
      'Thailand',
      'Philippines',
      'Vietnam',
      'Brunei',
      'Cambodia',
      'Myanmar',
      'Laos',
      'Other',
    ];

    // Format card number: strip non-digits, insert space every 4 digits,
    // max 16 digits (19 chars with spaces).
    String formatCardNumber(String input) {
      final digits = input.replaceAll(RegExp(r'\D'), '');
      if (digits.length > 16) return cardController.text;
      final buffer = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        if (i > 0 && i % 4 == 0) buffer.write(' ');
        buffer.write(digits[i]);
      }
      return buffer.toString();
    }

    void validateCardNumber() {
      final digits = cardController.text.replaceAll(RegExp(r'\s'), '');
      if (digits.isEmpty) {
        cardError = null; // don't show error on empty
      } else if (digits.length != 16) {
        cardError = 'Card number must be exactly 16 digits';
      } else {
        cardError = null;
      }
    }

    void validateName() {
      final v = nameController.text.trim();
      if (v.isEmpty) {
        nameError = null;
      } else if (v.length < 3) {
        nameError = 'Name must be at least 3 characters';
      } else if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(v)) {
        nameError = 'Name must contain only letters and spaces';
      } else {
        nameError = null;
      }
    }

    void validateCvv() {
      final v = cvvController.text;
      if (v.isEmpty) {
        cvvError = null;
      } else if (!RegExp(r'^\d{3}$').hasMatch(v)) {
        cvvError = 'CVV must be exactly 3 digits';
      } else {
        cvvError = null;
      }
    }

    void validateExpiry() {
      if (expiryMonth == null || expiryYear == null) {
        expiryError = null;
        return;
      }
      final now = DateTime.now();
      final year = int.parse(expiryYear!);
      final month = int.parse(expiryMonth!);
      if (year < now.year || (year == now.year && month < now.month)) {
        expiryError = 'Card has expired';
      } else {
        expiryError = null;
      }
    }

    void validateZip() {
      final v = zipController.text;
      if (v.isEmpty) {
        zipError = null;
      } else if (!RegExp(r'^\d{4,10}$').hasMatch(v)) {
        zipError = '4–10 digits required';
      } else {
        zipError = null;
      }
    }

    bool isFormValid() =>
        cardError == null &&
        nameError == null &&
        cvvError == null &&
        expiryError == null &&
        zipError == null &&
        cardController.text.replaceAll(RegExp(r'\s'), '').length == 16 &&
        nameController.text.trim().length >= 3 &&
        RegExp(r'^\d{3}$').hasMatch(cvvController.text) &&
        expiryMonth != null &&
        expiryYear != null;

    // Reserved-height error text widget — occupies a fixed slot so the
    // layout never jumps when an error appears or disappears.
    Widget reservedError(String? error, {double height = 16}) {
      return SizedBox(
        height: height,
        child: error != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(error,
                    style: const TextStyle(fontSize: 11, color: Colors.red)),
              )
            : const SizedBox.shrink(),
      );
    }

    return await showDialog<PaymentResult?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Run initial validation so the Pay button state is correct on open.
          if (!submitting) {
            validateCardNumber();
            validateName();
            validateCvv();
            validateExpiry();
            validateZip();
          }

          final currentYear = DateTime.now().year;

          return LayoutBuilder(
            builder: (context, constraints) {
              final dialogMaxWidth = constraints.maxWidth < 400
                  ? constraints.maxWidth * 0.95
                  : 380.0;

              return Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: dialogMaxWidth,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Title ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                        child: Row(children: [
                          const Icon(Icons.credit_card_rounded,
                              color: AppTheme.red, size: 28),
                          const SizedBox(width: 10),
                          const Text('Card Payment',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          if (!processing)
                            IconButton(
                              icon: const Icon(Icons.close, size: 22),
                              color: AppTheme.textMuted,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ]),
                      ),
                      const Divider(height: 1),

                      // ── Scrollable body ────────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Amount banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppTheme.red.withOpacity(0.2)),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Amount Due',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary)),
                                    Text(
                                        'RM${pricing.amountDueToday.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.red)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Cardholder Name
                              TextField(
                                controller: nameController,
                                keyboardType: TextInputType.name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Cardholder Name',
                                  hintText: 'e.g. Ahmad Ali',
                                  prefixIcon: Icon(Icons.person_outline,
                                      color: AppTheme.red),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (_) => setDialogState(validateName),
                              ),
                              reservedError(nameError),
                              const SizedBox(height: 8),

                              // Card Number
                              TextField(
                                controller: cardController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(19),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Card Number',
                                  hintText: '4242 4242 4242 4242',
                                  prefixIcon: const Icon(Icons.credit_card,
                                      color: AppTheme.red),
                                  suffixIcon: cardType == 'Visa'
                                      ? const Icon(Icons.credit_card,
                                          color: Color(0xFF1A1F71), size: 28)
                                      : cardType == 'Mastercard'
                                          ? const Icon(Icons.credit_card,
                                              color: Color(0xFFEB001B),
                                              size: 28)
                                          : null,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final formatted = formatCardNumber(value);
                                  setDialogState(() {
                                    if (formatted != value) {
                                      cardController.value = TextEditingValue(
                                        text: formatted,
                                        selection: TextSelection.collapsed(
                                            offset: formatted.length),
                                      );
                                    }
                                    final digits =
                                        formatted.replaceAll(RegExp(r'\s'), '');
                                    cardType = digits.startsWith('4')
                                        ? 'Visa'
                                        : digits.startsWith('5')
                                            ? 'Mastercard'
                                            : '';
                                    validateCardNumber();
                                  });
                                },
                              ),
                              reservedError(cardError),
                              const SizedBox(height: 8),

                              // Expiry Month / Year / CVV — responsive row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Expiry Month
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          value: expiryMonth,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Month',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                            isDense: true,
                                          ),
                                          items: List.generate(
                                                  12,
                                                  (i) => (i + 1)
                                                      .toString()
                                                      .padLeft(2, '0'))
                                              .map((m) => DropdownMenuItem(
                                                  value: m, child: Text(m)))
                                              .toList(),
                                          onChanged: (v) => setDialogState(() {
                                            expiryMonth = v;
                                            validateExpiry();
                                          }),
                                        ),
                                        reservedError(null, height: 16),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Expiry Year
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          value: expiryYear,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Year',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                            isDense: true,
                                          ),
                                          items: List.generate(
                                                  16,
                                                  (i) => (currentYear + i)
                                                      .toString())
                                              .map((y) => DropdownMenuItem(
                                                  value: y, child: Text(y)))
                                              .toList(),
                                          onChanged: (v) => setDialogState(() {
                                            expiryYear = v;
                                            validateExpiry();
                                          }),
                                        ),
                                        reservedError(expiryError, height: 16),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // CVV — fixed width
                                  SizedBox(
                                    width: 80,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TextField(
                                          controller: cvvController,
                                          keyboardType: TextInputType.number,
                                          obscureText: true,
                                          textInputAction: TextInputAction.next,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(3),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'CVV',
                                            hintText: '123',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                            isDense: true,
                                          ),
                                          onChanged: (_) =>
                                              setDialogState(validateCvv),
                                        ),
                                        reservedError(cvvError, height: 16),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Country
                              DropdownButtonFormField<String>(
                                value: country,
                                decoration: const InputDecoration(
                                  labelText: 'Country',
                                  prefixIcon:
                                      Icon(Icons.public, color: AppTheme.red),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: countries
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (v) => setDialogState(
                                    () => country = v ?? 'Malaysia'),
                              ),
                              reservedError(null, height: 16),
                              const SizedBox(height: 8),

                              // ZIP / Postal Code
                              TextField(
                                controller: zipController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'ZIP / Postal Code',
                                  hintText: 'e.g. 50480',
                                  prefixIcon: Icon(Icons.location_on_outlined,
                                      color: AppTheme.red),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (_) => setDialogState(validateZip),
                              ),
                              reservedError(zipError),
                              const SizedBox(height: 12),

                              // Demo gateway info
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.gold.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppTheme.gold.withOpacity(0.3)),
                                ),
                                child: const Row(children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: AppTheme.goldDark),
                                  SizedBox(width: 6),
                                  Expanded(
                                      child: Text(
                                    'Demo gateway. Use 4242 4242 4242 4242 for success.',
                                    style: TextStyle(
                                        fontSize: 10, color: AppTheme.goldDark),
                                  )),
                                ]),
                              ),

                              if (processing) ...[
                                const SizedBox(height: 16),
                                const Center(
                                    child: CircularProgressIndicator(
                                        color: AppTheme.red)),
                                const SizedBox(height: 6),
                                const Center(
                                    child: Text('Processing payment...',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted))),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // ── Sticky action bar ──────────────────────────
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Row(
                          children: [
                            if (!processing)
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, null),
                                  child: const Text('Cancel',
                                      style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            if (!processing) const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: GradientButton(
                                label: processing
                                    ? 'Processing...'
                                    : 'Pay RM${pricing.amountDueToday.toStringAsFixed(0)}',
                                onPressed: isFormValid() && !processing
                                    ? () async {
                                        setDialogState(() {
                                          submitting = true;
                                          processing = true;
                                        });
                                        final result = await context
                                            .read<AppState>()
                                            .processLockerPayment(
                                              cardNumber: cardController.text,
                                              cardCvv: cvvController.text,
                                              locker: locker,
                                              durationMonths: durationMonths,
                                            );
                                        if (!ctx.mounted) return;
                                        Navigator.pop(dialogContext, result);
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Step 4: Payment success screen — professional receipt showing
  /// Transaction ID, Receipt Number, Amount Paid, Locker ID, and Booking
  /// Status. The booking has already been created with status
  /// 'Waiting Approval'.
  void _showBookingSubmittedDialog(
      BuildContext context, Locker locker, Payment? payment) {
    final pricing = LockerPricing.fromLocker(locker, _durationMonths);
    final txnId = payment?.transactionId ?? '—';
    final receipt = payment?.receiptNumber ?? '—';
    final amount = payment != null
        ? 'RM${payment.amount.toStringAsFixed(0)}'
        : 'RM${pricing.amountDueToday.toStringAsFixed(0)}';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.red, size: 28),
          SizedBox(width: 10),
          Text('Payment Successful',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text(
                  'Your payment has been received and your booking is now pending admin approval.',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.creamLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.red.withOpacity(0.15)),
                ),
                child: Column(children: [
                  InfoRow(label: 'Transaction ID', value: txnId),
                  InfoRow(label: 'Receipt Number', value: receipt),
                  InfoRow(label: 'Amount Paid', value: amount),
                  InfoRow(label: 'Locker ID', value: locker.id),
                  InfoRow(
                      label: 'Booking Status',
                      value: 'Waiting for Admin Approval'),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: AppTheme.goldDark, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    locker.lockType == 'digital'
                        ? 'Once approved, your digital lock code will appear in "My Locker".'
                        : 'Once approved, collect your key at Facilities Office, Block A Level 1.',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.goldDark, height: 1.4),
                  )),
                ]),
              ),
            ])),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/lockers');
            },
            child: const Text('Got it!',
                style: TextStyle(
                    color: AppTheme.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

/// Small helper widget for payment summary line items.
class _PaymentLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _PaymentLine(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold ? AppTheme.textPrimary : AppTheme.textSecondary,
            )),
        Text(value,
            style: TextStyle(
              fontSize: bold ? 17 : 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? AppTheme.red : AppTheme.textPrimary,
            )),
      ]),
    );
  }
}

// ── Screen 31: My Locker ─────────────────────────────────────────
class MyLockerScreen extends StatefulWidget {
  const MyLockerScreen({super.key});
  @override
  State<MyLockerScreen> createState() => _MyLockerScreenState();
}

class _MyLockerScreenState extends State<MyLockerScreen> {
  late final Stream<List<LockerBooking>> _myBookings;

  @override
  void initState() {
    super.initState();
    _myBookings = context.read<AppState>().watchMyLockerBookings();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LockerBooking>>(
      stream: _myBookings,
      builder: (context, bookingsSnap) {
        final myBookings = bookingsSnap.data ?? const <LockerBooking>[];
        final booking = myBookings
            .where((b) => b.status != 'Completed' && b.status != 'Rejected')
            .firstOrNull;
        if (booking == null) {
          return Scaffold(
            appBar: _appBar('My Locker', context),
            body:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const EmptyState(
                  title: 'No Active Booking',
                  subtitle:
                      'You don\'t have a locker. Browse available lockers to book one.',
                  icon: Icons.lock_open_rounded),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: GradientButton(
                      label: 'Browse Lockers',
                      onPressed: () => context.push('/lockers/browse'))),
            ]),
          );
        }

        // Join with the locker doc for lock type + digital code.
        return StreamBuilder<Locker?>(
          stream: context.read<AppState>().watchLocker(booking.lockerId),
          builder: (context, lockerSnap) {
            // Wait for the real locker document instead of falling back to a
            // temporary default Locker, so lock type and digital code never
            // render placeholder values.
            if (lockerSnap.connectionState == ConnectionState.waiting) {
              return Scaffold(
                appBar: _appBar('My Locker', context),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (lockerSnap.hasError) {
              return Scaffold(
                appBar: _appBar('My Locker', context),
                body: const EmptyState(
                    title: 'Locker Unavailable',
                    subtitle: 'Could not load locker details. Pull to retry.',
                    icon: Icons.error_outline_rounded),
              );
            }
            final locker = lockerSnap.data;
            if (locker == null) {
              return Scaffold(
                appBar: _appBar('My Locker', context),
                body: const EmptyState(
                    title: 'Locker Not Found',
                    subtitle: 'This locker no longer exists.',
                    icon: Icons.error_outline_rounded),
              );
            }
            final isKeyLocker = locker.lockType == 'key';
            final hasReleaseFlow = booking.releaseStatus != null ||
                booking.status == 'Release Requested';
            final releaseStatus = booking.releaseStatus ??
                (booking.status == 'Release Requested' ? 'Requested' : null);
            final bookingPricing = LockerPricing.fromBooking(booking);

            return Scaffold(
              appBar: _appBar('My Locker', context),
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main booking card
                        Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppTheme.red.withOpacity(0.3),
                                          blurRadius: 20,
                                          offset: const Offset(0, 6))
                                    ]),
                                child:
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Row(children: [
                                        const Icon(Icons.lock_rounded,
                                            color: Colors.white, size: 28),
                                        const SizedBox(width: 12),
                                        Text(booking.lockerId,
                                            style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white))
                                      ]),
                                      const SizedBox(height: 6),
                                      Text(booking.location,
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.85))),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        _PricePill(
                                            '${booking.durationMonths} months'),
                                        const SizedBox(width: 8),
                                        _PricePill(locker.lockType == 'digital'
                                            ? 'Digital Lock'
                                            : 'Key Lock'),
                                        const SizedBox(width: 8),
                                        _PricePill(booking.status),
                                      ]),
                                      const SizedBox(height: 14),
                                      Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _StatW('Start',
                                                fmtDate(booking.startDate)),
                                            _StatW('End',
                                                fmtDate(booking.endDate)),
                                            _StatW('Status', booking.status),
                                            CountdownBadge(booking.daysLeft),
                                          ]),
                                    ]))
                            .animate()
                            .fadeIn(delay: 50.ms)
                            .slideY(begin: 0.15),

                        // Waiting Approval banner — shown before admin approves.
                        if (booking.status == 'Waiting Approval') ...[
                          const SectionLabel('Approval Pending'),
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(children: [
                                    const Row(children: [
                                      Icon(Icons.hourglass_top_rounded,
                                          color: AppTheme.goldDark, size: 22),
                                      SizedBox(width: 10),
                                      Expanded(
                                          child: Text('Awaiting Admin Approval',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w700))),
                                    ]),
                                    const SizedBox(height: 10),
                                    Text(
                                      locker.lockType == 'digital'
                                          ? 'Your payment has been received. Once an admin approves your booking, your digital lock code will appear here.'
                                          : 'Your payment has been received. Once an admin approves your booking, you can collect your key at the Facilities Office.',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                          height: 1.4),
                                    ),
                                  ]))).animate().fadeIn(delay: 100.ms),
                        ],

                        // Digital lock code section — only visible after admin approval
                        // (status == 'Active'). The code lives ONLY on the student-owned
                        // booking document (`booking.digitalCode`), which Firestore rules
                        // scope to its owner. It is never stored on, or read from, the
                        // world-readable locker document.
                        //
                        // The code STAYS visible for the whole time a release request is
                        // pending, so the student can keep opening their locker right up
                        // until the admin officially approves the release:
                        //
                        //   releaseStatus == null / 'Requested' / 'Pending Approval' -> shown
                        //   releaseStatus == 'Approved' / 'Completed'                -> hidden
                        //
                        // `requestLockerRelease` also flips booking.status to
                        // 'Release Requested', so that status must be accepted here too —
                        // testing for 'Active' alone is what previously made the code
                        // vanish the instant the student submitted the request.
                        if (locker.lockType == 'digital' &&
                            (booking.status == 'Active' ||
                                booking.status == 'Release Requested') &&
                            booking.digitalCode != null &&
                            (booking.releaseStatus == null ||
                                booking.releaseStatus == 'Requested' ||
                                booking.releaseStatus ==
                                    'Pending Approval')) ...[
                          const SectionLabel('Lock Password'),
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(children: [
                                    const Row(children: [
                                      Icon(Icons.dialpad_rounded,
                                          color: AppTheme.red, size: 22),
                                      SizedBox(width: 10),
                                      Expanded(
                                          child: Text('Digital Lock Code',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w700))),
                                    ]),
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color:
                                                AppTheme.red.withOpacity(0.2)),
                                      ),
                                      child: Text(booking.digitalCode!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.red,
                                              letterSpacing: 8)),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Use this code to unlock your locker',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                  ]))).animate().fadeIn(delay: 100.ms),
                        ] else if (locker.lockType == 'key' &&
                            booking.status != 'Waiting Approval') ...[
                          const SectionLabel('Key Collection'),
                          NoticeBox(
                            message: booking.status == 'Pending Pickup'
                                ? 'Please collect your key from the Inventory Manager at Facilities Office, Block A Level 1, within 3 working days.'
                                : 'Key collected. If you need a replacement, visit the Facilities Office.',
                            borderColor: AppTheme.goldDark,
                            bgColor: AppTheme.gold.withOpacity(0.12),
                            textColor: const Color(0xFF7A5B00),
                            icon: Icons.key_rounded,
                          ),
                          if (booking.status == 'Pending Pickup' &&
                              !booking.keyCollected)
                            _QrActionCard(
                              title: 'Verify Key Collection',
                              subtitle: booking.keyCollectionQR == null
                                  ? 'Waiting for admin to generate key collection QR.'
                                  : 'Scan your key collection QR to activate booking.',
                              actionLabel: 'Scan Key Collection QR',
                              enabled: booking.keyCollectionQR != null,
                              onTap: booking.keyCollectionQR == null
                                  ? null
                                  : () => _showQrScanDialog(
                                        context,
                                        title: 'Scan Key Collection QR',
                                        hintText:
                                            'Enter key collection QR code',
                                        onSubmit: (code) async {
                                          final ok = await context
                                              .read<AppState>()
                                              .scanKeyCollectionQR(
                                                  booking, code);
                                          if (!context.mounted) return false;
                                          if (!ok) {
                                            _toast(context,
                                                'Invalid QR code or key already collected.');
                                            return false;
                                          }
                                          _toast(context,
                                              'Key collection verified. Locker is now active.');
                                          return true;
                                        },
                                      ),
                            ),
                        ],

                        // Payment info
                        const SectionLabel('Payment Details'),
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [
                                  _PriceRow('Deposit (refundable)',
                                      'RM${bookingPricing.deposit.toStringAsFixed(0)}'),
                                  _PriceRow('Monthly Rent',
                                      'RM${bookingPricing.monthlyRent.toStringAsFixed(0)}/month'),
                                  _PriceRow('Duration',
                                      '${bookingPricing.durationMonths} months'),
                                  _PriceRow('Total Rental Cost',
                                      'RM${bookingPricing.totalRentalCost.toStringAsFixed(0)}'),
                                  const Divider(height: 16),
                                  _PriceRow('Amount Paid',
                                      'RM${bookingPricing.amountDueToday.toStringAsFixed(0)}',
                                      isBold: true),
                                  if (booking.receiptNumber != null &&
                                      booking.receiptNumber!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _PriceRow(
                                        'Receipt No.', booking.receiptNumber!),
                                  ],
                                ]))).animate().fadeIn(delay: 150.ms),

                        if (hasReleaseFlow) ...[
                          const SectionLabel('Release Progress'),
                          ReleaseStepper(
                            status: releaseStatus ?? 'Requested',
                            lockType: isKeyLocker ? 'key' : 'digital',
                            keyReturnGenerated: booking.keyReturnQR != null,
                            keyReturned: booking.keyReturned,
                          ),
                          if (isKeyLocker)
                            _QrActionCard(
                              title: 'Key Return Verification',
                              subtitle: booking.keyReturnQR == null
                                  ? (releaseStatus == 'Requested'
                                      ? 'Waiting for admin to approve release request.'
                                      : releaseStatus == 'Approved'
                                          ? 'Admin approved release. Waiting for return QR generation.'
                                          : 'No return QR available yet.')
                                  : (booking.keyReturned
                                      ? 'Key return verified. Waiting for admin to complete release.'
                                      : 'Scan return QR to confirm key handover.'),
                              actionLabel: 'Scan Return QR',
                              enabled: booking.keyReturnQR != null &&
                                  !booking.keyReturned,
                              onTap: (booking.keyReturnQR != null &&
                                      !booking.keyReturned)
                                  ? () => _showQrScanDialog(
                                        context,
                                        title: 'Scan Return QR',
                                        hintText: 'Enter key return QR code',
                                        onSubmit: (code) async {
                                          final ok = await context
                                              .read<AppState>()
                                              .scanKeyReturnQR(booking, code);
                                          if (!context.mounted) return false;
                                          if (!ok) {
                                            _toast(context,
                                                'Invalid return QR code.');
                                            return false;
                                          }
                                          _toast(context,
                                              'Key return verified. Waiting for admin to complete release.');
                                          return true;
                                        },
                                      )
                                  : null,
                            ),
                        ],

                        // ─── Recent Updates (student notifications) ───
                        const SectionLabel('Recent Updates'),
                        StreamBuilder<List<LockerNotification>>(
                          stream: context
                              .read<AppState>()
                              .watchMyLockerNotifications(),
                          builder: (context, snap) {
                            if (!snap.hasData || snap.data!.isEmpty) {
                              return Card(
                                  child: ListTile(
                                leading: const Icon(
                                    Icons.notifications_none_rounded,
                                    color: AppTheme.textMuted),
                                title: const Text('No updates yet',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textMuted)),
                                subtitle: const Text(
                                    'Notifications about your locker will appear here.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted)),
                              ));
                            }
                            final notifs =
                                snap.data!.take(8).toList(); // show latest 8
                            return Column(
                              children: notifs.map((n) {
                                final dt = DateTime.tryParse(n.createdAt);
                                final timeStr = dt != null
                                    ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                                    : '';
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: n.read
                                        ? null
                                        : () {
                                            context
                                                .read<AppState>()
                                                .markLockerNotificationRead(
                                                    n.id);
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            _notificationIcon(n.type),
                                            size: 22,
                                            color: n.read
                                                ? AppTheme.textMuted
                                                : AppTheme.red,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        n.title,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: n.read
                                                              ? FontWeight.w500
                                                              : FontWeight.w700,
                                                          color: n.read
                                                              ? AppTheme
                                                                  .textMuted
                                                              : AppTheme
                                                                  .textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!n.read)
                                                      Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration:
                                                            const BoxDecoration(
                                                          color: AppTheme.red,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(n.body,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme
                                                            .textMuted)),
                                                if (timeStr.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(timeStr,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme
                                                              .textMuted)),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ).animate().fadeIn(delay: 50.ms);
                              }).toList(),
                            );
                          },
                        ),

                        const SectionLabel('Quick Actions'),
                        HubButton(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Request Extension',
                          subtitle: booking.daysLeft <= 30
                              ? 'Extend your rental period'
                              : 'Available when remaining time is 1 month or less (${booking.daysLeft} days left)',
                          isPrimary: booking.daysLeft <= 30,
                          onTap: booking.daysLeft <= 30
                              ? () => _showExtensionDialog(context, booking)
                              : () => _toast(context,
                                  'Extension available only when remaining time is 1 month or less. You have ${booking.daysLeft} days remaining.'),
                        ),
                        HubButton(
                          icon: Icons.report_problem_rounded,
                          label: 'Report Locker Issue',
                          subtitle: 'Damage, malfunction, etc.',
                          onTap: () =>
                              _showLockerIssueDialog(context, booking.lockerId),
                        ),
                        if (!hasReleaseFlow)
                          HubButton(
                            icon: Icons.cancel_rounded,
                            label: 'Request Locker Release',
                            subtitle:
                                'Start key-return flow and refund process',
                            isAmber: false,
                            iconColor: AppTheme.danger,
                            onTap: () =>
                                _showReleaseRequestDialog(context, booking),
                          )
                        else if (releaseStatus == 'Returned')
                          const NoticeBox(
                            message:
                                'Key return completed. Waiting for admin approval to finalize release and refund.',
                            borderColor: Color(0xFF2E7D32),
                            bgColor: Color(0x112E7D32),
                            textColor: Color(0xFF1E5A23),
                            icon: Icons.hourglass_top_rounded,
                          ),

                        // ── My Reported Issues (realtime from Firestore) ──────
                        const SectionLabel('My Reported Issues'),
                        StreamBuilder<List<LockerIssue>>(
                          stream:
                              context.read<AppState>().watchMyLockerIssues(),
                          builder: (context, issuesSnap) {
                            final issues =
                                issuesSnap.data ?? const <LockerIssue>[];
                            // Only show issues for the current locker.
                            final myIssues = issues
                                .where((i) => i.lockerId == booking.lockerId)
                                .toList();
                            if (myIssues.isEmpty) {
                              return Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(children: [
                                        Icon(Icons.check_circle_outline_rounded,
                                            size: 36,
                                            color: AppTheme.textMuted
                                                .withOpacity(0.5)),
                                        const SizedBox(height: 8),
                                        const Text('No issues reported',
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textMuted)),
                                        const SizedBox(height: 4),
                                        const Text(
                                            'If you encounter any problems with this locker, use "Report Locker Issue" above.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textMuted)),
                                      ])));
                            }
                            return Column(
                                children: myIssues
                                    .map((issue) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: Card(
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(14),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(children: [
                                                          Icon(
                                                              Icons
                                                                  .report_problem_rounded,
                                                              size: 18,
                                                              color: _issueColor(
                                                                  issue
                                                                      .status)),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                              child: Text(
                                                            issue.category
                                                                    .isNotEmpty
                                                                ? issue.category
                                                                : 'Issue',
                                                            style: const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800),
                                                          )),
                                                          StatusBadge(
                                                              issue.status),
                                                        ]),
                                                        const Divider(
                                                            height: 16),
                                                        InfoRow(
                                                            label: 'Reported',
                                                            value: fmtDate(issue
                                                                .reportedDate)),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(issue.description,
                                                            style: const TextStyle(
                                                                fontSize: 13,
                                                                color: AppTheme
                                                                    .textSecondary,
                                                                height: 1.4)),
                                                        if (issue.adminNotes
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                              height: 10),
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(10),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: AppTheme
                                                                  .gold
                                                                  .withOpacity(
                                                                      0.10),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              border: Border.all(
                                                                  color: AppTheme
                                                                      .gold
                                                                      .withOpacity(
                                                                          0.3)),
                                                            ),
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  const Row(
                                                                      children: [
                                                                        Icon(
                                                                            Icons
                                                                                .admin_panel_settings_rounded,
                                                                            size:
                                                                                14,
                                                                            color:
                                                                                AppTheme.goldDark),
                                                                        SizedBox(
                                                                            width:
                                                                                4),
                                                                        Text(
                                                                            'Admin Notes',
                                                                            style: TextStyle(
                                                                                fontSize: 11,
                                                                                fontWeight: FontWeight.w700,
                                                                                color: AppTheme.goldDark)),
                                                                      ]),
                                                                  const SizedBox(
                                                                      height:
                                                                          4),
                                                                  Text(
                                                                      issue
                                                                          .adminNotes,
                                                                      style: const TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              AppTheme.textSecondary)),
                                                                ]),
                                                          ),
                                                        ],
                                                      ]))),
                                        ))
                                    .toList());
                          },
                        ),
                      ])),
            );
          },
        );
      },
    );
  }

  IconData _notificationIcon(String type) {
    switch (type) {
      case 'termination':
        return Icons.warning_rounded;
      case 'release':
        return Icons.assignment_turned_in_rounded;
      case 'block':
        return Icons.block_rounded;
      case 'unblock':
        return Icons.lock_open_rounded;
      case 'force_release':
        return Icons.lock_open_rounded;
      case 'return_qr':
        return Icons.qr_code_rounded;
      case 'key_returned':
        return Icons.key_rounded;
      case 'deposit_refunded':
        return Icons.payments_rounded;
      case 'completed':
        return Icons.check_circle_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  void _showReleaseRequestDialog(BuildContext context, LockerBooking booking) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Request Locker Release?'),
              content: Text(
                'Start release for booking ${booking.id}? You will need to return your key and wait for admin approval before refund is processed.',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.read<AppState>().requestLockerRelease(booking);
                      _toast(context,
                          'Release requested. Please return your key at the admin office.');
                    },
                    child: const Text('Request',
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w700))),
              ],
            ));
  }

  void _showExtensionDialog(BuildContext context, LockerBooking booking) {
    if (booking.daysLeft > 30) {
      _toast(
          context, 'Extension is only available when 30 days or less remain.');
      return;
    }

    final pricing = LockerPricing.fromBooking(booking);
    var months = 1;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Request Extension',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remaining days: ${booking.daysLeft}. Choose additional months to extend.',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Additional Months',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: months > 1
                        ? () => setDialogState(() => months--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$months',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: months < 6
                        ? () => setDialogState(() => months++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              NoticeBox(
                message:
                    'Additional cost: RM${pricing.extensionCost(months).toStringAsFixed(0)} ($months month(s) x RM${pricing.monthlyRent.toStringAsFixed(0)})',
                borderColor: AppTheme.red,
                bgColor: AppTheme.red.withOpacity(0.08),
                textColor: AppTheme.textSecondary,
                icon: Icons.payments_rounded,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () async {
                final ok = await context
                    .read<AppState>()
                    .requestLockerExtension(booking, months);
                if (!context.mounted) return;
                if (!ok) {
                  _toast(context, 'Unable to process extension request.');
                  return;
                }
                Navigator.pop(dialogCtx);
                _toast(
                  context,
                  'Extension successful: +$months month(s), RM${pricing.extensionCost(months).toStringAsFixed(0)} added.',
                );
              },
              child:
                  const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLockerIssueDialog(BuildContext context, String lockerId) {
    final descriptionCtrl = TextEditingController();
    var photoCount = 0;
    String category = 'Lock Damage';
    String? descError;
    bool submitting = false;

    const categories = [
      'Lock Damage',
      'Door Stuck',
      'Shelf Broken',
      'Water Leak',
      'Other',
    ];

    Widget reservedError(String? error, {double height = 16}) {
      return SizedBox(
        height: height,
        child: error != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(error,
                    style: const TextStyle(fontSize: 11, color: Colors.red)),
              )
            : const SizedBox.shrink(),
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void validateDesc() {
            final v = descriptionCtrl.text.trim();
            descError = v.isEmpty ? 'Please describe the issue' : null;
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final dialogMaxWidth = constraints.maxWidth < 400
                  ? constraints.maxWidth * 0.95
                  : 380.0;

              return Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: dialogMaxWidth,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Title ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                        child: Row(children: [
                          const Icon(Icons.report_problem_rounded,
                              color: AppTheme.red, size: 28),
                          const SizedBox(width: 10),
                          const Text('Report Locker Issue',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          if (!submitting)
                            IconButton(
                              icon: const Icon(Icons.close, size: 22),
                              color: AppTheme.textMuted,
                              onPressed: () => Navigator.pop(dialogCtx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ]),
                      ),
                      const Divider(height: 1),

                      // ── Scrollable body ────────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category dropdown
                              DropdownButtonFormField<String>(
                                value: category,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Issue Category',
                                  prefixIcon: Icon(Icons.category_rounded,
                                      color: AppTheme.red),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: categories
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (v) => setDialogState(
                                    () => category = v ?? 'Lock Damage'),
                              ),
                              reservedError(null, height: 8),
                              const SizedBox(height: 4),

                              // Description
                              TextField(
                                controller: descriptionCtrl,
                                maxLines: 3,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  labelText: 'Issue description',
                                  hintText: 'Describe what happened...',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (_) => setDialogState(validateDesc),
                              ),
                              reservedError(descError),
                              const SizedBox(height: 8),

                              // Photo counter — uses Expanded for the label
                              // so the row never overflows on narrow screens.
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text('Attached photos (mock):',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  IconButton(
                                    onPressed: photoCount > 0
                                        ? () =>
                                            setDialogState(() => photoCount--)
                                        : null,
                                    icon: const Icon(
                                        Icons.remove_circle_outline_rounded),
                                  ),
                                  Text('$photoCount',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)),
                                  IconButton(
                                    onPressed: photoCount < 10
                                        ? () =>
                                            setDialogState(() => photoCount++)
                                        : null,
                                    icon: const Icon(
                                        Icons.add_circle_outline_rounded),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Sticky action bar ──────────────────────────
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Row(
                          children: [
                            if (!submitting)
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('Cancel',
                                      style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            if (!submitting) const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: GradientButton(
                                label: submitting ? 'Submitting...' : 'Submit',
                                onPressed: !submitting
                                    ? () async {
                                        setDialogState(() {
                                          validateDesc();
                                          submitting = true;
                                        });
                                        if (descError != null) {
                                          setDialogState(() {
                                            submitting = false;
                                          });
                                          return;
                                        }
                                        final desc =
                                            descriptionCtrl.text.trim();
                                        await context
                                            .read<AppState>()
                                            .reportLockerIssue(
                                                lockerId, desc, photoCount,
                                                category: category);
                                        if (!ctx.mounted) return;
                                        Navigator.pop(dialogCtx);
                                        _toast(context,
                                            'Locker issue submitted. Admin has been notified.');
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showQrScanDialog(
    BuildContext context, {
    required String title,
    required String hintText,
    required Future<bool> Function(String code) onSubmit,
  }) {
    final qrCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: qrCtrl,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              final code = qrCtrl.text.trim();
              if (code.isEmpty) {
                _toast(context, 'Please enter a QR code.');
                return;
              }
              final ok = await onSubmit(code);
              if (!dialogCtx.mounted) return;
              if (ok) {
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Verify', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Screen 33: Admin Locker Dashboard ───────────────────────────

/// A single row of the administrator action queue — one locker that needs an
/// administrator action right now, together with the action label, a human
/// readable detail line, and the timestamp used for "newest first" ordering.
/// Redesigned admin locker hub matching the approved mobile dashboard layout.
class AdminLockerDashboardScreen extends StatefulWidget {
  const AdminLockerDashboardScreen({super.key});

  @override
  State<AdminLockerDashboardScreen> createState() =>
      _AdminLockerDashboardScreenState();
}

class _AdminLockerDashboardScreenState
    extends State<AdminLockerDashboardScreen> {
  late final Stream<List<Locker>> _lockers;
  late final Stream<List<LockerBooking>> _bookings;
  late final Stream<List<LockerIssue>> _issues;
  bool _showMoreStatuses = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _lockers = appState.watchLockers();
    _bookings = appState.watchAllLockerBookings();
    _issues = appState.watchAllLockerIssues();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Locker>>(
      stream: _lockers,
      builder: (context, lockerSnapshot) {
        final lockers = lockerSnapshot.data ?? const <Locker>[];
        final lockersReady = lockerSnapshot.hasData && !lockerSnapshot.hasError;
        final total = lockers.length;
        final available =
            lockers.where((locker) => locker.status == 'Available').length;
        final active =
            lockers.where((locker) => locker.status == 'Active').length;
        final overdue =
            lockers.where((locker) => locker.status == 'Overdue').length;
        final blocked =
            lockers.where((locker) => locker.status == 'Blocked').length;
        final rented =
            lockers.where((locker) => locker.studentId != null).length;

        return StreamBuilder<List<LockerBooking>>(
          stream: _bookings,
          builder: (context, bookingSnapshot) {
            final bookings = bookingSnapshot.data ?? const <LockerBooking>[];
            final bookingsReady =
                bookingSnapshot.hasData && !bookingSnapshot.hasError;
            final waiting = bookings
                .where((booking) => booking.status == 'Waiting Approval')
                .length;
            final pending = bookings
                .where((booking) => booking.status == 'Pending Pickup')
                .length;
            final releaseRequests = bookings
                .where((booking) =>
                    booking.releaseStatus != null &&
                    booking.releaseStatus != 'Completed')
                .length;

            return StreamBuilder<List<LockerIssue>>(
              stream: _issues,
              builder: (context, issueSnapshot) {
                final issues = issueSnapshot.data ?? const <LockerIssue>[];
                final issuesReady =
                    issueSnapshot.hasData && !issueSnapshot.hasError;
                final openIssues =
                    issues.where((issue) => issue.status != 'Resolved').length;

                String display(int number, bool ready) =>
                    ready ? '$number' : '—';

                return Scaffold(
                  backgroundColor: Luxe.bg,
                  body: SafeArea(
                    top: true,
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontal =
                            constraints.maxWidth >= 640 ? 28.0 : 20.0;
                        return ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              horizontal, 6, horizontal, 28),
                          children: [
                            const _AdminLockerIdentityRow(),
                            const SizedBox(height: 12),
                            const _AdminLockerModeCard(),
                            const SizedBox(height: 18),
                            _AdminLockerOverviewCard(
                              showMoreStatuses: _showMoreStatuses,
                              onToggleMore: () => setState(() {
                                _showMoreStatuses = !_showMoreStatuses;
                              }),
                              primaryStats: [
                                _LockerStatData(
                                  icon: Icons.inventory_2_outlined,
                                  value: display(total, lockersReady),
                                  label: 'Total Lockers',
                                  color: const Color(0xFFE21B4D),
                                  tint: const Color(0xFFFFE9EF),
                                ),
                                _LockerStatData(
                                  icon: Icons.lock_open_rounded,
                                  value: display(available, lockersReady),
                                  label: 'Available',
                                  color: const Color(0xFF159447),
                                  tint: const Color(0xFFE7F7EC),
                                ),
                                _LockerStatData(
                                  icon: Icons.person_outline_rounded,
                                  value: display(rented, lockersReady),
                                  label: 'Rented',
                                  color: const Color(0xFF6A2BE2),
                                  tint: const Color(0xFFF0E9FF),
                                ),
                                _LockerStatData(
                                  icon: Icons.schedule_rounded,
                                  value: display(overdue, lockersReady),
                                  label: 'Overdue',
                                  color: const Color(0xFFE21B4D),
                                  tint: const Color(0xFFFFE9EF),
                                ),
                              ],
                              secondaryStats: [
                                _LockerStatData(
                                  icon: Icons.hourglass_top_rounded,
                                  value: display(waiting, bookingsReady),
                                  label: 'Waiting',
                                  color: const Color(0xFFD97706),
                                  tint: const Color(0xFFFFF0DE),
                                ),
                                _LockerStatData(
                                  icon: Icons.lock_rounded,
                                  value: display(active, lockersReady),
                                  label: 'Active',
                                  color: const Color(0xFF2E72D3),
                                  tint: const Color(0xFFEAF2FF),
                                ),
                                _LockerStatData(
                                  icon: Icons.pending_actions_rounded,
                                  value: display(pending, bookingsReady),
                                  label: 'Pending',
                                  color: const Color(0xFFD97706),
                                  tint: const Color(0xFFFFF0DE),
                                ),
                                _LockerStatData(
                                  icon: Icons.block_rounded,
                                  value: display(blocked, lockersReady),
                                  label: 'Blocked',
                                  color: const Color(0xFF64748B),
                                  tint: const Color(0xFFF1F3F5),
                                ),
                                _LockerStatData(
                                  icon: Icons.assignment_return_outlined,
                                  value:
                                      display(releaseRequests, bookingsReady),
                                  label: 'Release Requests',
                                  color: const Color(0xFF2E72D3),
                                  tint: const Color(0xFFEAF2FF),
                                ),
                                _LockerStatData(
                                  icon: Icons.report_problem_outlined,
                                  value: display(openIssues, issuesReady),
                                  label: 'Open Issues',
                                  color: const Color(0xFFD97706),
                                  tint: const Color(0xFFFFF0DE),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _AdminLockerActionsCard(
                              onLockerGrid: () =>
                                  context.push('/admin/lockers/list'),
                              // The list already supports searching by Student
                              // ID, so this action opens the existing lookup.
                              onStudentLookup: () =>
                                  context.push('/admin/lockers/list'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminLockerIdentityRow extends StatelessWidget {
  const _AdminLockerIdentityRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final tiny = constraints.maxWidth < 350;
        final controlSize = tiny
            ? 34.0
            : compact
                ? 36.0
                : 40.0;
        final logoSize = tiny
            ? 40.0
            : compact
                ? 44.0
                : 48.0;
        final gap = tiny
            ? 3.0
            : compact
                ? 4.0
                : 6.0;
        final roleWidth = tiny
            ? 62.0
            : compact
                ? 76.0
                : 104.0;

        return Padding(
          padding: EdgeInsets.only(top: tiny ? 3 : 7, bottom: 5),
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
                    color: Luxe.primary, size: controlSize * .72),
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
                          fontSize: compact ? 16 : 18,
                          fontWeight: FontWeight.w800,
                          color: Luxe.ink,
                          letterSpacing: -.45,
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
                                fontSize: compact ? 9 : 9.5,
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
                child: _AdminLockerRoleChip(
                  onTap: () async {
                    await context.read<AppState>().logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ),
              SizedBox(width: gap),
              _AdminLockerIconButton(
                size: controlSize,
                icon: Icons.person_outline_rounded,
                onTap: () => context.push('/profile'),
              ),
              SizedBox(width: gap),
              _AdminLockerNotificationButton(size: controlSize),
            ],
          ),
        );
      },
    );
  }
}

class _AdminLockerIconButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminLockerIconButton({
    required this.size,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Luxe.rSmall),
        border: Border.all(color: Luxe.primary.withValues(alpha: .08)),
        boxShadow: [
          BoxShadow(
            color: Luxe.primary.withValues(alpha: .07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        icon: Icon(icon, color: Luxe.ink, size: size * .56),
      ),
    );
  }
}

class _AdminLockerRoleChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminLockerRoleChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB83F),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB83F).withValues(alpha: .22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.shield_rounded, color: Color(0xFFA46808), size: 17),
              SizedBox(width: 5),
              Text('Admin',
                  style: TextStyle(
                      color: Color(0xFFA46808),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFFA46808), size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminLockerNotificationButton extends StatelessWidget {
  final double size;

  const _AdminLockerNotificationButton({required this.size});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: context.read<AppState>().watchUnreadCampusNotifications(),
      initialData: 0,
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _AdminLockerIconButton(
              size: size,
              icon: Icons.notifications_none_rounded,
              onTap: () => context.push('/notifications'),
            ),
            if (unread > 0)
              Positioned(
                top: -4,
                right: -4,
                child: IgnorePointer(
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB83F),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA46808),
                        fontSize: 9,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdminLockerModeCard extends StatelessWidget {
  const _AdminLockerModeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2DD).withValues(alpha: .42),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFFFC96C).withValues(alpha: .82)),
        boxShadow: Luxe.lift(tint: Luxe.accent, strength: .45),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DD),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Color(0xFFA46808), size: 27),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Mode',
                  style: TextStyle(
                    color: Color(0xFFA46808),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Full access to manage lockers and operations.',
                  maxLines: 2,
                  style: TextStyle(
                    color: Luxe.inkSoft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.workspace_premium_rounded,
              color: Color(0xFFFFA000), size: 30),
        ],
      ),
    );
  }
}

class _LockerStatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color tint;

  const _LockerStatData({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.tint,
  });
}

class _AdminLockerOverviewCard extends StatelessWidget {
  final List<_LockerStatData> primaryStats;
  final List<_LockerStatData> secondaryStats;
  final bool showMoreStatuses;
  final VoidCallback onToggleMore;

  const _AdminLockerOverviewCard({
    required this.primaryStats,
    required this.secondaryStats,
    required this.showMoreStatuses,
    required this.onToggleMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: Luxe.hairline),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Locker Overview', style: Luxe.cardTitle),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < primaryStats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _LockerPrimaryStatCard(data: primaryStats[i])),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleMore,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                constraints: const BoxConstraints(minHeight: 78),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCFB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Luxe.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0DE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.grid_view_rounded,
                          color: Color(0xFFD97706), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('More Status Details',
                              style: TextStyle(
                                  color: Luxe.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text('Tap to view all locker statuses',
                              style: TextStyle(
                                  color: Luxe.inkSoft,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Icon(
                      showMoreStatuses
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.chevron_right_rounded,
                      color: Luxe.primary,
                      size: 27,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showMoreStatuses) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: secondaryStats.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: constraints.maxWidth < 300 ? 76 : 70,
                  ),
                  itemBuilder: (context, index) =>
                      _LockerSecondaryStatCard(data: secondaryStats[index]),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _LockerPrimaryStatCard extends StatelessWidget {
  final _LockerStatData data;

  const _LockerPrimaryStatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 78;
        final iconBox = compact ? 34.0 : 40.0;
        return Container(
          height: compact ? 138 : 148,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: data.color.withValues(alpha: .16)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: data.tint,
                  borderRadius: BorderRadius.circular(compact ? 11 : 13),
                ),
                child:
                    Icon(data.icon, color: data.color, size: compact ? 19 : 22),
              ),
              Text(
                data.value,
                maxLines: 1,
                style: TextStyle(
                  color: data.color,
                  fontSize: compact ? 25 : 28,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
              ),
              Flexible(
                child: Text(
                  data.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Luxe.ink,
                    fontSize: compact ? 9.5 : 10.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
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

class _LockerSecondaryStatCard extends StatelessWidget {
  final _LockerStatData data;

  const _LockerSecondaryStatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: data.tint.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: data.color.withValues(alpha: .12)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: data.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 17),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.value,
                    style: TextStyle(
                        color: data.color,
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(data.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Luxe.inkSoft,
                        fontSize: 10,
                        height: 1.1,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLockerActionsCard extends StatelessWidget {
  final VoidCallback onLockerGrid;
  final VoidCallback onStudentLookup;

  const _AdminLockerActionsCard({
    required this.onLockerGrid,
    required this.onStudentLookup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: Luxe.hairline),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Actions', style: Luxe.cardTitle),
          ),
          const SizedBox(height: 16),
          _LockerActionCard(
            icon: Icons.grid_view_rounded,
            title: 'Locker Grid',
            subtitle: 'View all locker statuses',
            tint: const Color(0xFFFFE9EF),
            color: Luxe.primary,
            onTap: onLockerGrid,
          ),
          const SizedBox(height: 10),
          _LockerActionCard(
            icon: Icons.person_search_rounded,
            title: 'Student Lookup',
            subtitle: 'Find by student ID',
            tint: const Color(0xFFFFF0DE),
            color: const Color(0xFFD97706),
            onTap: onStudentLookup,
          ),
        ],
      ),
    );
  }
}

class _LockerActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Color color;
  final VoidCallback onTap;

  const _LockerActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Luxe.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Luxe.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Luxe.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Luxe.primary.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Luxe.primary, size: 23),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueItem {
  final Locker locker;
  final LockerBooking? booking;
  final LockerIssue? issue;

  /// Action label shown on the card ("Waiting Approval", "Release Request",
  /// "Locker Issue", "Pending Key Pickup", "Pending Return").
  final String label;

  /// Secondary line ("Submitted 5 minutes ago", "Waiting for key return", …).
  final String detail;

  /// Tie-breaker when two actions share the same timestamp (lower first).
  final int priority;

  /// Timestamp of the event that requires attention. Null when the source
  /// document carries no usable date.
  final DateTime? timestamp;

  const _QueueItem({
    required this.locker,
    required this.label,
    required this.detail,
    required this.priority,
    required this.timestamp,
    this.booking,
    this.issue,
  });

  /// Student behind the action. Booking/issue owner first — a locker awaiting
  /// approval is not yet reserved, so `locker.studentId` is still null there.
  String? get studentId =>
      booking?.studentId ?? issue?.studentId ?? locker.studentId;

  /// Sort key with a stable floor for entries without a timestamp.
  DateTime get sortKey => timestamp ?? DateTime(2000);
}

// ── Screen 34: Admin Lockers List (Smart Filtering) ─────────────
class AdminLockersListScreen extends StatefulWidget {
  const AdminLockersListScreen({super.key});
  @override
  State<AdminLockersListScreen> createState() => _AdminLockersListScreenState();
}

class _AdminLockersListScreenState extends State<AdminLockersListScreen> {
  /// Active filter tab.
  String _filter = 'Recent';

  /// Search query.
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// Sort option.
  String _sortOption = 'Locker ID';

  /// Filter tab definitions (label, key).
  static const _tabs = [
    ('Recent', 'Recent'),
    ('Active', 'Active'),
    ('Available', 'Available'),
    ('Rented', 'Rented'),
    ('Overdue', 'Overdue'),
    ('Blocked', 'Blocked'),
    ('All', 'All'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering logic ─────────────────────────────────────────────

  /// Returns lockers for the given tab. All filtering is client-side from the
  /// single `watchLockers()` stream (plus bookings/issues for the Recent tab).
  List<Locker> _filterLockers(
    String tab,
    List<Locker> all,
    Map<String, LockerBooking> activeBookings,
    Map<String, LockerIssue> latestIssues,
  ) {
    switch (tab) {
      case 'Active':
        return all.where((l) => l.status == 'Active').toList();
      case 'Available':
        return all.where((l) => l.status == 'Available').toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      case 'Rented':
        // Every locker with an active agreement (non-completed, non-blocked,
        // non-available).
        return all.where((l) {
          if (l.status == 'Completed' ||
              l.status == 'Blocked' ||
              l.status == 'Available') return false;
          final bk = activeBookings[l.id];
          if (bk != null && bk.status == 'Completed') return false;
          return true;
        }).toList();
      case 'Overdue':
        return all
            .where((l) =>
                (l.daysLeft ?? 1) <= 0 &&
                l.status != 'Completed' &&
                l.status != 'Available')
            .toList();
      case 'Blocked':
        return all.where((l) => l.status == 'Blocked').toList();
      case 'All':
      case 'Recent':
      default:
        return all.toList();
    }
  }

  // ── Administrator action queue ("Recent" tab) ───────────────────

  /// Builds the administrator action queue.
  ///
  /// The queue is an inbox of *pending tasks*: a locker appears **only** when
  /// it currently requires an administrator action. Nothing historical
  /// (Available / Active / Completed / Blocked / resolved issues) is ever
  /// included.

  ///
  /// Actionable conditions:
  ///  1. `booking.status == 'Waiting Approval'`          → "Waiting Approval"
  ///  2. `booking.releaseStatus == 'Requested'`          → "Release Request"
  ///  3. `issue.status` is 'Reported' / 'Under Review'   → "Locker Issue"
  ///  4. `booking.status == 'Pending Pickup'` && !keyCollected
  ///                                                     → "Pending Key Pickup"
  ///  5. `booking.releaseStatus == 'Approved'` && !keyReturned (key locks)
  ///                                                     → "Release Approved"
  ///  6. `booking.releaseStatus == 'Pending Return'` && !keyReturned
  ///                                                     → "Pending Return"
  ///  7. `booking.releaseStatus == 'Returned'` (key locks)
  ///                                                     → "Pending Completion"
  ///
  /// The full key-lock release chain therefore stays in the queue end to end:
  /// Requested → Approved → Pending Return → Returned → **Completed**. The
  /// locker only leaves the queue once "Complete Release" succeeds (deposit
  /// refunded, booking status 'Completed'). Digital locks are unchanged:
  /// Requested → Approve Release → Completed → removed.
  ///

  /// Everything is derived client-side from the three streams this screen
  /// already listens to (`watchLockers`, `watchAllLockerBookings`,
  /// `watchAllLockerIssues`) — no extra Firestore queries. Because the queue
  /// is recomputed on every stream emission, an entry disappears
  /// automatically the moment its condition stops being true (booking
  /// approved, release approved, key scanned, key returned, issue resolved).
  List<_QueueItem> _buildActionQueue(
    List<Locker> all,
    List<LockerBooking> allBookings,
    List<LockerIssue> allIssues,
  ) {
    final lockerById = {for (final l in all) l.id: l};
    final items = <_QueueItem>[];

    // ── Booking-driven actions ────────────────────────────────────
    for (final b in allBookings) {
      final lk = lockerById[b.lockerId];
      if (lk == null) continue;
      // Terminal bookings are history, never actionable.
      if (b.status == 'Completed' || b.status == 'Rejected') continue;

      // 1. Booking waiting for admin approval.
      if (b.status == 'Waiting Approval') {
        final ts = _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Waiting Approval',
          detail: 'Submitted ${_timeAgo(ts)}',
          priority: 1,
          timestamp: ts,
        ));
        continue;
      }

      // 2. Student asked to release the locker.
      if (b.releaseStatus == 'Requested') {
        final ts = _parseStamp(b.keyReturnDate) ?? _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Release Request',
          detail: 'Requested ${_timeAgo(ts)}',
          priority: 2,
          timestamp: ts,
        ));
        continue;
      }

      // 7. Key returned — the release is NOT finished. The admin still has to
      // run "Complete Release" (refund the deposit and close the agreement),
      // so the locker must stay in the queue until booking.status becomes
      // 'Completed'.
      if (b.releaseStatus == 'Returned' ||
          (b.releaseStatus == 'Pending Return' && b.keyReturned)) {
        final ts = _parseStamp(b.keyReturnDate) ?? _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Pending Completion',
          detail:
              'Key returned ${_timeAgo(ts)} — complete release & refund deposit',
          priority: 3,
          timestamp: ts,
        ));
        continue;
      }

      // 5. Release approved (key locks) — admin must still generate the
      // return QR before the student can hand the key back.
      if (b.releaseStatus == 'Approved' && !b.keyReturned) {
        final ts = _parseStamp(b.keyReturnDate) ?? _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Release Approved',
          detail: 'Generate key return QR',
          priority: 4,
          timestamp: ts,
        ));
        continue;
      }

      // 6. Key return outstanding.
      if (b.releaseStatus == 'Pending Return' && !b.keyReturned) {
        final ts = _parseStamp(b.keyReturnDate) ?? _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Pending Return',
          detail: 'Waiting for key return',
          priority: 5,
          timestamp: ts,
        ));
        continue;
      }

      // 4. Key collection outstanding.
      if (b.status == 'Pending Pickup' && !b.keyCollected) {
        final ts = _parseStamp(lk.startDate) ?? _parseStamp(b.startDate);
        items.add(_QueueItem(
          locker: lk,
          booking: b,
          label: 'Pending Key Pickup',
          detail: 'Waiting for key collection',
          priority: 6,
          timestamp: ts,
        ));
      }
    }

    // ── 3. Open locker issues ─────────────────────────────────────
    for (final i in allIssues) {
      if (i.status != 'Reported' && i.status != 'Under Review') continue;
      final lk = lockerById[i.lockerId];
      if (lk == null) continue;
      final ts = _parseStamp(i.reportedDate);
      final category = i.category.isNotEmpty ? i.category : 'General';
      items.add(_QueueItem(
        locker: lk,
        issue: i,
        label: 'Locker Issue',
        detail: 'Category: $category  |  Reported ${_timeAgo(ts)}',
        priority: 7,
        timestamp: ts,
      ));
    }

    // One row per locker — keep the newest actionable event for that locker.
    final byLocker = <String, _QueueItem>{};
    for (final it in items) {
      final existing = byLocker[it.locker.id];
      if (existing == null || _queueCompare(it, existing) < 0) {
        byLocker[it.locker.id] = it;
      }
    }

    // Newest actionable item first.
    final queue = byLocker.values.toList()..sort(_queueCompare);
    return queue;
  }

  /// Queue ordering: newest timestamp first; ties broken by action priority
  /// and then by locker ID so the list is stable between rebuilds.
  int _queueCompare(_QueueItem a, _QueueItem b) {
    final byTime = b.sortKey.compareTo(a.sortKey);
    if (byTime != 0) return byTime;
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    return a.locker.id.compareTo(b.locker.id);
  }

  /// Parses an ISO date/datetime string, returning null when absent/invalid.
  DateTime? _parseStamp(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Relative "time ago" label for the queue detail line.
  String _timeAgo(DateTime? when) {
    if (when == null) return 'recently';
    final diff = DateTime.now().difference(when);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60)
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inDays < 30)
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    final months = diff.inDays ~/ 30;
    return '$months month${months == 1 ? '' : 's'} ago';
  }

  // ── Sorting logic ───────────────────────────────────────────────

  void _sortList(List<Locker> list, String option) {
    switch (option) {
      case 'Newest':
        list.sort((a, b) {
          final aDate = a.endDate ?? a.startDate ?? '';
          final bDate = b.endDate ?? b.startDate ?? '';
          return bDate.compareTo(aDate);
        });
        break;
      case 'Oldest':
        list.sort((a, b) {
          final aDate = a.startDate ?? a.endDate ?? '';
          final bDate = b.startDate ?? b.endDate ?? '';
          return aDate.compareTo(bDate);
        });
        break;
      case 'Location':
        list.sort((a, b) => a.location.compareTo(b.location));
        break;
      case 'Days Remaining':
        list.sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
        break;
      case 'Locker ID':
      default:
        list.sort((a, b) => a.id.compareTo(b.id));
        break;
    }
  }

  // ── Search logic ────────────────────────────────────────────────

  bool _matchesSearch(Locker l, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (l.id.toLowerCase().contains(q)) return true;
    if (l.location.toLowerCase().contains(q)) return true;
    if ((l.studentId ?? '').toLowerCase().contains(q)) return true;
    if (l.lockType == 'digital' &&
        ('digital'.contains(q) || 'key'.contains(q) == false)) return true;
    if (l.lockType == 'key' && 'key'.contains(q)) return true;
    // Also match "digital" / "key" search terms
    if (q == 'digital' && l.lockType == 'digital') return true;
    if (q == 'key' && l.lockType == 'key') return true;
    return false;
  }

  /// Search for the action queue. Matches Locker ID, Student ID (taken from
  /// the booking/issue, since a locker awaiting approval has no tenant yet),
  /// Location, Locker Type and the action label.
  bool _matchesQueueSearch(_QueueItem item, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final l = item.locker;
    if (l.id.toLowerCase().contains(q)) return true;
    if (l.location.toLowerCase().contains(q)) return true;
    if ((item.studentId ?? '').toLowerCase().contains(q)) return true;
    final type = l.lockType == 'digital' ? 'digital' : 'key';
    if (type.contains(q)) return true;
    if (item.label.toLowerCase().contains(q)) return true;
    return false;
  }

  // ── Count helpers ───────────────────────────────────────────────

  int _countForTab(
    String tab,
    List<Locker> all,
    Map<String, LockerBooking> activeBookings,
    int queueCount,
  ) {
    switch (tab) {
      case 'Active':
        return all.where((l) => l.status == 'Active').length;
      case 'Available':
        return all.where((l) => l.status == 'Available').length;
      case 'Rented':
        return all.where((l) {
          if (l.status == 'Completed' ||
              l.status == 'Blocked' ||
              l.status == 'Available') return false;
          final bk = activeBookings[l.id];
          if (bk != null && bk.status == 'Completed') return false;
          return true;
        }).length;
      case 'Overdue':
        return all
            .where((l) =>
                (l.daysLeft ?? 1) <= 0 &&
                l.status != 'Completed' &&
                l.status != 'Available')
            .length;
      case 'Blocked':
        return all.where((l) => l.status == 'Blocked').length;
      case 'All':
        return all.length;
      case 'Recent':
        // Number of lockers currently awaiting an administrator action.
        return queueCount;
      default:
        return all.length;
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return StreamBuilder<List<Locker>>(
      stream: appState.watchLockers(),
      builder: (context, lockersSnap) {
        final allLockers = lockersSnap.data ?? const <Locker>[];
        return StreamBuilder<List<LockerBooking>>(
          stream: appState.watchAllLockerBookings(),
          builder: (context, bookingsSnap) {
            final allBookings = bookingsSnap.data ?? const <LockerBooking>[];
            // Build a map of lockerId → active (non-completed) booking.
            final activeBookings = <String, LockerBooking>{};
            for (final b in allBookings) {
              if (b.status == 'Completed') continue;
              activeBookings[b.lockerId] = b;
            }
            return StreamBuilder<List<LockerIssue>>(
              stream: appState.watchAllLockerIssues(),
              builder: (context, issuesSnap) {
                final allIssues = issuesSnap.data ?? const <LockerIssue>[];
                // Build a map of lockerId → latest issue (by reportedDate).
                final latestIssues = <String, LockerIssue>{};
                for (final i in allIssues) {
                  final existing = latestIssues[i.lockerId];
                  if (existing == null ||
                      i.reportedDate.compareTo(existing.reportedDate) > 0) {
                    latestIssues[i.lockerId] = i;
                  }
                }

                // Administrator action queue (drives the "Recent" tab).
                final actionQueue =
                    _buildActionQueue(allLockers, allBookings, allIssues);
                final visibleQueue = actionQueue
                    .where((i) => _matchesQueueSearch(i, _searchQuery))
                    .toList();
                final queueByLocker = {
                  for (final i in visibleQueue) i.locker.id: i
                };

                // Compute counts for all tabs.
                final counts = <String, int>{};
                for (final t in _tabs) {
                  counts[t.$2] = _countForTab(
                      t.$2, allLockers, activeBookings, actionQueue.length);
                }

                // Filter + sort.
                List<Locker> filtered;
                if (_filter == 'Recent') {
                  // Queue order (newest actionable item first) is the sort.
                  filtered = visibleQueue.map((i) => i.locker).toList();
                } else {
                  filtered = _filterLockers(
                          _filter, allLockers, activeBookings, latestIssues)
                      .where((l) => _matchesSearch(l, _searchQuery))
                      .toList();
                  _sortList(filtered, _sortOption);
                }

                return Scaffold(
                  appBar: _appBar('All Lockers', context),
                  body: Column(children: [
                    const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: AdminBar()),

                    // ── Search field ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                        decoration: InputDecoration(
                          hintText:
                              'Search by Locker ID, Student, Location, Digital, Key...',
                          hintStyle: const TextStyle(
                              fontSize: 13, color: AppTheme.textMuted),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: AppTheme.textMuted),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18, color: AppTheme.textMuted),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: AppTheme.bgCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppTheme.red.withOpacity(0.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppTheme.red.withOpacity(0.15)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppTheme.red, width: 1.2),
                          ),
                        ),
                      ),
                    ),

                    // ── Filter chips ──────────────────────────────
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        children: _tabs.map((t) {
                          final label = t.$1;
                          final key = t.$2;
                          final selected = _filter == key;
                          final count = counts[key] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(label),
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.white.withOpacity(0.25)
                                            : AppTheme.red.withOpacity(0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : AppTheme.red,
                                        ),
                                      ),
                                    ),
                                  ]),
                              selected: selected,
                              onSelected: (_) => setState(() => _filter = key),
                              selectedColor: AppTheme.red,
                              backgroundColor: AppTheme.bgCard,
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // ── Sort menu ─────────────────────────────────
                    if (_filter != 'Recent')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.sort_rounded,
                                    size: 18, color: AppTheme.textSecondary),
                                tooltip: 'Sort by',
                                onSelected: (v) =>
                                    setState(() => _sortOption = v),
                                itemBuilder: (_) => [
                                  'Locker ID',
                                  'Newest',
                                  'Oldest',
                                  'Location',
                                  'Days Remaining',
                                ]
                                    .map((s) => PopupMenuItem(
                                          value: s,
                                          child: Row(children: [
                                            Icon(
                                              _sortOption == s
                                                  ? Icons.check_rounded
                                                  : Icons.sort_rounded,
                                              size: 16,
                                              color: _sortOption == s
                                                  ? AppTheme.red
                                                  : AppTheme.textMuted,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(s,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: _sortOption == s
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: _sortOption == s
                                                      ? AppTheme.red
                                                      : AppTheme.textPrimary,
                                                )),
                                          ]),
                                        ))
                                    .toList(),
                              ),
                              Text('Sort: $_sortOption',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w500)),
                            ]),
                      ),

                    // ── Locker list ───────────────────────────────
                    Expanded(
                        child: _buildList(filtered, activeBookings,
                            latestIssues, queueByLocker)),
                  ]),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Builds the locker list or empty state.
  Widget _buildList(
    List<Locker> lockers,
    Map<String, LockerBooking> activeBookings,
    Map<String, LockerIssue> latestIssues,
    Map<String, _QueueItem> queueByLocker,
  ) {
    if (lockers.isEmpty) {
      return _emptyStateForTab(_filter);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: lockers.length,
      itemBuilder: (ctx, i) {
        final lk = lockers[i];
        final bk = activeBookings[lk.id];
        return _buildLockerCard(
            lk, bk, latestIssues[lk.id], i, queueByLocker[lk.id]);
      },
    );
  }

  /// Builds a single locker card for the list.
  Widget _buildLockerCard(
      Locker lk, LockerBooking? bk, LockerIssue? issue, int index,
      [_QueueItem? queueItem]) {
    final showRelease = bk != null &&
        bk.releaseStatus != null &&
        bk.releaseStatus != 'Completed';
    final statusLabel = showRelease ? 'Release Requested' : lk.status;
    final lockLabel = lk.lockType == 'digital' ? 'Digital' : 'Key';

    // For Blocked tab, show reason + blocked info + Unblock button.
    if (_filter == 'Blocked') {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(children: [
            InkWell(
              onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
              borderRadius: BorderRadius.circular(16),
              child: Row(children: [
                Container(
                  width: 3,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(lk.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 3),
                      Text(lk.location,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('$lockLabel Lock',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                    ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const StatusBadge('Blocked'),
                  if (lk.daysLeft != null) ...[
                    const SizedBox(height: 4),
                    CountdownBadge(lk.daysLeft!)
                  ],
                ]),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 18),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: OutlineBtn(
                label: 'View Details',
                color: AppTheme.textSecondary,
                onPressed: () => context.push('/admin/lockers/detail/${lk.id}'),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: GradientButton(
                label: 'Unblock Locker',
                color: const Color(0xFF2E7D32),
                onPressed: () => _showUnblockLockerDialog(context, lk),
              )),
            ]),
          ]),
        ),
      ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.1);
    }

    // For Overdue tab, highlight overdue styling.
    if (_filter == 'Overdue') {
      final overdueDays = (lk.daysLeft ?? 0).abs();
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Container(
                width: 3,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFB03030),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(lk.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 3),
                    Text(lk.location,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('Student: ${lk.studentId ?? '—'}  |  $lockLabel Lock',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                  ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const StatusBadge('Overdue'),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x18D65E5E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                      '$overdueDays day${overdueDays == 1 ? '' : 's'} overdue',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB03030))),
                ),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 18),
            ]),
          ),
        ),
      ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.1);
    }

    // For Active tab, show student + rental period + days remaining.
    if (_filter == 'Active') {
      return CardRow(
        title: lk.id,
        subtitle: lk.location,
        status: statusLabel,
        extra:
            'Student: ${lk.studentId ?? '—'}  |  $lockLabel Lock  |  ${bk != null ? '${bk.durationMonths}mo' : '—'}',
        trailing: lk.daysLeft != null ? CountdownBadge(lk.daysLeft!) : null,
        onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
      ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.1);
    }

    // Recent tab = administrator action queue. The badge shows the pending
    // action ("Waiting Approval", "Release Request", "Locker Issue", …) and
    // the extra line explains what the admin has to do, plus how long the
    // item has been waiting.
    if (_filter == 'Recent' && queueItem != null) {
      return CardRow(
        title: lk.id,
        subtitle: lk.location,
        status: queueItem.label,
        extra:
            'Student: ${queueItem.studentId ?? '—'}  |  $lockLabel Lock  |  ${queueItem.detail}',
        trailing: lk.daysLeft != null ? CountdownBadge(lk.daysLeft!) : null,
        onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
      ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.1);
    }

    // Default card for Available, Rented, All tabs.
    return CardRow(
      title: lk.id,
      subtitle: lk.location,
      status: statusLabel,
      extra: 'Student: ${lk.studentId ?? '—'}  |  $lockLabel Lock',
      trailing: lk.daysLeft != null ? CountdownBadge(lk.daysLeft!) : null,
      onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
    ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.1);
  }

  /// Returns a friendly empty state for the current tab.
  Widget _emptyStateForTab(String tab) {
    final messages = <String, (String, IconData)>{
      'Recent': ('No pending actions', Icons.history_rounded),
      'Active': ('No active lockers', Icons.check_circle_outline_rounded),
      'Available': ('No available lockers', Icons.lock_open_rounded),
      'Rented': ('No rented lockers', Icons.meeting_room_rounded),
      'Overdue': ('No overdue lockers', Icons.check_circle_outline_rounded),
      'Blocked': ('No blocked lockers', Icons.block_rounded),
      'All': ('No lockers found', Icons.inbox_rounded),
    };
    final entry = messages[tab] ?? ('No lockers found', Icons.inbox_rounded);
    final subtitle = _searchQuery.isNotEmpty
        ? 'No lockers match "$_searchQuery" in this tab.'
        : tab == 'Recent'
            ? 'Nothing needs your attention right now. New requests, releases and issues will appear here.'
            : 'There are currently no ${tab.toLowerCase()} lockers to show.';

    return EmptyState(icon: entry.$2, title: entry.$1, subtitle: subtitle);
  }
}

/// Read-only card for a booking in its terminal `Completed` state. Shows the
/// audit fields required by the booking-history spec and exposes no
/// operational actions (no QR / Approve / Block / Terminate / Release).
class _CompletedBookingCard extends StatelessWidget {
  final LockerBooking booking;
  final VoidCallback? onTap;
  const _CompletedBookingCard({required this.booking, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(booking.lockerId,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary))),
              const StatusBadge('Completed'),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 18),
            ]),
            const Divider(height: 18),
            InfoRow(label: 'Student ID', value: booking.studentId ?? '—'),
            InfoRow(label: 'Locker ID', value: booking.lockerId),
            InfoRow(label: 'Completed', value: fmtDate(booking.completedDate)),
            InfoRow(
                label: 'Deposit',
                value:
                    'RM${booking.deposit.toStringAsFixed(0)}${booking.depositRefunded ? " (Refunded)" : " (Not Refunded)"}'),
            InfoRow(
                label: 'Rental Duration',
                value:
                    '${booking.durationMonths} month${booking.durationMonths == 1 ? "" : "s"}'),
          ]),
        ),
      ),
    );
  }
}

// ── Screen 35: Admin Locker Detail (fully functional) ────────────
class AdminLockerDetailScreen extends StatefulWidget {
  final String id;
  const AdminLockerDetailScreen({super.key, required this.id});
  @override
  State<AdminLockerDetailScreen> createState() =>
      _AdminLockerDetailScreenState();
}

class _AdminLockerDetailScreenState extends State<AdminLockerDetailScreen> {
  final TextEditingController _noticeController = TextEditingController();

  @override
  void dispose() {
    _noticeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return StreamBuilder<Locker?>(
      stream: appState.watchLocker(widget.id),
      builder: (context, lockerSnap) {
        final lk = lockerSnap.data ??
            Locker(
              id: widget.id,
              location: '',
              status: '',
              studentId: null,
              endDate: null,
              daysLeft: null,
            );
        return StreamBuilder<List<LockerBooking>>(
          stream: appState.watchAllLockerBookings(),
          builder: (context, bookingsSnap) {
            final allBookings = bookingsSnap.data ?? const <LockerBooking>[];
            return StreamBuilder<List<LockerHistory>>(
              stream: appState.watchLockerHistory(widget.id),
              builder: (context, histSnap) {
                final hist = histSnap.data ?? const <LockerHistory>[];
                final isOccupied = lk.studentId != null;
                // Pick the booking to display for this locker: prefer the active
                // (non-completed) booking; if none exists fall back to the most
                // recent completed booking so the booking history is inspectable.
                LockerBooking? booking;
                LockerBooking? completedBooking;
                for (final b in allBookings) {
                  if (b.lockerId != lk.id) continue;
                  if (b.status != 'Completed') {
                    booking = b;
                    break;
                  }
                  completedBooking ??= b;
                }
                booking ??= completedBooking;
                final isCompleted =
                    booking != null && booking.status == 'Completed';
                final lockerBooking = booking;
                final isWaitingApproval = lockerBooking != null &&
                    !isCompleted &&
                    lockerBooking.status == 'Waiting Approval';
                final showRelease = lockerBooking != null &&
                    !isCompleted &&
                    lockerBooking.releaseStatus != null &&
                    lockerBooking.releaseStatus != 'Completed';
                final isPendingKeyPickup = lockerBooking != null &&
                    !isCompleted &&
                    lk.lockType == 'key' &&
                    lockerBooking.status == 'Pending Pickup' &&
                    !lockerBooking.keyCollected;
                // Digital locks have no key-collection QR step, but the locker is
                // still unreserved (lk.studentId == null) until the admin confirms.
                final isPendingDigital = lockerBooking != null &&
                    !isCompleted &&
                    lk.lockType == 'digital' &&
                    lockerBooking.status == 'Pending Pickup' &&
                    lk.studentId == null;
                final canGenerateReturnQr = lockerBooking != null &&
                    !isCompleted &&
                    lk.lockType == 'key' &&
                    (lockerBooking.releaseStatus == 'Approved' ||
                        lockerBooking.releaseStatus == 'Pending Return') &&
                    !lockerBooking.keyReturned;
                // Approve Release Request: intermediate step for KEY lockers — moves
                // releaseStatus from 'Requested' to 'Approved'. The admin then
                // generates the return QR.
                final canApproveReleaseRequest = lockerBooking != null &&
                    !isCompleted &&
                    lk.lockType == 'key' &&
                    lockerBooking.releaseStatus == 'Requested';
                // Approve Release (final): for DIGITAL lockers, can be done from
                // 'Requested'. For KEY lockers, requires key returned
                // (releaseStatus == 'Returned' && keyReturned == true).
                final canApproveRelease = lockerBooking != null &&
                    !isCompleted &&
                    ((lk.lockType == 'key' &&
                            lockerBooking.releaseStatus == 'Returned' &&
                            lockerBooking.keyReturned) ||
                        (lk.lockType == 'digital' &&
                            lockerBooking.releaseStatus == 'Requested'));

                return Scaffold(
                  appBar: _appBar(lk.id, context),
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AdminBar(), const SizedBox(height: 8),

                            // Locker / completed-booking info card
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                isCompleted
                                                    ? 'Completed Booking'
                                                    : lk.id,
                                                style: const TextStyle(
                                                    fontSize: 17,
                                                    fontWeight:
                                                        FontWeight.w800))),
                                        StatusBadge(isCompleted
                                            ? 'Completed'
                                            : (showRelease
                                                ? 'Release Requested'
                                                : lk.status))
                                      ]),
                                      const Divider(height: 18),
                                      if (isCompleted &&
                                          lockerBooking != null) ...[
                                        InfoRow(
                                            label: 'Student ID',
                                            value:
                                                lockerBooking.studentId ?? '—'),
                                        InfoRow(
                                            label: 'Locker ID',
                                            value: lockerBooking.lockerId),
                                        InfoRow(
                                            label: 'Location',
                                            value: lk.location),
                                        InfoRow(
                                            label: 'Completed Date',
                                            value: fmtDate(
                                                lockerBooking.completedDate)),
                                        InfoRow(
                                            label: 'Deposit',
                                            value:
                                                'RM${lockerBooking.deposit.toStringAsFixed(0)}${lockerBooking.depositRefunded ? " (Refunded)" : " (Not Refunded)"}'),
                                        InfoRow(
                                            label: 'Rental Duration',
                                            value:
                                                '${lockerBooking.durationMonths} month${lockerBooking.durationMonths == 1 ? "" : "s"}'),
                                        if (lockerBooking.startDate.isNotEmpty)
                                          InfoRow(
                                              label: 'Start Date',
                                              value: fmtDate(
                                                  lockerBooking.startDate)),
                                        if (lockerBooking.endDate.isNotEmpty)
                                          InfoRow(
                                              label: 'End Date',
                                              value: fmtDate(
                                                  lockerBooking.endDate)),
                                      ] else ...[
                                        InfoRow(
                                            label: 'Location',
                                            value: lk.location),
                                        InfoRow(
                                            label: 'Lock Type',
                                            value: lk.lockType == 'digital'
                                                ? 'Digital Lock'
                                                : 'Key Lock'),
                                        InfoRow(
                                            label: 'Monthly Rent',
                                            value:
                                                'RM${lk.monthlyRent.toStringAsFixed(0)}'),
                                        InfoRow(
                                            label: 'Deposit',
                                            value:
                                                'RM${lk.deposit.toStringAsFixed(0)}${lk.depositRefunded ? " (Refunded)" : ""}'),
                                        if (lk.studentId != null)
                                          InfoRow(
                                              label: 'Student ID',
                                              value: lk.studentId!),
                                        if (lk.startDate != null &&
                                            lk.startDate!.isNotEmpty)
                                          InfoRow(
                                              label: 'Start Date',
                                              value: fmtDate(lk.startDate!)),
                                        if (lk.endDate != null &&
                                            lk.endDate!.isNotEmpty)
                                          InfoRow(
                                              label: 'End Date',
                                              value: fmtDate(lk.endDate!)),
                                        // Digital code comes from the current booking — never from
                                        // the locker document (readable by every signed-in user).
                                        if (lk.lockType == 'digital' &&
                                            lockerBooking?.digitalCode != null)
                                          InfoRow(
                                              label: 'Digital Code',
                                              value:
                                                  lockerBooking!.digitalCode!),
                                        if (lk.daysLeft != null)
                                          Align(
                                              alignment: Alignment.centerRight,
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: CountdownBadge(
                                                      lk.daysLeft!))),
                                      ],
                                    ]))).animate().fadeIn(delay: 50.ms),

                            // Waiting Approval review section — admin can approve or reject.
                            if (isWaitingApproval) ...[
                              const SectionLabel('Booking Approval'),
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              const Icon(
                                                  Icons.hourglass_top_rounded,
                                                  color: Color(0xFFE65100),
                                                  size: 22),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: Text(
                                                      'Booking from ${lockerBooking.studentId ?? '—'}',
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight
                                                              .w800))),
                                            ]),
                                            const Divider(height: 18),
                                            InfoRow(
                                                label: 'Student ID',
                                                value:
                                                    lockerBooking.studentId ??
                                                        '—'),
                                            InfoRow(
                                                label: 'Locker ID',
                                                value: lockerBooking.lockerId),
                                            InfoRow(
                                                label: 'Location',
                                                value: lk.location),
                                            InfoRow(
                                                label: 'Lock Type',
                                                value: lk.lockType == 'digital'
                                                    ? 'Digital Lock'
                                                    : 'Key Lock'),
                                            InfoRow(
                                                label: 'Duration',
                                                value:
                                                    '${lockerBooking.durationMonths} month(s)'),
                                            InfoRow(
                                                label: 'Start Date',
                                                value: fmtDate(
                                                    lockerBooking.startDate)),
                                            InfoRow(
                                                label: 'End Date',
                                                value: fmtDate(
                                                    lockerBooking.endDate)),
                                            const Divider(height: 18),
                                            _PriceRow('Deposit',
                                                'RM${LockerPricing.fromBooking(lockerBooking).deposit.toStringAsFixed(0)}'),
                                            _PriceRow('Monthly Rent',
                                                'RM${LockerPricing.fromBooking(lockerBooking).monthlyRent.toStringAsFixed(0)}/month'),
                                            _PriceRow('Total Rental Cost',
                                                'RM${LockerPricing.fromBooking(lockerBooking).totalRentalCost.toStringAsFixed(0)}'),
                                            _PriceRow('Amount Paid',
                                                'RM${LockerPricing.fromBooking(lockerBooking).amountDueToday.toStringAsFixed(0)}',
                                                isBold: true),
                                            if (lockerBooking.receiptNumber !=
                                                    null &&
                                                lockerBooking
                                                    .receiptNumber!.isNotEmpty)
                                              InfoRow(
                                                  label: 'Receipt No.',
                                                  value: lockerBooking
                                                      .receiptNumber!),
                                            const SizedBox(height: 16),
                                            Row(children: [
                                              Expanded(
                                                  child: GradientButton(
                                                label: 'Approve',
                                                onPressed: () =>
                                                    _approveBooking(
                                                        lockerBooking, lk),
                                              )),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: OutlineBtn(
                                                label: 'Reject',
                                                color: AppTheme.danger,
                                                onPressed: () => _rejectBooking(
                                                    lockerBooking),
                                              )),
                                            ]),
                                          ]))).animate().fadeIn(delay: 80.ms),
                            ],

                            // Release flow (kept visible for completed bookings — read-only record
                            // of the finished release; it carries no actions).
                            if (booking != null &&
                                booking.releaseStatus != null)
                              ReleaseStepper(
                                status: booking.releaseStatus!,
                                lockType: lk.lockType,
                                keyReturnGenerated: booking.keyReturnQR != null,
                                keyReturned: booking.keyReturned,
                              ),

                            // Admin Actions (hidden for terminal Completed bookings — read-only)
                            if (!isCompleted) ...[
                              const SectionLabel('Admin Actions'),

                              if (isPendingDigital) ...[
                                _AdminActionButton(
                                  icon: Icons.dialpad_rounded,
                                  label: 'Confirm Digital Booking',
                                  subtitle:
                                      'Reserve locker and assign its digital code',
                                  color: AppTheme.goldDark,
                                  onTap: () => _confirmDigital(booking!, lk),
                                ).animate().fadeIn(delay: 80.ms),
                              ],

                              if (isPendingKeyPickup) ...[
                                _AdminActionButton(
                                  icon: Icons.qr_code_2_rounded,
                                  label: lockerBooking.keyCollectionQR != null
                                      ? 'Regenerate Key Collection QR'
                                      : 'Generate Key Collection QR',
                                  subtitle:
                                      'Generate one-time QR for key pickup',
                                  color: AppTheme.goldDark,
                                  onTap: () {
                                    if (lockerBooking.keyCollectionQR != null) {
                                      _showRegenerateQrDialog(context,
                                          title: 'Key Collection QR',
                                          onConfirm: () =>
                                              _generateCollectionQr(
                                                  booking!, lk));
                                    } else {
                                      _generateCollectionQr(booking!, lk);
                                    }
                                  },
                                ).animate().fadeIn(delay: 80.ms),
                              ],

                              if (canGenerateReturnQr) ...[
                                _AdminActionButton(
                                  icon: Icons.qr_code_scanner_rounded,
                                  label: lockerBooking.keyReturnQR != null
                                      ? 'Regenerate Return QR'
                                      : 'Generate Return QR',
                                  subtitle:
                                      'Generate QR for key return verification',
                                  color: const Color(0xFF1565C0),
                                  onTap: () {
                                    if (lockerBooking.keyReturnQR != null) {
                                      _showRegenerateQrDialog(context,
                                          title: 'Return QR',
                                          onConfirm: () =>
                                              _generateReturnQr(booking!));
                                    } else {
                                      _generateReturnQr(booking!);
                                    }
                                  },
                                ).animate().fadeIn(delay: 90.ms),
                              ],

                              if (canApproveReleaseRequest) ...[
                                _AdminActionButton(
                                  icon: Icons.assignment_turned_in_rounded,
                                  label: 'Approve Release Request',
                                  subtitle:
                                      'Approve the student\'s release request to proceed',
                                  color: const Color(0xFF1565C0),
                                  onTap: () => _showApproveReleaseRequestDialog(
                                      context, lk, booking!),
                                ).animate().fadeIn(delay: 92.ms),
                              ],

                              if (canApproveRelease) ...[
                                _AdminActionButton(
                                  icon: Icons.verified_rounded,
                                  label: lk.lockType == 'key'
                                      ? 'Complete Release'
                                      : 'Approve Release',
                                  subtitle: lk.lockType == 'key'
                                      ? 'Finalize release and process deposit refund'
                                      : 'Approve release, refund deposit, and complete booking',
                                  color: const Color(0xFF2E7D32),
                                  onTap: () => _showApproveReleaseDialog(
                                      context, lk, booking!),
                                ).animate().fadeIn(delay: 95.ms),
                              ],

                              // Terminate Agreement (only if occupied)
                              if (isOccupied) ...[
                                _AdminActionButton(
                                  icon: Icons.cancel_rounded,
                                  label: 'Terminate Agreement',
                                  subtitle: 'End rental, deposit forfeited',
                                  color: AppTheme.danger,
                                  onTap: () => _showTerminateDialog(
                                      context, lk, booking),
                                ).animate().fadeIn(delay: 100.ms),
                              ],

                              // Block Locker (available for non-blocked lockers)
                              if (lk.status != 'Blocked') ...[
                                _AdminActionButton(
                                  icon: Icons.block_rounded,
                                  label: 'Block Locker',
                                  subtitle:
                                      'Mark as unavailable for maintenance/issues',
                                  color: Colors.grey.shade700,
                                  onTap: () =>
                                      _showBlockDialog(context, lk, booking),
                                ).animate().fadeIn(delay: 150.ms),
                              ],

                              // Unblock Locker (only for blocked lockers)
                              if (lk.status == 'Blocked') ...[
                                _AdminActionButton(
                                  icon: Icons.lock_open_rounded,
                                  label: 'Unblock Locker',
                                  subtitle: 'Make locker available again',
                                  color: const Color(0xFF2E7D32),
                                  onTap: () =>
                                      _showUnblockLockerDialog(context, lk),
                                ).animate().fadeIn(delay: 150.ms),
                              ],

                              // Force Release Locker (for blocked/occupied lockers)
                              if (lk.status == 'Blocked' || isOccupied) ...[
                                _AdminActionButton(
                                  icon: Icons.lock_open_rounded,
                                  label: 'Force Release Locker',
                                  subtitle:
                                      'Force-release locker and make it available',
                                  color: AppTheme.redDark,
                                  onTap: () => _showForceReleaseDialog(
                                      context, lk, booking),
                                ).animate().fadeIn(delay: 200.ms),
                              ],

                              // Send Notice (only if tenant exists)
                              if (isOccupied) ...[
                                const SectionLabel('Send Notice to Tenant'),
                                Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(children: [
                                          TextField(
                                            controller: _noticeController,
                                            maxLines: 3,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Type your notice/reminder message...',
                                              hintStyle: const TextStyle(
                                                  fontSize: 13,
                                                  color: AppTheme.textMuted),
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                      color: AppTheme.red
                                                          .withOpacity(0.2))),
                                              enabledBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                      color: AppTheme.red
                                                          .withOpacity(0.2))),
                                              focusedBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                      color: AppTheme.red)),
                                              contentPadding:
                                                  const EdgeInsets.all(14),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(children: [
                                            if (lk.status == 'Overdue')
                                              Expanded(
                                                  child: OutlineBtn(
                                                      label:
                                                          'Send Overdue Reminder',
                                                      color: AppTheme.danger,
                                                      onPressed: () async {
                                                        final msg =
                                                            'OVERDUE NOTICE: Your locker ${lk.id} rental has expired. Please renew or return the locker immediately to avoid penalties.';
                                                        await context
                                                            .read<AppState>()
                                                            .sendLockerNotice(
                                                                lk, msg);
                                                        if (!context.mounted)
                                                          return;
                                                        _toast(context,
                                                            'Overdue reminder sent to ${lk.studentId}');
                                                      })),
                                            if (lk.status == 'Overdue')
                                              const SizedBox(width: 10),
                                            Expanded(
                                                child: GradientButton(
                                                    label: 'Send Notice',
                                                    onPressed: () async {
                                                      final msg =
                                                          _noticeController.text
                                                              .trim();
                                                      if (msg.isEmpty) {
                                                        _toast(context,
                                                            'Please enter a message');
                                                        return;
                                                      }
                                                      await context
                                                          .read<AppState>()
                                                          .sendLockerNotice(
                                                              lk, msg);
                                                      if (!context.mounted)
                                                        return;
                                                      _noticeController.clear();
                                                      _toast(context,
                                                          'Notice sent to ${lk.studentId}');
                                                    })),
                                          ]),
                                        ]))).animate().fadeIn(delay: 250.ms),
                              ],
                            ], // end if (!isCompleted) — operational admin actions

                            // ── Locker Issues (realtime from Firestore) ────────────
                            const SectionLabel('Locker Issues'),
                            StreamBuilder<List<LockerIssue>>(
                              stream: appState.watchAllLockerIssues(),
                              builder: (context, issuesSnap) {
                                final allIssues =
                                    issuesSnap.data ?? const <LockerIssue>[];
                                final lockerIssues = allIssues
                                    .where((i) => i.lockerId == lk.id)
                                    .toList();
                                if (lockerIssues.isEmpty) {
                                  return Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(children: [
                                            Icon(
                                                Icons
                                                    .check_circle_outline_rounded,
                                                size: 36,
                                                color: AppTheme.textMuted
                                                    .withOpacity(0.5)),
                                            const SizedBox(height: 8),
                                            const Text('No issues reported',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.textMuted)),
                                          ])));
                                }
                                return Column(
                                    children: lockerIssues
                                        .map((issue) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: Card(
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              14),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(children: [
                                                              Icon(
                                                                  Icons
                                                                      .report_problem_rounded,
                                                                  size: 18,
                                                                  color: _issueColor(
                                                                      issue
                                                                          .status)),
                                                              const SizedBox(
                                                                  width: 8),
                                                              Expanded(
                                                                  child: Text(
                                                                issue.category
                                                                        .isNotEmpty
                                                                    ? issue
                                                                        .category
                                                                    : 'Issue',
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800),
                                                              )),
                                                              StatusBadge(
                                                                  issue.status),
                                                            ]),
                                                            const Divider(
                                                                height: 16),
                                                            InfoRow(
                                                                label:
                                                                    'Student ID',
                                                                value: issue
                                                                    .studentId),
                                                            InfoRow(
                                                                label:
                                                                    'Reported',
                                                                value: fmtDate(issue
                                                                    .reportedDate)),
                                                            InfoRow(
                                                                label: 'Photos',
                                                                value:
                                                                    '${issue.photoCount}'),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                                issue
                                                                    .description,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    color: AppTheme
                                                                        .textSecondary,
                                                                    height:
                                                                        1.4)),
                                                            if (issue.adminNotes
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                  height: 8),
                                                              Container(
                                                                width: double
                                                                    .infinity,
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        10),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: AppTheme
                                                                      .gold
                                                                      .withOpacity(
                                                                          0.10),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                  border: Border.all(
                                                                      color: AppTheme
                                                                          .gold
                                                                          .withOpacity(
                                                                              0.3)),
                                                                ),
                                                                child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      const Row(
                                                                          children: [
                                                                            Icon(Icons.admin_panel_settings_rounded,
                                                                                size: 14,
                                                                                color: AppTheme.goldDark),
                                                                            SizedBox(width: 4),
                                                                            Text('Admin Notes',
                                                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.goldDark)),
                                                                          ]),
                                                                      const SizedBox(
                                                                          height:
                                                                              4),
                                                                      Text(
                                                                          issue
                                                                              .adminNotes,
                                                                          style: const TextStyle(
                                                                              fontSize: 12,
                                                                              color: AppTheme.textSecondary)),
                                                                    ]),
                                                              ),
                                                            ],
                                                            // ── Admin action buttons ───────────────────────
                                                            if (issue.status ==
                                                                'Reported') ...[
                                                              const SizedBox(
                                                                  height: 12),
                                                              Row(children: [
                                                                Expanded(
                                                                    child:
                                                                        GradientButton(
                                                                  label:
                                                                      'Mark Under Review',
                                                                  onPressed: () =>
                                                                      _showIssueStatusDialog(
                                                                    context,
                                                                    issue,
                                                                    'Under Review',
                                                                  ),
                                                                )),
                                                              ]),
                                                            ] else if (issue
                                                                    .status ==
                                                                'Under Review') ...[
                                                              const SizedBox(
                                                                  height: 12),
                                                              Row(children: [
                                                                Expanded(
                                                                    child:
                                                                        GradientButton(
                                                                  label:
                                                                      'Resolve',
                                                                  color: const Color(
                                                                      0xFF2E7D32),
                                                                  onPressed: () =>
                                                                      _showIssueStatusDialog(
                                                                    context,
                                                                    issue,
                                                                    'Resolved',
                                                                  ),
                                                                )),
                                                              ]),
                                                            ],
                                                          ]))),
                                            ))
                                        .toList());
                              },
                            ),

                            // History (always visible, including for completed bookings)
                            if (hist.isNotEmpty) ...[
                              const SectionLabel('History'),
                              ...hist.reversed.map((h) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: AppTheme.creamLight,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(h.action,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(
                                                '${h.timestamp} \u00b7 ${h.staffId}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.textMuted)),
                                            if (h.reason != null)
                                              Text(h.reason!,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme
                                                          .textSecondary)),
                                          ])))),
                            ],
                          ])),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _generateCollectionQr(
      LockerBooking booking, Locker locker) async {
    final code =
        await context.read<AppState>().generateKeyCollectionQR(booking, locker);
    if (!mounted) return;
    if (code == null) {
      _toast(context, 'Failed to generate QR. Please try again.');
      return;
    }
    _showQrCodeDialog(
      context,
      title: 'Key Collection QR',
      code: code,
      helper:
          'Share this code at the counter. Student must scan this code in My Locker to activate booking.',
    );
  }

  Future<void> _confirmDigital(LockerBooking booking, Locker locker) async {
    final ok = await context
        .read<AppState>()
        .confirmDigitalLockerBooking(booking, locker);
    if (!mounted) return;
    if (!ok) {
      _toast(context, 'Failed to confirm booking. Please try again.');
      return;
    }
    _toast(context, 'Digital booking confirmed. Locker reserved.');
  }

  /// Approves a 'Waiting Approval' booking. For digital lockers the booking
  /// moves to 'Active' and the digital code is assigned. For key lockers the
  /// booking moves to 'Pending Pickup' and the admin can then generate the
  /// key collection QR.
  Future<void> _approveBooking(LockerBooking booking, Locker locker) async {
    final ok =
        await context.read<AppState>().approveLockerBooking(booking, locker);
    if (!mounted) return;
    if (!ok) {
      _toast(context, 'Failed to approve booking. Please try again.');
      return;
    }
    if (locker.lockType == 'digital') {
      _toast(context, 'Booking approved. Digital locker activated.');
    } else {
      _toast(
          context, 'Booking approved. Generate key collection QR for student.');
    }
  }

  /// Rejects a 'Waiting Approval' booking. The booking moves to 'Rejected'
  /// and the payment is marked 'Refund Pending'.
  Future<void> _rejectBooking(LockerBooking booking) async {
    final ok = await context.read<AppState>().rejectLockerBooking(booking);
    if (!mounted) return;
    if (!ok) {
      _toast(context, 'Failed to reject booking. Please try again.');
      return;
    }
    _toast(context, 'Booking rejected. Refund pending.');
  }

  Future<void> _generateReturnQr(LockerBooking booking) async {
    final code = await context.read<AppState>().generateKeyReturnQR(booking);
    if (!mounted) return;
    if (code == null) {
      _toast(context, 'Failed to generate QR. Please try again.');
      return;
    }
    _toast(context, 'Return QR generated. Previous QR is now invalid.');
    _showQrCodeDialog(
      context,
      title: 'Key Return QR',
      code: code,
      helper:
          'Student must scan this return QR in My Locker after handing over the key.',
    );
  }

  void _showRegenerateQrDialog(
    BuildContext context, {
    required String title,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Generate New $title?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: const Text(
          'The previous QR will become invalid immediately. Only the new QR can be scanned.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Generate',
                style: TextStyle(
                    color: AppTheme.redDark, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showQrCodeDialog(
    BuildContext context, {
    required String title,
    required String code,
    required String helper,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.red.withOpacity(0.25)),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.red,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(helper,
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showTerminateDialog(
      BuildContext context, Locker lk, LockerBooking? booking) {
    // Validation guard: cannot terminate a completed booking.
    if (booking != null && booking.status == 'Completed') {
      _toast(context, 'Cannot terminate a completed booking.');
      return;
    }
    String? selectedReason;
    final otherController = TextEditingController();
    const reasons = [
      'Student violated locker policy',
      'Locker damaged',
      'Rental payment overdue',
      'Unauthorized usage',
      'Student requested termination',
      'Maintenance requirement',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_rounded, color: AppTheme.danger, size: 24),
            SizedBox(width: 8),
            Text('Terminate Agreement',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'This will terminate the rental agreement for locker ${lk.id} (${lk.studentId ?? 'no tenant'}).',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  const NoticeBox(
                    message:
                        'The student\'s deposit will be forfeited. The locker will become available for new bookings.',
                    borderColor: AppTheme.danger,
                    bgColor: Color(0x0ED65E5E),
                    textColor: Color(0xFF8B2020),
                    icon: Icons.warning_rounded,
                  ),
                  const SizedBox(height: 14),
                  const Text('Reason for termination (required):',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => RadioListTile<String>(
                        value: r,
                        groupValue: selectedReason,
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 0),
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        onChanged: (v) =>
                            setDialogState(() => selectedReason = v),
                      )),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: otherController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Please specify the reason...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textMuted))),
            TextButton(
              onPressed: () async {
                if (selectedReason == null) {
                  _toast(ctx, 'Please select a reason for termination.');
                  return;
                }
                String reason = selectedReason!;
                if (reason == 'Other') {
                  final custom = otherController.text.trim();
                  if (custom.isEmpty) {
                    _toast(ctx, 'Please specify the reason for "Other".');
                    return;
                  }
                  reason = custom;
                }
                Navigator.pop(ctx);
                final ok = await context
                    .read<AppState>()
                    .terminateLocker(lk, booking, reason: reason);
                if (!context.mounted) return;
                _toast(
                    context,
                    ok
                        ? 'Agreement terminated for ${lk.id}. Student notified. Locker is now available.'
                        : 'Failed to terminate. Please try again.');
              },
              child: const Text('Terminate',
                  style: TextStyle(
                      color: AppTheme.danger, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog(
      BuildContext context, Locker lk, LockerBooking? booking) {
    // Validation guard: cannot block an already-blocked locker.
    if (lk.status == 'Blocked') {
      _toast(context, 'Locker is already blocked.');
      return;
    }
    String? selectedReason;
    final otherController = TextEditingController();
    const reasons = [
      'Maintenance',
      'Broken Lock',
      'Cleaning',
      'Water Damage',
      'Security Investigation',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Block Locker',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Block locker ${lk.id}? This will mark it as unavailable.',
                      style: const TextStyle(fontSize: 13)),
                  if (lk.studentId != null) ...[
                    const SizedBox(height: 8),
                    NoticeBox(
                      message:
                          'This locker is rented by ${lk.studentId}. Blocking will remove their booking.',
                      borderColor: AppTheme.goldDark,
                      bgColor: AppTheme.gold.withOpacity(0.12),
                      textColor: const Color(0xFF7A5B00),
                      icon: Icons.warning_rounded,
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text('Reason for blocking (required):',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => RadioListTile<String>(
                        value: r,
                        groupValue: selectedReason,
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 0),
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        onChanged: (v) =>
                            setDialogState(() => selectedReason = v),
                      )),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: otherController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Please specify the reason...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textMuted))),
            TextButton(
              onPressed: () async {
                if (selectedReason == null) {
                  _toast(ctx, 'Please select a reason for blocking.');
                  return;
                }
                String reason = selectedReason!;
                if (reason == 'Other') {
                  final custom = otherController.text.trim();
                  if (custom.isEmpty) {
                    _toast(ctx, 'Please specify the reason for "Other".');
                    return;
                  }
                  reason = custom;
                }
                Navigator.pop(ctx);
                final ok = await context
                    .read<AppState>()
                    .blockLocker(lk, booking, reason: reason);
                if (!context.mounted) return;
                _toast(
                    context,
                    ok
                        ? 'Locker ${lk.id} blocked. Student notified.'
                        : 'Failed to block locker. Please try again.');
              },
              child: Text('Block',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showForceReleaseDialog(
      BuildContext context, Locker lk, LockerBooking? booking) {
    String? selectedReason;
    final otherController = TextEditingController();
    const reasons = [
      'Student Graduated',
      'Student Withdrawn',
      'Emergency',
      'Maintenance',
      'Administrative Decision',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.lock_open_rounded, color: AppTheme.redDark, size: 24),
            SizedBox(width: 8),
            Text('Force Release Locker',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Force-release locker ${lk.id} and make it available for new bookings?',
                      style: const TextStyle(fontSize: 13)),
                  if (lk.studentId != null) ...[
                    const SizedBox(height: 8),
                    NoticeBox(
                      message:
                          'Current tenant ${lk.studentId} will lose access. Their booking will be completed.',
                      borderColor: AppTheme.goldDark,
                      bgColor: AppTheme.gold.withOpacity(0.12),
                      textColor: const Color(0xFF7A5B00),
                      icon: Icons.info_outline_rounded,
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text('Reason for force release (required):',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => RadioListTile<String>(
                        value: r,
                        groupValue: selectedReason,
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 0),
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        onChanged: (v) =>
                            setDialogState(() => selectedReason = v),
                      )),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: otherController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Please specify the reason...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textMuted))),
            TextButton(
              onPressed: () async {
                if (selectedReason == null) {
                  _toast(ctx, 'Please select a reason for force release.');
                  return;
                }
                String reason = selectedReason!;
                if (reason == 'Other') {
                  final custom = otherController.text.trim();
                  if (custom.isEmpty) {
                    _toast(ctx, 'Please specify the reason for "Other".');
                    return;
                  }
                  reason = custom;
                }
                Navigator.pop(ctx);
                final ok = await context
                    .read<AppState>()
                    .releaseLockerAdmin(lk, booking, reason: reason);
                if (!context.mounted) return;
                _toast(
                    context,
                    ok
                        ? 'Locker ${lk.id} force-released and available. Student notified.'
                        : 'Failed to release locker. Please try again.');
              },
              child: const Text('Force Release',
                  style: TextStyle(
                      color: AppTheme.redDark, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog for the intermediate "Approve Release Request" step (key lockers
  /// only). Moves releaseStatus from 'Requested' to 'Approved'. The admin
  /// then generates the return QR as a separate step.
  void _showApproveReleaseRequestDialog(
      BuildContext context, Locker lk, LockerBooking booking) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Approve Release Request?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Approve the release request for locker ${lk.id} from ${booking.studentId ?? 'student'}?',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              const NoticeBox(
                message:
                    'After approval, generate the Return QR so the student can return their key. '
                    'The release will be completed once the key is returned.',
                borderColor: Color(0xFF1565C0),
                bgColor: Color(0x0D1565C0),
                textColor: Color(0xFF0D47A1),
                icon: Icons.info_outline_rounded,
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final ok = await context
                  .read<AppState>()
                  .approveLockerReleaseRequest(lk, booking);
              if (!context.mounted) return;
              _toast(
                  context,
                  ok
                      ? 'Release request approved. Generate Return QR for the student.'
                      : 'Failed to approve release request. Please try again.');
            },
            child: const Text('Approve',
                style: TextStyle(
                    color: Color(0xFF1565C0), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Dialog for the final "Complete Release" / "Approve Release" step.
  /// For key lockers: requires key returned (releaseStatus == 'Returned').
  /// For digital lockers: can be done from 'Requested'.
  /// Frees the locker, refunds the deposit, and completes the booking.
  void _showApproveReleaseDialog(
      BuildContext context, Locker lk, LockerBooking booking) {
    final isDigital = lk.lockType == 'digital';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isDigital ? 'Approve Digital Locker Release' : 'Complete Release?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDigital
                    ? 'This locker does not require physical key return. The locker access code will immediately become invalid. Continue?'
                    : 'Complete the release for locker ${lk.id}? The key has been returned. The deposit will be refunded and the locker will become available.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (isDigital)
                const NoticeBox(
                  message:
                      'Approving this release will: revoke the digital access code, refund the security deposit, mark the booking as completed, and make the locker available for new bookings.',
                  borderColor: Color(0xFF2E7D32),
                  bgColor: Color(0x112E7D32),
                  textColor: Color(0xFF1E5A23),
                  icon: Icons.dialpad_rounded,
                )
              else
                const NoticeBox(
                  message:
                      'The key has been returned. The deposit will be refunded to the student.',
                  borderColor: Color(0xFF2E7D32),
                  bgColor: Color(0x112E7D32),
                  textColor: Color(0xFF1E5A23),
                  icon: Icons.check_circle_outline_rounded,
                ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final ok = await context
                  .read<AppState>()
                  .approveLockerRelease(lk, booking);
              if (!context.mounted) return;
              _toast(
                  context,
                  ok
                      ? isDigital
                          ? 'Release approved. Access code revoked. Deposit refunded. Locker is available.'
                          : 'Release completed. Deposit refunded. Locker is available.'
                      : 'Failed to complete release. Please try again.');
            },
            child: Text(
              isDigital ? 'Approve Release' : 'Confirm',
              style: const TextStyle(
                  color: Color(0xFF2E7D32), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog for an admin to move a locker issue to a new status, with an
  /// optional admin note. Calls [AppState.updateLockerIssueStatus] which
  /// also appends a locker history entry.
  void _showIssueStatusDialog(
    BuildContext context,
    LockerIssue issue,
    String newStatus,
  ) {
    final noteCtrl = TextEditingController();
    final isResolve = newStatus == 'Resolved';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isResolve ? 'Resolve Issue?' : 'Mark Under Review?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isResolve
                    ? 'Mark this issue as resolved? The student will see the update in real-time.'
                    : 'Move this issue to "Under Review"? The student will see the update in real-time.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.creamLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(issue.category.isNotEmpty ? issue.category : 'Issue',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(issue.description,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: isResolve
                      ? 'Resolution notes (optional)'
                      : 'Review notes (optional)',
                  hintStyle:
                      const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final note = noteCtrl.text.trim();
              final ok = await context.read<AppState>().updateLockerIssueStatus(
                    issue,
                    newStatus,
                    adminNotes: note.isNotEmpty ? note : null,
                  );
              if (!context.mounted) return;
              _toast(
                  context,
                  ok
                      ? isResolve
                          ? 'Issue resolved. Student notified in real-time.'
                          : 'Issue moved to Under Review.'
                      : 'Failed to update issue. Please try again.');
            },
            child: Text(
              isResolve ? 'Resolve' : 'Mark Under Review',
              style: TextStyle(
                  color: isResolve ? const Color(0xFF2E7D32) : AppTheme.red,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────
class _StatW extends StatelessWidget {
  final String label, value;
  const _StatW(this.label, this.value);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ]);
}

class _PricePill extends StatelessWidget {
  final String text;
  const _PricePill(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  final bool isBold;
  const _PriceRow(this.label, this.value, {this.isBold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                  color: isBold ? AppTheme.textPrimary : AppTheme.textMuted)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: isBold ? AppTheme.red : AppTheme.textPrimary)),
        ]),
      );
}

class _DurationBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _DurationBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: onTap != null
                ? AppTheme.red.withOpacity(0.1)
                : Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: onTap != null
                    ? AppTheme.red.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.2)),
          ),
          child: Icon(icon,
              size: 18, color: onTap != null ? AppTheme.red : Colors.grey),
        ),
      );
}

class _AdminActionButton extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _AdminActionButton(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: color.withOpacity(0.7))),
                ])),
            Icon(Icons.chevron_right_rounded,
                color: color.withOpacity(0.5), size: 20),
          ]),
        ),
      );
}

class _QrActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool enabled;
  final VoidCallback? onTap;

  const _QrActionCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_rounded, color: AppTheme.red),
                  SizedBox(width: 8),
                  Text('QR Verification',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 10),
              OutlineBtn(
                label: actionLabel,
                color: enabled ? AppTheme.red : Colors.grey,
                onPressed: enabled ? onTap : null,
              ),
            ],
          ),
        ),
      );
}
