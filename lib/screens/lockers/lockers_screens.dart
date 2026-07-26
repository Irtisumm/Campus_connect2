import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../widgets/release_stepper.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../services/data_service.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
  content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
  behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.textPrimary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
  title: Text(t), backgroundColor: Colors.transparent,
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => ctx.pop()));

// ── Screen 28: Locker Hub ────────────────────────────────────────
class LockerHubScreen extends StatelessWidget {
  const LockerHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final booking = dataService.myBookings.isNotEmpty ? dataService.myBookings.first : null;
        final hasActiveBooking = dataService.myBookings.any((b) => b.status == 'Active' || b.status == 'Pending Pickup');
        return Scaffold(
          body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (booking != null) ...[
              const SectionLabel('Active Booking'),
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.3), blurRadius: 18, offset: const Offset(0,5))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Icon(Icons.lock_rounded, color: Colors.white, size: 24), const SizedBox(width: 10), Text(booking.lockerId, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))]),
                  const SizedBox(height: 6),
                  Text(booking.location, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _PricePill('${booking.durationMonths} months'),
                    const SizedBox(width: 8),
                    _PricePill('RM${booking.totalPaid.toStringAsFixed(0)} paid'),
                  ]),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    _StatW('Start', fmtDate(booking.startDate)),
                    _StatW('End', fmtDate(booking.endDate)),
                    CountdownBadge(booking.daysLeft),
                  ]),
                ])).animate().fadeIn(delay: 50.ms).slideY(begin: 0.15),
              const SizedBox(height: 6),
              OutlineBtn(label: 'Manage My Locker', onPressed: () => context.push('/lockers/my-locker')),
            ] else ...[
              const NoticeBox(message: 'You don\'t have an active locker. You can browse and book one below.'),
            ],
            const SectionLabel('Services'),
            HubButton(
              icon: Icons.grid_view_rounded,
              label: 'Browse Available Lockers',
              subtitle: hasActiveBooking
                  ? 'You already have a locker (max 1)'
                  : '${dataService.lockers.where((l) => l.status == "Available").length} available now',
              isPrimary: !hasActiveBooking,
              onTap: () => context.push('/lockers/browse'),
            ).animate().fadeIn(delay:100.ms),
            HubButton(icon: Icons.manage_accounts_rounded, label: 'My Locker', subtitle: booking != null ? 'Booking ${booking.id}' : 'No active booking', onTap: () => context.push('/lockers/my-locker')).animate().fadeIn(delay:150.ms),
          ]))),
        );
      },
    );
  }
}

// ── Screen 29: Browse / Available Lockers ────────────────────────
class BrowseLockersScreen extends StatelessWidget {
  const BrowseLockersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final hasActiveBooking = dataService.myBookings.any((b) => b.status == 'Active' || b.status == 'Pending Pickup');
        final blocks = {'Block A, Level 1': 'LK-A', 'Block B, Level 2': 'LK-B', 'Block C, Level 1': 'LK-C'};
        return Scaffold(
          appBar: _appBar('Available Lockers', context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasActiveBooking)
              NoticeBox(
                message: 'You already have an active locker. Only 1 locker per student is allowed. Release your current locker to book a new one.',
                borderColor: AppTheme.goldDark,
                bgColor: AppTheme.gold.withOpacity(0.12),
                textColor: const Color(0xFF7A5B00),
                icon: Icons.warning_rounded,
              )
            else
              const NoticeBox(message: 'Locker rentals: 2-12 months, RM10/month + RM100 refundable deposit. Tap an available locker to book.'),
            ...blocks.entries.map((entry) {
              final lks = dataService.lockers.where((l) => l.location == entry.key).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionLabel(entry.key),
                GridView.count(crossAxisCount: 4, childAspectRatio: 1.1, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8,
                  children: lks.map((lk) {
                    Color c; Color tc;
                    switch (lk.status) {
                      case 'Available': c = AppTheme.red.withOpacity(0.12); tc = AppTheme.redDark; break;
                      case 'Active':   c = AppTheme.redLight.withOpacity(0.12); tc = AppTheme.red;     break;
                      case 'Pending Pickup': c = AppTheme.gold.withOpacity(0.2); tc = AppTheme.goldDark; break;
                      case 'Overdue':  c = AppTheme.danger.withOpacity(0.12); tc = AppTheme.danger;  break;
                      case 'Blocked':  c = Colors.grey.withOpacity(0.12);    tc = Colors.grey;       break;
                      default:         c = AppTheme.gold.withOpacity(0.2);   tc = AppTheme.goldDark;
                    }
                    final canBook = lk.status == 'Available' && !hasActiveBooking;
                    return GestureDetector(
                      onTap: canBook ? () => context.push('/lockers/detail/${lk.id}') : (lk.status == 'Available' && hasActiveBooking ? () => _toast(context, 'You already have a locker. Max 1 per student.') : null),
                      child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10), border: Border.all(color: tc.withOpacity(0.3))),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(lk.status == 'Blocked' ? Icons.block_rounded : Icons.lock_rounded, color: tc, size: 20),
                          const SizedBox(height: 4),
                          Text(lk.id.split('-').last, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tc)),
                          Text(lk.lockType == 'digital' ? 'D' : 'K', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: tc.withOpacity(0.6))),
                        ])));
                  }).toList()),
                const SizedBox(height: 8),
                Row(children: [
                  _Key(AppTheme.red.withOpacity(0.15), AppTheme.redDark, 'Available'),
                  const SizedBox(width: 10),
                  _Key(AppTheme.redLight.withOpacity(0.15), AppTheme.red, 'Taken'),
                  const SizedBox(width: 10),
                  _Key(AppTheme.gold.withOpacity(0.2), AppTheme.goldDark, 'Pending'),
                  const SizedBox(width: 10),
                  _Key(AppTheme.danger.withOpacity(0.15), AppTheme.danger, 'Overdue'),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  _Key(Colors.grey.withOpacity(0.15), Colors.grey, 'Blocked'),
                  const SizedBox(width: 14),
                  const Text('D = Digital Lock  K = Key Lock', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                ]),
              ]);
            }),
          ])),
        );
      },
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

  double get _deposit => 100.0;
  double get _monthlyRent => 10.0;
  double get _firstMonthRent => _monthlyRent;
  double get _totalDue => _deposit + _firstMonthRent;

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final hasActiveBooking = dataService.myBookings.any((b) => b.status == 'Active' || b.status == 'Pending Pickup');
        final lk = dataService.lockers.firstWhere((x) => x.id == widget.id, orElse: () => const Locker(
          id: '', location: '', status: '', studentId: null, endDate: '', daysLeft: null
        ));

        if (lk.id.isEmpty) {
          return Scaffold(
            appBar: _appBar('Book Locker', context),
            body: const EmptyState(title: 'Locker Not Found', subtitle: 'This locker does not exist.', icon: Icons.error_outline_rounded),
          );
        }

        if (hasActiveBooking) {
          return Scaffold(
            appBar: _appBar('Book Locker', context),
            body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const EmptyState(title: 'Already Have a Locker', subtitle: 'You can only have 1 locker at a time. Release your current locker first.', icon: Icons.lock_rounded),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: OutlineBtn(label: 'Go to My Locker', onPressed: () => context.go('/lockers/my-locker'))),
            ]),
          );
        }

        if (lk.status != 'Available') {
          return Scaffold(
            appBar: _appBar('Book Locker', context),
            body: const EmptyState(title: 'Locker Unavailable', subtitle: 'This locker is no longer available for booking.', icon: Icons.lock_outline_rounded),
          );
        }

        return Scaffold(
          appBar: _appBar('Book Locker', context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
            // Locker info card
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lk.id, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(lk.location, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  const SizedBox(height: 6),
                  Row(children: [
                    StatusBadge(lk.status),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: lk.lockType == 'digital' ? AppTheme.red.withOpacity(0.1) : AppTheme.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(lk.lockType == 'digital' ? Icons.dialpad_rounded : Icons.key_rounded, size: 11,
                          color: lk.lockType == 'digital' ? AppTheme.red : AppTheme.goldDark),
                        const SizedBox(width: 4),
                        Text(lk.lockType == 'digital' ? 'Digital Lock' : 'Key Lock',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                            color: lk.lockType == 'digital' ? AppTheme.red : AppTheme.goldDark)),
                      ]),
                    ),
                  ]),
                ])),
              ]),
            ]))).animate().fadeIn(delay: 50.ms),

            const SizedBox(height: 12),

            // Duration picker
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Select Duration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              const Text('Choose your rental period (2-12 months)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 14),
              Row(children: [
                Text('$_durationMonths months', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.red)),
                const Spacer(),
                _DurationBtn(icon: Icons.remove, onTap: _durationMonths > 2 ? () => setState(() => _durationMonths--) : null),
                const SizedBox(width: 8),
                _DurationBtn(icon: Icons.add, onTap: _durationMonths < 12 ? () => setState(() => _durationMonths++) : null),
              ]),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.red,
                  inactiveTrackColor: AppTheme.red.withOpacity(0.15),
                  thumbColor: AppTheme.red,
                  overlayColor: AppTheme.red.withOpacity(0.1),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _durationMonths.toDouble(),
                  min: 2, max: 12,
                  divisions: 10,
                  label: '$_durationMonths months',
                  onChanged: (v) => setState(() => _durationMonths = v.round()),
                ),
              ),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('2 months', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                Text('12 months', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ]),
            ]))).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 12),

            // Pricing breakdown
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Pricing Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const Divider(height: 20),
              _PriceRow('Monthly Rent', 'RM${_monthlyRent.toStringAsFixed(0)}/month'),
              _PriceRow('Duration', '$_durationMonths months'),
              _PriceRow('Total Rent', 'RM${(_monthlyRent * _durationMonths).toStringAsFixed(0)}'),
              const Divider(height: 16),
              _PriceRow('Refundable Deposit', 'RM${_deposit.toStringAsFixed(0)}', isBold: true),
              _PriceRow('First Month\'s Rent', 'RM${_firstMonthRent.toStringAsFixed(0)}', isBold: true),
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Due Now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('RM${_totalDue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
              const SizedBox(height: 8),
              Text('* Remaining rent of RM${((_monthlyRent * _durationMonths) - _firstMonthRent).toStringAsFixed(0)} billed monthly',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
            ]))).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 12),

            // Lock type info
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(lk.lockType == 'digital' ? Icons.dialpad_rounded : Icons.key_rounded, color: AppTheme.red, size: 20),
                const SizedBox(width: 8),
                Text(lk.lockType == 'digital' ? 'Digital Lock Info' : 'Key Lock Info',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              ]),
              const SizedBox(height: 10),
              if (lk.lockType == 'digital')
                NoticeBox(
                  message: 'After payment, your digital lock password will be displayed in the app under "My Locker". You can access it anytime.',
                  borderColor: AppTheme.red,
                  bgColor: AppTheme.red.withOpacity(0.06),
                  textColor: AppTheme.textSecondary,
                  icon: Icons.smartphone_rounded,
                )
              else
                NoticeBox(
                  message: 'After payment, please visit the Inventory Manager at Facilities Office, Block A Level 1, to collect your key within 3 working days.',
                  borderColor: AppTheme.goldDark,
                  bgColor: AppTheme.gold.withOpacity(0.12),
                  textColor: const Color(0xFF7A5B00),
                  icon: Icons.key_rounded,
                ),
            ]))).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 12),

            // Agreement checkbox
            Card(child: InkWell(
              onTap: () => setState(() => _agreed = !_agreed),
              borderRadius: BorderRadius.circular(16),
              child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppTheme.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'I agree to the Locker Rental Policy and understand the deposit of RM${_deposit.toStringAsFixed(0)} is refundable upon proper locker return.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                )),
              ])),
            )).animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 16),

            // Action buttons
            GradientButton(
              label: 'Confirm & Pay RM${_totalDue.toStringAsFixed(0)}',
              onPressed: _agreed ? () {
                context.read<DataService>().bookLocker(lk.id, durationMonths: _durationMonths);
                final updatedLk = context.read<DataService>().lockers.firstWhere((x) => x.id == lk.id);
                if (lk.lockType == 'digital' && updatedLk.digitalCode != null) {
                  _showDigitalCodeDialog(context, updatedLk.digitalCode!);
                } else {
                  _toast(context, 'Booking confirmed! Please collect your key at Facilities Office, Block A Level 1.');
                  context.go('/lockers');
                }
              } : null,
            ),
            const SizedBox(height: 10),
            OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
          ])),
        );
      },
    );
  }

  void _showDigitalCodeDialog(BuildContext context, String code) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.check_circle_rounded, color: AppTheme.red, size: 28),
        SizedBox(width: 10),
        Text('Booking Confirmed!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Your digital lock password is:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 8)),
        ),
        const SizedBox(height: 12),
        const Text('You can always view this code in "My Locker".',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton(
          onPressed: () { Navigator.pop(context); context.go('/lockers'); },
          child: const Text('Got it!', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    ));
  }
}

// ── Screen 31: My Locker ─────────────────────────────────────────
class MyLockerScreen extends StatelessWidget {
  const MyLockerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final booking = dataService.myBookings.isNotEmpty ? dataService.myBookings.first : null;
        if (booking == null) {
          return Scaffold(
            appBar: _appBar('My Locker', context),
            body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const EmptyState(title: 'No Active Booking', subtitle: 'You don\'t have a locker. Browse available lockers to book one.', icon: Icons.lock_open_rounded),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: GradientButton(label: 'Browse Lockers', onPressed: () => context.push('/lockers/browse'))),
            ]),
          );
        }

        // Find the locker to get lock type + digital code
        final locker = dataService.lockers.firstWhere((l) => l.id == booking.lockerId,
          orElse: () => const Locker(id: '', location: '', status: ''));
        final isKeyLocker = locker.lockType == 'key';
        final hasReleaseFlow = booking.releaseStatus != null || booking.status == 'Release Requested';
        final releaseStatus = booking.releaseStatus ?? (booking.status == 'Release Requested' ? 'Requested' : null);

        return Scaffold(
          appBar: _appBar('My Locker', context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Main booking card
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.3), blurRadius: 20, offset: const Offset(0,6))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.lock_rounded, color: Colors.white, size: 28), const SizedBox(width: 12), Text(booking.lockerId, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))]),
                const SizedBox(height: 6),
                Text(booking.location, style: TextStyle(color: Colors.white.withOpacity(0.85))),
                const SizedBox(height: 8),
                Row(children: [
                  _PricePill('${booking.durationMonths} months'),
                  const SizedBox(width: 8),
                  _PricePill(locker.lockType == 'digital' ? 'Digital Lock' : 'Key Lock'),
                  const SizedBox(width: 8),
                  _PricePill(booking.status),
                ]),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _StatW('Start', fmtDate(booking.startDate)),
                  _StatW('End', fmtDate(booking.endDate)),
                  _StatW('Status', booking.status),
                  CountdownBadge(booking.daysLeft),
                ]),
              ])).animate().fadeIn(delay: 50.ms).slideY(begin: 0.15),

            // Digital lock code section
            if (locker.lockType == 'digital' && locker.digitalCode != null) ...[
              const SectionLabel('Lock Password'),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                const Row(children: [
                  Icon(Icons.dialpad_rounded, color: AppTheme.red, size: 22),
                  SizedBox(width: 10),
                  Expanded(child: Text('Digital Lock Code', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.red.withOpacity(0.2)),
                  ),
                  child: Text(locker.digitalCode!, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.red, letterSpacing: 8)),
                ),
                const SizedBox(height: 8),
                const Text('Use this code to unlock your locker', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ]))).animate().fadeIn(delay: 100.ms),
            ] else if (locker.lockType == 'key') ...[
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
              if (booking.status == 'Pending Pickup' && !booking.keyCollected)
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
                            hintText: 'Enter key collection QR code',
                            onSubmit: (code) {
                              final ok = context.read<DataService>().scanKeyCollectionQR(booking.id, code);
                              if (!ok) {
                                _toast(context, 'Invalid QR code or key already collected.');
                                return false;
                              }
                              _toast(context, 'Key collection verified. Locker is now active.');
                              return true;
                            },
                          ),
                ),
            ],

            // Payment info
            const SectionLabel('Payment Details'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              _PriceRow('Deposit (refundable)', 'RM${booking.deposit.toStringAsFixed(0)}'),
              _PriceRow('Monthly Rent', 'RM${booking.monthlyRent.toStringAsFixed(0)}/month'),
              _PriceRow('Duration', '${booking.durationMonths} months'),
              const Divider(height: 16),
              _PriceRow('Amount Paid', 'RM${booking.totalPaid.toStringAsFixed(0)}', isBold: true),
            ]))).animate().fadeIn(delay: 150.ms),

            if (hasReleaseFlow) ...[
              const SectionLabel('Release Progress'),
              ReleaseStepper(status: releaseStatus ?? 'Requested'),
              if (isKeyLocker)
                _QrActionCard(
                  title: 'Key Return Verification',
                  subtitle: booking.keyReturnQR == null
                      ? (releaseStatus == 'Requested'
                          ? 'Waiting for admin to generate return QR.'
                          : 'No return QR available yet.')
                      : (booking.keyReturned
                          ? 'Key return verified. Waiting for admin approval.'
                          : 'Scan return QR to confirm key handover.'),
                  actionLabel: 'Scan Return QR',
                  enabled: booking.keyReturnQR != null && !booking.keyReturned,
                  onTap: (booking.keyReturnQR != null && !booking.keyReturned)
                      ? () => _showQrScanDialog(
                            context,
                            title: 'Scan Return QR',
                            hintText: 'Enter key return QR code',
                            onSubmit: (code) {
                              final ok = context.read<DataService>().scanKeyReturnQR(booking.id, code);
                              if (!ok) {
                                _toast(context, 'Invalid return QR code.');
                                return false;
                              }
                              _toast(context, 'Key return verified. Waiting for admin approval.');
                              return true;
                            },
                          )
                      : null,
                ),
            ],

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
                  : () => _toast(context, 'Extension available only when remaining time is 1 month or less. You have ${booking.daysLeft} days remaining.'),
            ),
            HubButton(
              icon: Icons.report_problem_rounded,
              label: 'Report Locker Issue',
              subtitle: 'Damage, malfunction, etc.',
              onTap: () => _showLockerIssueDialog(context, booking.lockerId),
            ),
            if (!hasReleaseFlow)
              HubButton(
                icon: Icons.cancel_rounded,
                label: 'Request Locker Release',
                subtitle: 'Start key-return flow and refund process',
                isAmber: false,
                iconColor: AppTheme.danger,
                onTap: () => _showReleaseRequestDialog(context, booking),
              )
            else if (releaseStatus == 'Returned')
              const NoticeBox(
                message: 'Key return completed. Waiting for admin approval to finalize release and refund.',
                borderColor: Color(0xFF2E7D32),
                bgColor: Color(0x112E7D32),
                textColor: Color(0xFF1E5A23),
                icon: Icons.hourglass_top_rounded,
              ),
          ])),
        );
      },
    );
  }

  void _showReleaseRequestDialog(BuildContext context, LockerBooking booking) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Request Locker Release?'),
      content: Text(
        'Start release for booking ${booking.id}? You will need to return your key and wait for admin approval before refund is processed.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () {
          Navigator.pop(context);
          context.read<DataService>().requestLockerRelease(booking.id);
          _toast(context, 'Release requested. Please return your key at the admin office.');
        }, child: const Text('Request', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _showExtensionDialog(BuildContext context, LockerBooking booking) {
    if (booking.daysLeft > 30) {
      _toast(context, 'Extension is only available when 30 days or less remain.');
      return;
    }

    var months = 1;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Request Extension', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remaining days: ${booking.daysLeft}. Choose additional months to extend.',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Additional Months', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: months > 1 ? () => setDialogState(() => months--) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$months', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: months < 6 ? () => setDialogState(() => months++) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              NoticeBox(
                message:
                    'Additional cost: RM${(booking.monthlyRent * months).toStringAsFixed(0)} ($months month(s) x RM${booking.monthlyRent.toStringAsFixed(0)})',
                borderColor: AppTheme.red,
                bgColor: AppTheme.red.withOpacity(0.08),
                textColor: AppTheme.textSecondary,
                icon: Icons.payments_rounded,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () {
                final ok = context.read<DataService>().requestLockerExtension(booking.id, months);
                if (!ok) {
                  _toast(context, 'Unable to process extension request.');
                  return;
                }
                Navigator.pop(dialogCtx);
                _toast(
                  context,
                  'Extension successful: +$months month(s), RM${(booking.monthlyRent * months).toStringAsFixed(0)} added.',
                );
              },
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLockerIssueDialog(BuildContext context, String lockerId) {
    final descriptionCtrl = TextEditingController();
    var photoCount = 0;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Report Locker Issue', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Issue description',
                  hintText: 'Describe what happened...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Attached photos (mock):', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: photoCount > 0 ? () => setDialogState(() => photoCount--) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$photoCount', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: photoCount < 10 ? () => setDialogState(() => photoCount++) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () {
                final desc = descriptionCtrl.text.trim();
                if (desc.isEmpty) {
                  _toast(context, 'Please enter issue details before submitting.');
                  return;
                }
                context.read<DataService>().reportLockerIssue(lockerId, desc, photoCount);
                Navigator.pop(dialogCtx);
                _toast(context, 'Locker issue submitted. Admin has been notified.');
              },
              child: const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrScanDialog(
    BuildContext context, {
    required String title,
    required String hintText,
    required bool Function(String code) onSubmit,
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
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              final code = qrCtrl.text.trim();
              if (code.isEmpty) {
                _toast(context, 'Please enter a QR code.');
                return;
              }
              final ok = onSubmit(code);
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
class AdminLockerDashboardScreen extends StatelessWidget {
  const AdminLockerDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final lks = dataService.lockers;
        final avail   = lks.where((l) => l.status == 'Available').length;
        final active  = lks.where((l) => l.status == 'Active').length;
        final pending = lks.where((l) => l.status == 'Pending Pickup').length;
        final overdue = lks.where((l) => l.status == 'Overdue').length;
        final blocked = lks.where((l) => l.status == 'Blocked').length;
        final occupied = lks.where((l) => l.studentId != null).length;
        return Scaffold(
          body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatCard(value: '${lks.length}', label: 'Total')),
              const SizedBox(width: 8),
              Expanded(child: StatCard(value: '$avail', label: 'Available', valueColor: AppTheme.redDark, bgColor: AppTheme.red.withOpacity(0.07))),
              const SizedBox(width: 8),
              Expanded(child: StatCard(value: '$occupied', label: 'Rented', valueColor: AppTheme.red, bgColor: AppTheme.red.withOpacity(0.06))),
              const SizedBox(width: 8),
              Expanded(child: StatCard(value: '$overdue', label: 'Overdue', valueColor: const Color(0xFFB03030), bgColor: const Color(0x08D65E5E))),
            ]).animate().fadeIn(delay:50.ms),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: StatCard(value: '$active', label: 'Active')),
              const SizedBox(width: 8),
              Expanded(child: StatCard(value: '$pending', label: 'Pending', valueColor: AppTheme.goldDark, bgColor: AppTheme.gold.withOpacity(0.15))),
              const SizedBox(width: 8),
              Expanded(child: StatCard(value: '$blocked', label: 'Blocked', valueColor: Colors.grey, bgColor: Colors.grey.withOpacity(0.08))),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ]).animate().fadeIn(delay:100.ms),
            const SectionLabel('Actions'),
            HubButton(icon: Icons.grid_view_rounded, label: 'Locker Grid', subtitle: 'View all locker statuses', onTap: () => context.push('/admin/lockers/list')),
            HubButton(icon: Icons.person_search_rounded, label: 'Student Lookup', subtitle: 'Find by student ID', isAmber: true, onTap: () => _toast(context, 'Student lookup feature coming soon')),
            if (overdue > 0) NoticeBox(message: '$overdue locker(s) are overdue. Action required.', borderColor: AppTheme.danger, bgColor: AppTheme.danger.withOpacity(0.06), textColor: const Color(0xFF8B2020), icon: Icons.warning_rounded),
          ]))),
        );
      },
    );
  }
}

// ── Screen 34: Admin Lockers List ────────────────────────────────
class AdminLockersListScreen extends StatelessWidget {
  const AdminLockersListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final data = dataService.lockers;
        return Scaffold(
          appBar: _appBar('All Lockers', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
              final lk = data[i];
              return CardRow(
                title: lk.id, subtitle: lk.location, status: lk.status,
                extra: lk.studentId != null ? 'Student: ${lk.studentId}  |  ${lk.lockType == "digital" ? "Digital" : "Key"} Lock' : '${lk.lockType == "digital" ? "Digital" : "Key"} Lock',
                trailing: lk.daysLeft != null ? CountdownBadge(lk.daysLeft!) : null,
                onTap: () => context.push('/admin/lockers/detail/${lk.id}'),
              ).animate().fadeIn(delay: (i*50).ms).slideY(begin:0.1);
            })),
          ]),
        );
      },
    );
  }
}

// ── Screen 35: Admin Locker Detail (fully functional) ────────────
class AdminLockerDetailScreen extends StatefulWidget {
  final String id;
  const AdminLockerDetailScreen({super.key, required this.id});
  @override
  State<AdminLockerDetailScreen> createState() => _AdminLockerDetailScreenState();
}

class _AdminLockerDetailScreenState extends State<AdminLockerDetailScreen> {
  final TextEditingController _noticeController = TextEditingController();
  final TextEditingController _blockReasonController = TextEditingController();

  @override
  void dispose() {
    _noticeController.dispose();
    _blockReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final lk = dataService.lockers.firstWhere((x) => x.id == widget.id, orElse: () => const Locker(
          id: '', location: '', status: '', studentId: null, endDate: '', daysLeft: null
        ));
        final hist = dataService.lockerHistory[lk.id] ?? [];
        final isOccupied = lk.studentId != null;
        LockerBooking? booking;
        for (final b in dataService.myBookings) {
          if (b.lockerId == lk.id) {
            booking = b;
            break;
          }
        }
        final lockerBooking = booking;
        final isPendingKeyPickup = lockerBooking != null &&
            lk.lockType == 'key' &&
            lockerBooking.status == 'Pending Pickup' &&
            !lockerBooking.keyCollected;
        final canGenerateReturnQr = lockerBooking != null &&
            lk.lockType == 'key' &&
            lockerBooking.releaseStatus == 'Requested' &&
            lockerBooking.keyReturnQR == null;
        final canApproveRelease = lockerBooking != null &&
            ((lk.lockType == 'key' &&
                    lockerBooking.releaseStatus == 'Returned' &&
                    lockerBooking.keyReturned) ||
                (lk.lockType == 'digital' &&
                    lockerBooking.releaseStatus == 'Requested'));

        return Scaffold(
          appBar: _appBar(lk.id, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 8),

            // Locker info card
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [Expanded(child: Text(lk.id, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), StatusBadge(lk.status)]),
              const Divider(height: 18),
              InfoRow(label: 'Location', value: lk.location),
              InfoRow(label: 'Lock Type', value: lk.lockType == 'digital' ? 'Digital Lock' : 'Key Lock'),
              InfoRow(label: 'Monthly Rent', value: 'RM${lk.monthlyRent.toStringAsFixed(0)}'),
              InfoRow(label: 'Deposit', value: 'RM${lk.deposit.toStringAsFixed(0)}${lk.depositRefunded ? " (Refunded)" : ""}'),
              if (lk.studentId != null) InfoRow(label: 'Student ID', value: lk.studentId!),
              if (lk.startDate != null && lk.startDate!.isNotEmpty) InfoRow(label: 'Start Date', value: fmtDate(lk.startDate!)),
              if (lk.endDate != null && lk.endDate!.isNotEmpty) InfoRow(label: 'End Date', value: fmtDate(lk.endDate!)),
              if (lk.digitalCode != null) InfoRow(label: 'Digital Code', value: lk.digitalCode!),
              if (lk.daysLeft != null) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 8), child: CountdownBadge(lk.daysLeft!))),
            ]))).animate().fadeIn(delay: 50.ms),

            // Admin Actions
            const SectionLabel('Admin Actions'),

            if (booking != null && booking.releaseStatus != null)
              ReleaseStepper(status: booking.releaseStatus!),

            if (isPendingKeyPickup) ...[
              _AdminActionButton(
                icon: Icons.qr_code_2_rounded,
                label: 'Generate Key Collection QR',
                subtitle: 'Generate one-time QR for key pickup',
                color: AppTheme.goldDark,
                onTap: () {
                  final code = context.read<DataService>().generateKeyCollectionQR(booking!.id);
                  _showQrCodeDialog(
                    context,
                    title: 'Key Collection QR',
                    code: code,
                    helper:
                        'Share this code at the counter. Student must scan this code in My Locker to activate booking.',
                  );
                },
              ).animate().fadeIn(delay: 80.ms),
            ],

            if (canGenerateReturnQr) ...[
              _AdminActionButton(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Generate Return QR',
                subtitle: 'Generate QR for key return verification',
                color: const Color(0xFF1565C0),
                onTap: () {
                  final code = context.read<DataService>().generateKeyReturnQR(booking!.id);
                  _showQrCodeDialog(
                    context,
                    title: 'Key Return QR',
                    code: code,
                    helper:
                        'Student must scan this return QR in My Locker after handing over the key.',
                  );
                },
              ).animate().fadeIn(delay: 90.ms),
            ],

            if (canApproveRelease) ...[
              _AdminActionButton(
                icon: Icons.verified_rounded,
                label: 'Approve Release',
                subtitle: 'Finalize release and process deposit refund',
                color: const Color(0xFF2E7D32),
                onTap: () {
                  context.read<DataService>().approveLockerRelease(booking!.id);
                  _toast(context, 'Release approved. Locker is available and refund notice sent.');
                },
              ).animate().fadeIn(delay: 95.ms),
            ],

            // Terminate Agreement (only if occupied)
            if (isOccupied) ...[
              _AdminActionButton(
                icon: Icons.cancel_rounded,
                label: 'Terminate Agreement',
                subtitle: 'End rental, deposit forfeited',
                color: AppTheme.danger,
                onTap: () => _showTerminateDialog(context, lk),
              ).animate().fadeIn(delay: 100.ms),
            ],

            // Block Locker (available for non-blocked lockers)
            if (lk.status != 'Blocked') ...[
              _AdminActionButton(
                icon: Icons.block_rounded,
                label: 'Block Locker',
                subtitle: 'Mark as unavailable for maintenance/issues',
                color: Colors.grey.shade700,
                onTap: () => _showBlockDialog(context, lk),
              ).animate().fadeIn(delay: 150.ms),
            ],

            // Release Locker (for blocked/occupied lockers)
            if (lk.status == 'Blocked' || isOccupied) ...[
              _AdminActionButton(
                icon: Icons.lock_open_rounded,
                label: 'Release Locker',
                subtitle: 'Make locker available again',
                color: AppTheme.redDark,
                onTap: () => _showReleaseDialog(context, lk),
              ).animate().fadeIn(delay: 200.ms),
            ],

            // Send Notice (only if tenant exists)
            if (isOccupied) ...[
              const SectionLabel('Send Notice to Tenant'),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                TextField(
                  controller: _noticeController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Type your notice/reminder message...',
                    hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.red.withOpacity(0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.red.withOpacity(0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.red)),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (lk.status == 'Overdue')
                    Expanded(child: OutlineBtn(label: 'Send Overdue Reminder', color: AppTheme.danger, onPressed: () {
                      final msg = 'OVERDUE NOTICE: Your locker ${lk.id} rental has expired. Please renew or return the locker immediately to avoid penalties.';
                      dataService.sendLockerNotice(lk.id, msg);
                      _toast(context, 'Overdue reminder sent to ${lk.studentId}');
                    })),
                  if (lk.status == 'Overdue') const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'Send Notice', onPressed: () {
                    final msg = _noticeController.text.trim();
                    if (msg.isEmpty) {
                      _toast(context, 'Please enter a message');
                      return;
                    }
                    dataService.sendLockerNotice(lk.id, msg);
                    _noticeController.clear();
                    _toast(context, 'Notice sent to ${lk.studentId}');
                  })),
                ]),
              ]))).animate().fadeIn(delay: 250.ms),
            ],

            // History
            if (hist.isNotEmpty) ...[
              const SectionLabel('History'),
              ...hist.reversed.map((h) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.creamLight, borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${h.timestamp} \u00b7 ${h.staffId}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (h.reason != null) Text(h.reason!, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ])))),
            ],
          ])),
        );
      },
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
            Text(helper, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showTerminateDialog(BuildContext context, Locker lk) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.warning_rounded, color: AppTheme.danger, size: 24),
        SizedBox(width: 8),
        Text('Terminate Agreement', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('This will terminate the rental agreement for locker ${lk.id} (${lk.studentId}).', style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        const NoticeBox(
          message: 'The student\'s deposit will be forfeited. The locker will become available for new bookings.',
          borderColor: AppTheme.danger,
          bgColor: Color(0x0ED65E5E),
          textColor: Color(0xFF8B2020),
          icon: Icons.warning_rounded,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
        TextButton(onPressed: () {
          Navigator.pop(context);
          context.read<DataService>().terminateLocker(lk.id);
          _toast(context, 'Agreement terminated for ${lk.id}. Locker is now available.');
        }, child: const Text('Terminate', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _showBlockDialog(BuildContext context, Locker lk) {
    _blockReasonController.clear();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Block Locker', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Block locker ${lk.id}? This will mark it as unavailable.', style: const TextStyle(fontSize: 13)),
        if (lk.studentId != null) ...[
          const SizedBox(height: 8),
          NoticeBox(
            message: 'This locker is rented by ${lk.studentId}. Blocking will remove their booking.',
            borderColor: AppTheme.goldDark,
            bgColor: AppTheme.gold.withOpacity(0.12),
            textColor: const Color(0xFF7A5B00),
            icon: Icons.warning_rounded,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _blockReasonController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Reason for blocking (optional)',
            hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
        TextButton(onPressed: () {
          Navigator.pop(context);
          final reason = _blockReasonController.text.trim();
          context.read<DataService>().blockLocker(lk.id, reason: reason.isNotEmpty ? reason : null);
          _toast(context, 'Locker ${lk.id} blocked.');
        }, child: Text('Block', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _showReleaseDialog(BuildContext context, Locker lk) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Release Locker', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Release locker ${lk.id} and make it available for new bookings?', style: const TextStyle(fontSize: 13)),
        if (lk.studentId != null) ...[
          const SizedBox(height: 8),
          NoticeBox(
            message: 'Current tenant ${lk.studentId} will lose access. Their booking will be removed.',
            borderColor: AppTheme.goldDark,
            bgColor: AppTheme.gold.withOpacity(0.12),
            textColor: const Color(0xFF7A5B00),
            icon: Icons.info_outline_rounded,
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
        TextButton(onPressed: () {
          Navigator.pop(context);
          context.read<DataService>().releaseLockerAdmin(lk.id);
          _toast(context, 'Locker ${lk.id} released and available.');
        }, child: const Text('Release', style: TextStyle(color: AppTheme.redDark, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}

// ── Shared Widgets ────────────────────────────────────────────────
class _StatW extends StatelessWidget {
  final String label, value;
  const _StatW(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
  ]);
}

class _Key extends StatelessWidget {
  final Color bg, fg; final String label;
  const _Key(this.bg, this.fg, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3), border: Border.all(color: fg.withOpacity(0.4)))),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
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
    child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
  );
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  final bool isBold;
  const _PriceRow(this.label, this.value, {this.isBold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500, color: isBold ? AppTheme.textPrimary : AppTheme.textMuted)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600, color: isBold ? AppTheme.red : AppTheme.textPrimary)),
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
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: onTap != null ? AppTheme.red.withOpacity(0.1) : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onTap != null ? AppTheme.red.withOpacity(0.3) : Colors.grey.withOpacity(0.2)),
      ),
      child: Icon(icon, size: 18, color: onTap != null ? AppTheme.red : Colors.grey),
    ),
  );
}

class _AdminActionButton extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _AdminActionButton({required this.icon, required this.label, required this.subtitle, required this.color, required this.onTap});
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
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
        ])),
        Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5), size: 20),
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
              Text('QR Verification', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
