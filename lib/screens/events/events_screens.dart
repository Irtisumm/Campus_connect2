import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../widgets/common.dart';
import '../../widgets/delete_countdown_dialog.dart';
import '../../data/mock_data.dart' hide Candidate;
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';
import 'widgets/event_widgets.dart';
export 'events_hub_screen.dart';
export 'election_info_screen.dart';
export 'create_event_screen.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
  content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
  behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.textPrimary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
  title: Text(t), backgroundColor: Colors.transparent,
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => ctx.pop()));

// ── Screen 23: Event Detail ──────────────────────────────────────
class EventDetailScreen extends StatelessWidget {
  final String id;
  const EventDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final userId = appState.userId;
        if (userId == null || userId.isEmpty) {
          return Scaffold(
            appBar: _appBar('Event Details', context),
            body: const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in required',
              subtitle: 'Please sign in to view event details.',
            ),
          );
        }
        return StreamBuilder<Event?>(
          stream: appState.watchEvent(id),
          builder: (context, eventSnap) {
            if (eventSnap.hasError) {
              return Scaffold(
                appBar: _appBar('Event Details', context),
                body: const EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load event',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }
            final ev = eventSnap.data ?? const Event(
              id: '', title: 'Event Not Found', date: '', time: '', location: '',
              category: '', organizer: '', description: '', status: ''
            );
            final userJoined = ev.attendeeIds.contains(userId);

            return StreamBuilder<List<EventJoining>>(
              stream: appState.watchMyJoinings(),
              builder: (context, joiningsSnap) {
                if (joiningsSnap.hasError) {
                  return Scaffold(
                    appBar: _appBar(ev.title, context),
                    body: const EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Unable to load event',
                      subtitle: 'Please check your connection and try again.',
                    ),
                  );
                }
                final myJoining = (joiningsSnap.data ?? const <EventJoining>[])
                    .where((j) => j.eventId == ev.id && j.status == 'Approved')
                    .firstOrNull;
                String? qrCode;
                if (userJoined) {
                  qrCode = myJoining?.qrTicketCode ?? 'QR-${ev.id}-$userId';
                }

                return Scaffold(
          appBar: _appBar(ev.title, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: EventCover(
                category: ev.category,
                coverImageUrl: ev.coverImageUrl,
                radius: BorderRadius.circular(18),
                iconSize: 64,
              ),
            ),
            const SizedBox(height: 14),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              InfoRow(label: 'Date', value: fmtDate(ev.date)),
              InfoRow(label: 'Time', value: ev.time),
              InfoRow(label: 'Location', value: ev.location),
              InfoRow(label: 'Organizer', value: ev.organizer),
              InfoRow(label: 'Category', value: ev.category),
              InfoRow(label: 'Status', value: ev.status),
              if (ev.isPrivate) ...[
                const Divider(height: 12),
                LimitedBox(maxWidth: 200, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('🔒 Club-Based Event\nClub ID may be required', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gold)))),
              ],
              if (ev.isPaid) ...[
                const Divider(height: 12),
                LimitedBox(maxWidth: 200, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text('Price: RM${ev.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.red)))),
              ],
              const Divider(height: 20),
              Text(ev.description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.7)),
              if (ev.attendeeIds.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  ev.maxParticipants > 0
                      ? 'Attendees: ${ev.attendeeIds.length} / ${ev.maxParticipants}'
                      : 'Attendees: ${ev.attendeeIds.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted)),
                if (ev.maxParticipants > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    ev.isFull
                        ? 'Event Full'
                        : '${ev.availableSlots} slot${ev.availableSlots == 1 ? '' : 's'} available',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ev.isFull ? AppTheme.danger : AppTheme.textMuted)),
                ],
              ],
            ]))),
            // ── Creator management shortcut ─────────────────────────
            if (ev.hostStudentId != null &&
                ev.hostStudentId == userId &&
                ev.status == 'Published') ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => context.push('/events/manage/${ev.id}'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                      color: AppTheme.red.withOpacity(0.25),
                      blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Manage My Event', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 6),
            GradientButton(label: '📅 Add to Calendar', onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to calendar ✓')))),
            const SizedBox(height: 10),
            if (!userJoined)
              if (ev.isFull)
                Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                        color: AppTheme.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.danger.withOpacity(0.3))),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.do_not_disturb_rounded,
                              color: AppTheme.danger, size: 18),
                          SizedBox(width: 8),
                          Text('Registration Closed — Event Full',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.danger,
                                  fontSize: 12))
                        ]))
              else
                GradientButton(
                  label: ev.isPaid
                      ? '💳 Purchase Ticket'
                      : (ev.isPrivate
                          ? '📝 Request to Join'
                          : '✅ Join Event'),
                  onPressed: () =>
                      _showJoinDialog(context, appState, ev, userId),
                )
            else ...[
              Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3))),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18), SizedBox(width: 8), Text('You have joined this event', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4CAF50), fontSize: 12))])),
              if (qrCode != null) ...[
                const SizedBox(height: 12),
                _buildQRCodeSection(context, qrCode),
              ],
            ],
            const SizedBox(height: 10),
            OutlineBtn(label: '🔔 Remind Me', onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder set!')))),
          ])),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildQRCodeSection(BuildContext context, String qrCode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Your Ticket', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrCode,
                version: QrVersions.auto,
                size: 200,
                gapless: false,
                errorStateBuilder: (cxt, err) => const SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(child: Text('Error generating QR')),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(qrCode, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: OutlineBtn(
                    label: '📋 Copy Code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: qrCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ QR Code copied to clipboard!'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinDialog(BuildContext context, AppState appState, Event event, String userId) {
    final nameCtrl = TextEditingController();
    final courseCtrl = TextEditingController();
    final clubCtrl = TextEditingController();
    final key = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Join ${event.title}', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: courseCtrl,
                decoration: const InputDecoration(labelText: 'Course/Program'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              if (event.isPrivate) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: clubCtrl,
                  decoration: InputDecoration(
                    labelText: event.clubIdRequired ? 'Club ID *' : 'Club ID (Optional)',
                  ),
                  validator: (v) => event.clubIdRequired && v!.isEmpty ? 'Club ID is required' : null,
                ),
              ],
              if (event.isPaid) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Price: RM${event.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('You will be prompted for payment after confirmation.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              if (!key.currentState!.validate()) return;
              Navigator.pop(dialogCtx);
              // Capacity guard: refuse if the event is already full.
              if (event.isFull) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Registration Closed — Event Full')));
                return;
              }
              // Check for an existing registration before attempting to join.
              final existing = await appState.joiningFor(event.id);
              if (existing != null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('You have already registered for this event.')));
                return;
              }
              final joining = await appState.joinEvent(
                event,
                name: nameCtrl.text.trim(),
                courseName: courseCtrl.text.trim(),
                clubId: clubCtrl.text.isNotEmpty ? clubCtrl.text.trim() : null,
              );
              if (joining == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to join event. Please try again.')));
                return;
              }
              if (event.isPaid) {
                _showPaymentDialog(context, appState, event, joining);
              } else if (event.isPrivate) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request submitted. Waiting for approval...')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully joined! Your QR ticket is ready.')));
              }
            },
            child: const Text('Continue', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(BuildContext context, AppState appState, Event event, EventJoining joining) {
    final amountCtrl = TextEditingController(text: event.price.toStringAsFixed(2));
    final cardNumberCtrl = TextEditingController();
    final expiryCtrl = TextEditingController();
    final cvvCtrl = TextEditingController();
    bool isPaymentProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Payment for Event', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Event Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(event.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Divider(),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Amount:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('RM${event.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.red, fontSize: 16)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              // Payment Form (Mock)
              const Text('Card Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: cardNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Card Number',
                  hintText: '1234 5678 9012 3456',
                  prefixIcon: Icon(Icons.credit_card_rounded),
                ),
                enabled: !isPaymentProcessing,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: expiryCtrl,
                    decoration: const InputDecoration(labelText: 'MM/YY', hintText: '12/25'),
                    enabled: !isPaymentProcessing,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: cvvCtrl,
                    decoration: const InputDecoration(labelText: 'CVV', hintText: '123'),
                    enabled: !isPaymentProcessing,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Icon(Icons.lock_outline_rounded, color: Color(0xFF4CAF50), size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Your payment is secure and encrypted', style: TextStyle(fontSize: 11, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600))),
                ]),
              ),
            ]),
          ),
          actions: [
            if (!isPaymentProcessing)
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              onPressed: isPaymentProcessing ? null : () {
                setState(() => isPaymentProcessing = true);
                // Simulate payment processing, then persist the result.
                Future.delayed(const Duration(seconds: 2), () async {
                  final ok = await appState.completeJoiningPayment(joining.id);
                  if (!dialogCtx.mounted) return;
                  if (ok) {
                    Navigator.pop(dialogCtx);
                    _showQRCodeDialog(context, joining, event);
                  } else {
                    setState(() => isPaymentProcessing = false);
                    _toast(context, '❌ Payment failed. Please try again.');
                  }
                });
              },
              child: isPaymentProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Text('Complete Payment', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showQRCodeDialog(BuildContext context, EventJoining joining, Event event) {
    final qrCode = joining.qrTicketCode ?? 'QR-${joining.eventId}-${joining.studentId}';
    final scaffold = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('✅ Payment Successful!', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4CAF50))),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.textMuted.withOpacity(0.2))),
                  // Fixed SizedBox: QrImageView uses an internal LayoutBuilder,
                  // which throws when AlertDialog measures content via an
                  // intrinsic-width pass. A tight box answers with its own size.
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: QrImageView(
                      data: qrCode,
                      version: QrVersions.auto,
                      size: 200,
                      gapless: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(qrCode, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted)),
                const SizedBox(height: 16),
                Text('Event: ${event.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Price Paid: RM${event.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.2))),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📌 Save Your QR Code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                SizedBox(height: 6),
                Text('Screenshot your QR code or copy the code below to access your ticket anytime.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Done')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: qrCode));
              scaffold.showSnackBar(const SnackBar(
                content: Text('✅ QR Code copied to clipboard!'),
                behavior: SnackBarBehavior.floating,
              ));
              Navigator.pop(dialogCtx);
            },
            child: const Text('� Copy QR Code', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Screen 24: Elections Info ────────────────────────────────────
@Deprecated('Use the redesigned ElectionsInfoScreen from election_info_screen.dart.')
class LegacyElectionsInfoScreen extends StatelessWidget {
  const LegacyElectionsInfoScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar('Student Elections 2026', context),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NoticeBox(message: 'This is an information-only page. No online voting is conducted here.', borderColor: AppTheme.goldDark, bgColor: AppTheme.gold.withOpacity(0.12), textColor: const Color(0xFF7A5B00), icon: Icons.info_outline_rounded),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('About'),
          const Text('The Student Council Elections are held annually to elect student representatives. Physical ballot casting is at designated polling stations on campus.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.65)),
          const SectionLabel('Timeline'),
          const _TL('25 Mar 2026', 'Candidate registration closes'),
          const _TL('28–30 Mar 2026', 'Campaigning period'),
          const _TL('1 Apr 2026', 'Polling Day (Block A Foyer, 8am–5pm)'),
          const _TL('2 Apr 2026', 'Results announced'),
          const SectionLabel('Open Positions'),
          ...['President','Vice President','Secretary General','Treasurer'].map((p) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [const Icon(Icons.person_rounded, size: 16, color: AppTheme.red), const SizedBox(width: 8), Text(p, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]))),
        ]))),
        const SectionLabel('Candidates'),
        ...MockData.candidates.map((c) => Container(margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.red.withOpacity(0.1)), boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.07), blurRadius: 8, offset: const Offset(0,2))]),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 48, decoration: const BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle), child: Center(child: Text(c.name[0], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(c.programme, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Running for: ${c.position}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.red)),
              const SizedBox(height: 4),
              Text(c.manifesto, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.55)),
            ])),
          ])))),
      ])),
    );
  }
}

// ── Screen 25: Admin Events List ─────────────────────────────────
class AdminEventsListScreen extends StatefulWidget {
  const AdminEventsListScreen({super.key});
  @override
  State<AdminEventsListScreen> createState() => _AdminEventsListScreenState();
}

class _AdminEventsListScreenState extends State<AdminEventsListScreen> {
  bool _showPending = true;

  void _showSendNoticeDialog(BuildContext context, AppState appState, Event ev) {
    final noticeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Notice to Host', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event: ${ev.title}', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: noticeCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notice message',
                hintText: 'Enter message for the event host...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              if (noticeCtrl.text.trim().isNotEmpty) {
                await appState.addEventMessage(ev.id, noticeCtrl.text.trim());
                Navigator.of(dialogCtx).pop();
                _toast(context, 'Notice sent to host');
              }
            },
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppState appState, Event ev) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete "${ev.title}"? This action cannot be undone.', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              await appState.deleteEvent(ev.id);
              Navigator.of(dialogCtx).pop();
              _toast(context, 'Event deleted');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectReasonDialog(BuildContext context, AppState appState, Event ev) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event: ${ev.title}', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                hintText: 'Enter the reason for rejection...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              await appState.rejectEvent(ev.id, reason);
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              _toast(context, 'Event rejected');
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return StreamBuilder<List<Event>>(
          stream: appState.watchPendingEvents(),
          builder: (context, pendingSnap) {
            if (pendingSnap.hasError) {
              return Scaffold(
                appBar: _appBar('Events Management', context),
                body: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load events',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }
            return StreamBuilder<List<Event>>(
              stream: appState.watchAllEvents(),
              builder: (context, allSnap) {
                if (allSnap.hasError) {
                  return Scaffold(
                    appBar: _appBar('Events Management', context),
                    body: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Unable to load events',
                      subtitle: 'Please check your connection and try again.',
                    ),
                  );
                }
                final pendingList = pendingSnap.data ?? const <Event>[];
                final publishedList = allSnap.data ?? const <Event>[];
                final data = _showPending ? pendingList : publishedList;

        return Scaffold(
          appBar: _appBar('Events Management', context),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/admin/events/editor'),
            backgroundColor: AppTheme.red, icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: HubButton(
                icon: Icons.how_to_vote_rounded,
                label: 'Election Management',
                subtitle: 'Manage elections and candidates',
                iconColor: AppTheme.red,
                onTap: () => context.push('/admin/events/elections'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPending = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _showPending ? AppTheme.red : Colors.transparent, width: 3)),
                      ),
                      child: Text('Pending (${pendingList.length})', textAlign: TextAlign.center, style: TextStyle(fontWeight: _showPending ? FontWeight.w800 : FontWeight.w600, color: _showPending ? AppTheme.red : AppTheme.textMuted)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPending = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: !_showPending ? AppTheme.red : Colors.transparent, width: 3)),
                      ),
                      child: Text('Published (${publishedList.length})', textAlign: TextAlign.center, style: TextStyle(fontWeight: !_showPending ? FontWeight.w800 : FontWeight.w600, color: !_showPending ? AppTheme.red : AppTheme.textMuted)),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(child: data.isEmpty
              ? const Center(child: EmptyState(title: 'No Events', subtitle: 'No events to display.', icon: Icons.event_rounded))
              : ListView.builder(padding: const EdgeInsets.fromLTRB(16,16,16,80), itemCount: data.length, itemBuilder: (ctx, i) {
                final ev = data[i];
                if (_showPending) {
                  // Show pending events with approve/reject buttons
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.danger.withOpacity(0.2))),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ev.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('${ev.category} · ${fmtDate(ev.date)}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          if (ev.organizer.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('By: ${ev.organizer}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                          const SizedBox(height: 10),
                          OutlineBtn(
                            label: 'Open Review',
                            color: const Color(0xFF1565C0),
                            onPressed: () => context.push('/admin/events/pending/${ev.id}'),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: OutlineBtn(label: 'Reject', onPressed: () {
                              _showRejectReasonDialog(ctx, appState, ev);
                            })),
                            const SizedBox(width: 8),
                            Expanded(child: GradientButton(label: 'Approve', onPressed: () async {
                              await appState.approveEvent(ev.id);
                              _toast(ctx, 'Event approved!');
                            })),
                          ]),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: (i*55).ms).slideY(begin:0.12);
                } else {
                  // Show published events with action buttons
                  final isCompleted = ev.status == 'Completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.red.withOpacity(0.12)),
                      boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ev.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text('${ev.category} · ${fmtDate(ev.date)} · ${ev.time}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  if (ev.organizer.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('By: ${ev.organizer}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  ],
                                ],
                              )),
                              const SizedBox(width: 8),
                              StatusBadge(ev.status),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Action buttons row
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (!isCompleted)
                                _ActionChip(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Complete',
                                  color: const Color(0xFF2E7D32),
                                  onTap: () async {
                                    await appState.markEventCompleted(ev.id);
                                    _toast(ctx, 'Event marked as completed');
                                  },
                                ),
                              _ActionChip(
                                icon: Icons.mail_outline_rounded,
                                label: 'Notice',
                                color: AppTheme.red,
                                onTap: () => _showSendNoticeDialog(ctx, appState, ev),
                              ),
                              _ActionChip(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                color: const Color(0xFF1565C0),
                                onTap: () => context.push('/admin/events/editor/${ev.id}'),
                              ),
                              _ActionChip(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: AppTheme.danger,
                                onTap: () => _showDeleteConfirmation(ctx, appState, ev),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: (i*55).ms).slideY(begin:0.12);
                }
              })),
          ]),
        );
              },
            );
          },
        );
      },
    );
  }
}

// ── Screen 26: Admin Event Editor ───────────────────────────────
class AdminEventEditorScreen extends StatefulWidget {
  final String? id;
  const AdminEventEditorScreen({super.key, this.id});

  @override
  State<AdminEventEditorScreen> createState() => _AdminEventEditorScreenState();
}

class _AdminEventEditorScreenState extends State<AdminEventEditorScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _timeCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _orgCtrl;
  late TextEditingController _noticeCtrl;
  late TextEditingController _maxParticipantsCtrl;
  String _category = 'Academic';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _dateCtrl = TextEditingController();
    _timeCtrl = TextEditingController();
    _locCtrl = TextEditingController();
    _orgCtrl = TextEditingController();
    _noticeCtrl = TextEditingController();
    _maxParticipantsCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _locCtrl.dispose();
    _orgCtrl.dispose();
    _noticeCtrl.dispose();
    _maxParticipantsCtrl.dispose();
    super.dispose();
  }

  void _confirmDelete(BuildContext context, AppState appState, Event ev) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete "${ev.title}"? This action cannot be undone.', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              await appState.deleteEvent(ev.id);
              Navigator.of(dialogCtx).pop();
              _toast(context, 'Event deleted');
              context.pop(); // Go back to list
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return StreamBuilder<List<Event>>(
          stream: appState.watchAllEvents(),
          builder: (context, allEventsSnap) {
            if (allEventsSnap.hasError) {
              return Scaffold(
                appBar: _appBar('Event Editor', context),
                body: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load events',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }
            final allEvents = allEventsSnap.data ?? const <Event>[];
            final ev = widget.id != null
              ? allEvents.firstWhere((x) => x.id == widget.id, orElse: () => const Event(
                  id: '', title: '', date: '', time: '', location: '',
                  category: '', organizer: '', description: '', status: ''
                ))
              : null;

        // Load event data into controllers only once
        if (ev != null && !_loaded && ev.id.isNotEmpty) {
          _titleCtrl.text = ev.title;
          _descCtrl.text = ev.description;
          _dateCtrl.text = ev.date;
          _timeCtrl.text = ev.time;
          _locCtrl.text = ev.location;
          _orgCtrl.text = ev.organizer;
          _category = ev.category;
          _maxParticipantsCtrl.text = ev.maxParticipants > 0 ? ev.maxParticipants.toString() : '';
          _loaded = true;
        }

        final isEditing = ev != null && ev.id.isNotEmpty;

        return Scaffold(
          appBar: _appBar(isEditing ? 'Edit Event' : 'Create Event', context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
            const AdminBar(), const SizedBox(height: 10),

            // Status indicator for existing events
            if (isEditing) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.red.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    const Text('Current status: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    StatusBadge(ev.status),
                  ],
                ),
              ),
            ],

            TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextFormField(controller: _descCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ['Academic','Sport','Club','General'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _category = val ?? _category),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _dateCtrl, decoration: const InputDecoration(labelText: 'Date'))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _timeCtrl, decoration: const InputDecoration(labelText: 'Time'))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _locCtrl, decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 12),
            TextFormField(controller: _orgCtrl, decoration: const InputDecoration(labelText: 'Organizer')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxParticipantsCtrl,
              decoration: const InputDecoration(labelText: 'Max Participants', hintText: '0 = unlimited'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 18),

            // ── Primary Actions ─────────────────────────────────
            if (isEditing) ...[
              // Publish / Update Status button
              GradientButton(
                label: ev.status == 'Published' ? 'Update Event' : 'Publish Event',
                onPressed: () async {
                  if (_titleCtrl.text.isNotEmpty) {
                    final updated = ev.copyWith(
                      title: _titleCtrl.text,
                      description: _descCtrl.text,
                      date: _dateCtrl.text,
                      time: _timeCtrl.text,
                      location: _locCtrl.text,
                      organizer: _orgCtrl.text,
                      category: _category,
                      status: ev.status == 'Published' ? ev.status : 'Published',
                      maxParticipants: int.tryParse(_maxParticipantsCtrl.text.trim()) ?? 0,
                    );
                    await appState.updateEvent(updated);
                    _toast(context, 'Event updated');
                  } else {
                    _toast(context, 'Title is required');
                  }
                },
              ),
              const SizedBox(height: 10),

              // Mark Completed button (only if not already completed)
              if (ev.status != 'Completed')
                OutlineBtn(
                  label: 'Mark as Completed',
                  color: const Color(0xFF2E7D32),
                  onPressed: () async {
                    await appState.markEventCompleted(ev.id);
                    _toast(context, 'Event marked as completed');
                  },
                ),
              if (ev.status != 'Completed')
                const SizedBox(height: 10),

              // Send Notice to Host
              const SectionLabel('Send Notice to Host'),
              TextFormField(
                controller: _noticeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notice message',
                  hintText: 'Type a message to send to the event host...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlineBtn(
                label: 'Send Notice',
                color: AppTheme.red,
                onPressed: () async {
                  if (_noticeCtrl.text.trim().isNotEmpty) {
                    await appState.addEventMessage(ev.id, _noticeCtrl.text.trim());
                    _toast(context, 'Notice sent to event host');
                    _noticeCtrl.clear();
                  } else {
                    _toast(context, 'Please enter a notice message');
                  }
                },
              ),
              const SizedBox(height: 16),

              // Delete Event (destructive)
              OutlineBtn(
                label: 'Delete Event',
                color: AppTheme.danger,
                onPressed: () => _confirmDelete(context, appState, ev),
              ),
            ] else ...[
              // Creating a new event
              GradientButton(
                label: 'Publish',
                onPressed: () async {
                  if (_titleCtrl.text.isNotEmpty) {
                    final newEvent = Event(
                      id: '',
                      title: _titleCtrl.text,
                      category: _category,
                      date: _dateCtrl.text,
                      time: _timeCtrl.text,
                      location: _locCtrl.text,
                      organizer: _orgCtrl.text,
                      description: _descCtrl.text,
                      status: 'Published',
                      hostStudentId: appState.userId,
                    );
                    final created = await appState.createEvent(newEvent);
                    if (created != null) {
                      await appState.approveEvent(created.id);
                    }
                    _toast(context, 'Event published');
                    context.pop();
                  } else {
                    _toast(context, 'Title is required');
                  }
                },
              ),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Save as Draft', onPressed: () => _toast(context, 'Saved as draft')),
            ],
          ])),
        );
          },
        );
      },
    );
  }
}

// ── Screen 27: Admin Elections Management ────────────────────────
class AdminElectionsMgmtScreen extends StatelessWidget {
  const AdminElectionsMgmtScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return StreamBuilder<List<Candidate>>(
          stream: appState.watchAllCandidates(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(
                appBar: _appBar('Elections Admin', context),
                body: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load candidates',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }
            final candidates = snap.data ?? const <Candidate>[];
            return Scaffold(
              appBar: _appBar('Elections Admin', context),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _showCandidateEditor(context, appState),
                backgroundColor: AppTheme.red,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add Candidate',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminBar(),
                    const SizedBox(height: 10),
                    StreamBuilder<List<ElectionMeta>>(
                      stream: appState.watchAllElectionMeta(),
                      builder: (context, metaSnap) {
                        final activeMetas = (metaSnap.data ?? const <ElectionMeta>[])
                            .where((m) => !m.isArchived)
                            .toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Elections'),
                            if (metaSnap.connectionState == ConnectionState.waiting && activeMetas.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (activeMetas.isEmpty)
                              const EmptyState(
                                icon: Icons.how_to_vote_rounded,
                                title: 'No elections yet',
                                subtitle: 'Elections are created via the seed tool.',
                              )
                            else
                              ...activeMetas.map((meta) => Card(
                                    child: ListTile(
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                            gradient: AppTheme.primaryGradient,
                                            shape: BoxShape.circle),
                                        child: Center(
                                            child: Text(
                                                meta.title.isNotEmpty ? meta.title[0] : '?',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800))),
                                      ),
                                      title: Text(meta.title,
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: Text('${meta.status} · ${meta.pollingDate}'),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                icon: const Icon(Icons.visibility_outlined,
                                                    size: 18, color: AppTheme.red),
                                                tooltip: 'View',
                                                onPressed: () => context.push(
                                                    '/admin/events/elections/detail/${meta.id}')),
                                            IconButton(
                                                icon: const Icon(Icons.edit_rounded,
                                                    size: 18, color: AppTheme.red),
                                                tooltip: 'Edit',
                                                onPressed: () => context.push(
                                                    '/admin/events/elections/editor/${meta.id}')),
                                            IconButton(
                                                icon: const Icon(Icons.archive_outlined,
                                                    size: 18, color: AppTheme.danger),
                                                tooltip: 'Archive',
                                                onPressed: () async {
                                                  final confirmed = await showArchiveCountdownDialog(
                                                    context,
                                                    itemName: meta.title,
                                                    warning: 'This election will be moved to the Admin Archive. It will no longer appear as an active election.',
                                                  );
                                                  if (confirmed != true || !context.mounted) return;
                                                  final ok = await appState.archiveElectionMeta(
                                                      meta.id, previousStatus: meta.status);
                                                  if (!context.mounted) return;
                                                  _toast(context, ok ? 'Election archived' : 'Archive failed');
                                                }),
                                          ]),
                                    ),
                                  )),
                            const SizedBox(height: 10),
                            HubButton(
                              icon: Icons.inventory_2_rounded,
                              label: 'Archived Elections',
                              subtitle: 'View and restore archived elections',
                              iconColor: AppTheme.red,
                              onTap: () => context.push('/admin/events/elections/archive'),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const SectionLabel('Candidates'),
                    if (snap.connectionState == ConnectionState.waiting &&
                        candidates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (candidates.isEmpty)
                      EmptyState(
                        icon: Icons.how_to_vote_rounded,
                        title: 'No candidates yet',
                        subtitle:
                            'Tap "Add Candidate" to create the first one.',
                      )
                    else
                      ...candidates.map((c) => Card(
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    shape: BoxShape.circle),
                                child: Center(
                                    child: Text(c.name[0],
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800))),
                              ),
                              title: Text(c.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${c.programme} · ${c.position}${c.status == 'Published' ? '' : ' · ${c.status}'}'),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: Icon(
                                            c.status == 'Published'
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            size: 18,
                                            color: AppTheme.red),
                                        tooltip: c.status == 'Published'
                                            ? 'Unpublish'
                                            : 'Publish',
                                        onPressed: () async {
                                          final wasPublished =
                                              c.status == 'Published';
                                          final ok = wasPublished
                                              ? await appState
                                                  .unpublishCandidate(c.id)
                                              : await appState
                                                  .publishCandidate(c.id);
                                          if (!context.mounted) return;
                                          _toast(
                                              context,
                                              ok
                                                  ? (wasPublished
                                                      ? 'Candidate unpublished'
                                                      : 'Candidate published')
                                                  : 'Action failed');
                                        }),
                                    IconButton(
                                        icon: const Icon(Icons.edit_rounded,
                                            size: 18, color: AppTheme.red),
                                        onPressed: () => _showCandidateEditor(
                                            context, appState,
                                            candidate: c),
                                    ),
                                    IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            size: 18, color: AppTheme.danger),
                                        onPressed: () async {
                                          final ok = await appState
                                              .deleteCandidate(c.id);
                                          if (!context.mounted) return;
                                          _toast(
                                              context,
                                              ok
                                                  ? 'Candidate removed'
                                                  : 'Remove failed');
                                        }),
                                  ]),
                            ),
                          )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Dialog-based create/update form for a [Candidate]. Mirrors the lightweight
/// admin editor pattern used elsewhere in this module — keeps the elections
/// admin self-contained without introducing a new routed screen.
Future<void> _showCandidateEditor(
  BuildContext context,
  AppState appState, {
  Candidate? candidate,
}) async {
  final isEdit = candidate != null;
  final nameCtrl = TextEditingController(text: candidate?.name ?? '');
  final programmeCtrl =
      TextEditingController(text: candidate?.programme ?? '');
  final positionCtrl =
      TextEditingController(text: candidate?.position ?? '');
  final manifestoCtrl =
      TextEditingController(text: candidate?.manifesto ?? '');

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isEdit ? 'Edit Candidate' : 'New Candidate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
                controller: programmeCtrl,
                decoration: const InputDecoration(labelText: 'Programme')),
            const SizedBox(height: 12),
            TextField(
                controller: positionCtrl,
                decoration: const InputDecoration(labelText: 'Position')),
            const SizedBox(height: 12),
            TextField(
                controller: manifestoCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Manifesto', alignLabelWithHint: true)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save')),
      ],
    ),
  );

  if (result != true) return;
  final name = nameCtrl.text.trim();
  if (name.isEmpty) {
    _toast(context, 'Name is required');
    return;
  }
  final programme = programmeCtrl.text.trim();
  final position = positionCtrl.text.trim();
  final manifesto = manifestoCtrl.text.trim();
  bool ok;
  if (isEdit) {
    ok = await appState.updateCandidate(candidate.copyWith(
      name: name,
      programme: programme,
      position: position,
      manifesto: manifesto,
    ));
  } else {
    ok = await appState.createCandidate(Candidate(
      id: '',
      name: name,
      programme: programme,
      position: position,
      manifesto: manifesto,
      status: 'Pending',
    ));
  }
  if (!context.mounted) return;
  _toast(context,
      ok ? (isEdit ? 'Candidate updated' : 'Candidate created') : 'Save failed');
}

// ── Shared ────────────────────────────────────────────────────────
class _TL extends StatelessWidget {
  final String date, text;
  const _TL(this.date, this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 130, child: Text(date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.red))),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
  ]));
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
