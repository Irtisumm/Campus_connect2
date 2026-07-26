import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart' as qr;

import '../../data/mock_data.dart';
import '../../services/app_state.dart';
import '../../services/data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        duration: const Duration(seconds: 2),
      ),
    );

AppBar _appBar(String title, BuildContext ctx) => AppBar(
      title: Text(title),
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => ctx.pop(),
      ),
    );

class MyEventsScreen extends StatelessWidget {
  const MyEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<DataService, AppState>(
      builder: (context, dataService, appState, child) {
        final myEvents = dataService.getEventsForHost(appState.userId ?? '');
        return Scaffold(
          appBar: _appBar('My Submitted Events', context),
          body: RefreshIndicator(
              color: AppTheme.red,
              onRefresh: () async => dataService.refresh(),
              child: myEvents.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        EmptyState(
                          title: 'No Submitted Events',
                          subtitle: 'Submit your first event from the Events page.\nPull down to refresh.',
                          icon: Icons.event_busy_rounded,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: myEvents.length,
                      itemBuilder: (ctx, i) {
                        final ev = myEvents[i];
                        return _EventStatusCard(
                          event: ev,
                          onTap: () => context.push('/events/my-events/${ev.id}'),
                          onManage: ev.status == 'Published'
                              ? () => context.push('/events/manage/${ev.id}')
                              : null,
                        );
                      },
                    ),
            ),
        );
      },
    );
  }
}

class MyEventDetailScreen extends StatefulWidget {
  final String id;
  const MyEventDetailScreen({super.key, required this.id});

  @override
  State<MyEventDetailScreen> createState() => _MyEventDetailScreenState();
}

class _MyEventDetailScreenState extends State<MyEventDetailScreen> {
  final _messageCtrl = TextEditingController();
  final _qrScanCtrl = TextEditingController();
  bool _scanMode = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    _qrScanCtrl.dispose();
    super.dispose();
  }

  void _handleScan(BuildContext ctx, DataService dataService, String eventId) {
    final code = _qrScanCtrl.text.trim();
    if (code.isEmpty) return;
    
    final success = dataService.verifyAndMarkAttendance(eventId, code);
    if (success) {
      _toast(ctx, '✅ Entry Verified!');
      _qrScanCtrl.clear();
      setState(() {});
    } else {
      _toast(ctx, '❌ Invalid or unapproved QR code.');
    }
  }

  void _toggleScanMode() {
    setState(() => _scanMode = !_scanMode);
  }

  void _showQRCodeDialog(BuildContext context, String qrCode, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('QR Code - $name', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 250,
                height: 250,
                child: qr.QrImageView(
                  data: qrCode,
                  version: qr.QrVersions.auto,
                  size: 250,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              qrCode,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DataService, AppState>(
      builder: (context, dataService, appState, child) {
        Event? event = dataService.getEventById(widget.id);

        if (event == null) {
          try {
            final allCreatedEvents = dataService.getEventsForHost(appState.userId ?? '');
            if (allCreatedEvents.isNotEmpty) {
              final foundEvent = allCreatedEvents.firstWhere(
                (e) => e.id == widget.id,
                orElse: () => const Event(
                  id: '', title: '', date: '', time: '', location: '',
                  category: '', organizer: '', description: '', status: '',
                ),
              );
              if (foundEvent.id.isNotEmpty) {
                event = foundEvent;
              }
            }
          } catch (e) {
            // Silently catch errors
          }
        }

        if (event == null) {
          return Scaffold(
            appBar: _appBar('My Event', context),
            body: const EmptyState(
              title: 'Event Not Found',
              subtitle: 'This event no longer exists or has been deleted.',
              icon: Icons.error_outline_rounded,
            ),
          );
        }

        final eventId = event.id;
        final eventStatus = event.status;
        final canResubmit = event.status == 'Needs Revision' || event.status == 'Rejected';
        final messages = event.messages ?? const <EventMessage>[];
        final attendees = dataService.getEventAttendees(eventId);
        final pendingRequests = dataService.getJoiningRequestsForEvent(eventId)
            .where((j) => j.status == 'Pending').toList();

        return Scaffold(
          appBar: _appBar('Event Dashboard', context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event Overview Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.title,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    eventStatus,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: switch (eventStatus) {
                                        'Published'      => const Color(0xFF4CAF50),
                                        'Rejected'       => const Color(0xFFD65E5E),
                                        'Needs Revision' => const Color(0xFFB8860B),
                                        'Under Review'   => const Color(0xFF2196F3),
                                        _                => AppTheme.textMuted,
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(eventStatus),
                          ],
                        ),
                        const Divider(height: 20),
                        InfoRow(label: 'Date', value: fmtDate(event.date)),
                        InfoRow(label: 'Time', value: event.time),
                        InfoRow(label: 'Location', value: event.location),
                        InfoRow(label: 'Category', value: event.category),
                        const SizedBox(height: 12),
                        // Event Statistics
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(label: 'Participants', value: '${attendees.length}'),
                            _StatItem(label: 'Checked-In', value: '${attendees.where((a) => a.hasAttended).length}'),
                            _StatItem(label: 'Pending', value: '${pendingRequests.length}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Status Banner ─────────────────────────────
                if (eventStatus == 'Published') _StatusBanner(
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF4CAF50),
                  title: 'Event Approved & Published!',
                  body: 'Your event is now live. Use the Manage Dashboard to handle participants and entry.',
                  actionLabel: 'Open Manage Dashboard',
                  onAction: () => context.push('/events/manage/${event!.id}'),
                ),
                if (eventStatus == 'Rejected') _StatusBanner(
                  icon: Icons.cancel_rounded,
                  color: const Color(0xFFD65E5E),
                  title: 'Event Rejected',
                  body: event.rejectionReason ?? 'No reason provided. Please contact admin.',
                  actionLabel: 'Resubmit Event',
                  onAction: () => _showResubmitDialog(context, dataService, event!),
                ),
                if (eventStatus == 'Needs Revision') _StatusBanner(
                  icon: Icons.edit_note_rounded,
                  color: const Color(0xFFB8860B),
                  title: 'Changes Requested',
                  body: event.revisionNotes ?? 'Admin has requested changes. Check admin messages below.',
                  actionLabel: 'Resubmit with Changes',
                  onAction: () => _showResubmitDialog(context, dataService, event!),
                ),
                if (eventStatus == 'Under Review') const _StatusBanner(
                  icon: Icons.rate_review_rounded,
                  color: Color(0xFF2196F3),
                  title: 'Under Review',
                  body: 'Admin is currently reviewing your event. You will be notified of the decision.',
                ),
                if (eventStatus == 'Pending') const _StatusBanner(
                  icon: Icons.pending_rounded,
                  color: AppTheme.textMuted,
                  title: 'Pending Admin Review',
                  body: 'Your event has been submitted and is waiting for admin approval.',
                ),
                const SizedBox(height: 14),

                // QR Code Section (only for Published events)
                if (eventStatus == 'Published') ...[
                  const SectionLabel('Entry Verification'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (!_scanMode)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgCard,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.2)),
                                  ),
                                  child: SizedBox(
                                    width: 200,
                                    height: 200,
                                    child: qr.QrImageView(
                                      data: 'EVENT-$eventId-SCANNER',
                                      version: qr.QrVersions.auto,
                                      size: 200,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Scan this QR to enter scanning mode',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue, width: 2),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.qr_code_scanner, size: 32, color: Colors.blue),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'QR Scanner Active',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _qrScanCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Enter student QR code...',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueGrey)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () => _handleScan(context, dataService, eventId),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 12)),
                                      child: const Text('Verify Participant Entry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: _scanMode ? 'Exit Scanner' : 'Start Scanning',
                            onPressed: _toggleScanMode,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Pending Requests Section
                if (pendingRequests.isNotEmpty) ...[
                  SectionLabel('Join Requests (${pendingRequests.length})'),
                  ...pendingRequests.map((req) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFC107).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(req.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                  Text(req.courseName, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  if (req.clubId != null && req.clubId!.isNotEmpty)
                                    Text('Club: ${req.clubId}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    dataService.approveEventJoining(req.id);
                                    _toast(context, '${req.name} approved');
                                    setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    dataService.rejectEventJoining(req.id, reason: 'Rejected by organizer');
                                    _toast(context, '${req.name} rejected');
                                    setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.red.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                                    ),
                                    child: const Text('✕', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.red)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],

                // Approved Attendees Section
                if (attendees.isNotEmpty) ...[
                  SectionLabel('Approved Attendees (${attendees.length})'),
                  ...attendees.map((a) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: a.hasAttended ? const Color(0xFF4CAF50).withValues(alpha: 0.05) : AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: a.hasAttended ? const Color(0xFF4CAF50).withValues(alpha: 0.4) : AppTheme.textMuted.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => dataService.toggleManualAttendance(a.id),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: a.hasAttended ? const Color(0xFF4CAF50) : Colors.transparent,
                              border: Border.all(color: a.hasAttended ? const Color(0xFF4CAF50) : AppTheme.textMuted),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: a.hasAttended ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                              Text(a.courseName, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              if (a.clubId != null && a.clubId!.isNotEmpty)
                                Text('Club: ${a.clubId}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              if (a.paymentStatus != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: a.paymentStatus == 'Completed' ? const Color(0xFF4CAF50).withOpacity(0.1) : AppTheme.goldDark.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Payment: ${a.paymentStatus}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: a.paymentStatus == 'Completed' ? const Color(0xFF4CAF50) : AppTheme.goldDark)),
                                ),
                            ],
                          ),
                        ),
                        if (a.qrTicketCode != null && a.qrTicketCode!.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _showQRCodeDialog(context, a.qrTicketCode!, a.name);
                            },
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.2)),
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.white,
                              ),
                              child: qr.QrImageView(
                                data: a.qrTicketCode!,
                                version: qr.QrVersions.auto,
                                size: 50,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],

                // Admin Messages Section
                if (messages.isNotEmpty) ...[
                  const SectionLabel('Admin Communication'),
                  ...messages.map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: m.senderRole == 'admin'
                            ? AppTheme.gold.withValues(alpha: 0.14)
                            : AppTheme.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.senderRole == 'admin' ? 'Admin' : 'You',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m.message,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.timestamp,
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Message Input
                TextField(
                  controller: _messageCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Reply to admin...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlineBtn(
                        label: 'Send Message',
                        onPressed: () {
                          final msg = _messageCtrl.text.trim();
                          if (msg.isEmpty) return;
                          dataService.addEventMessage(
                            eventId,
                            appState.userId ?? 'S001',
                            'student',
                            msg,
                          );
                          _messageCtrl.clear();
                          _toast(context, 'Message sent');
                          setState(() {});
                        },
                      ),
                    ),
                    if (canResubmit) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: GradientButton(
                          label: 'Resubmit',
                          onPressed: () => _showResubmitDialog(context, dataService, event!),
                        ),
                      ),
                    ] else if (eventStatus == 'Pending') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlineBtn(
                          label: 'Edit Details',
                          onPressed: () => _showEditDialog(context, dataService, event!),
                        ),
                      ),
                    ] else if (eventStatus == 'Published') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: GradientButton(
                          label: 'Manage Dashboard',
                          onPressed: () => context.push('/events/manage/${event!.id}'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, DataService dataService, Event event) {
    final titleCtrl = TextEditingController(text: event.title);
    final dateCtrl = TextEditingController(text: event.date);
    final timeCtrl = TextEditingController(text: event.time);
    final locCtrl = TextEditingController(text: event.location);
    final orgCtrl = TextEditingController(text: event.organizer);
    final descCtrl = TextEditingController(text: event.description);
    var category = event.category;
    final key = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Event Details', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const ['Academic', 'Sport', 'Club', 'General']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => category = v ?? category,
                ),
                const SizedBox(height: 8),
                TextFormField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
                const SizedBox(height: 8),
                TextFormField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Time')),
                const SizedBox(height: 8),
                TextFormField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location')),
                const SizedBox(height: 8),
                TextFormField(controller: orgCtrl, decoration: const InputDecoration(labelText: 'Organizer')),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            onPressed: () {
              if (!key.currentState!.validate()) return;
              final parsed = DateTime.tryParse(dateCtrl.text.trim());
              if (parsed == null) {
                _toast(context, 'Please enter a valid date (YYYY-MM-DD)');
                return;
              }
              
              final updated = Event(
                id: event.id,
                title: titleCtrl.text.trim(),
                date: dateCtrl.text.trim(),
                time: timeCtrl.text.trim(),
                location: locCtrl.text.trim(),
                category: category,
                organizer: orgCtrl.text.trim(),
                description: descCtrl.text.trim(),
                status: event.status, // preserve status
              );
              dataService.updateEventDetails(event.id, updated);
              Navigator.pop(ctx);
              _toast(context, 'Details updated successfully');
            },
            child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showResubmitDialog(BuildContext context, DataService dataService, Event event) {
    final titleCtrl = TextEditingController(text: event.title);
    final dateCtrl = TextEditingController(text: event.date);
    final timeCtrl = TextEditingController(text: event.time);
    final locCtrl = TextEditingController(text: event.location);
    final orgCtrl = TextEditingController(text: event.organizer);
    final descCtrl = TextEditingController(text: event.description);
    var category = event.category;
    final key = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resubmit Event', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const ['Academic', 'Sport', 'Club', 'General']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => category = v ?? category,
                ),
                const SizedBox(height: 8),
                TextFormField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Date')),
                const SizedBox(height: 8),
                TextFormField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Time')),
                const SizedBox(height: 8),
                TextFormField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location')),
                const SizedBox(height: 8),
                TextFormField(controller: orgCtrl, decoration: const InputDecoration(labelText: 'Organizer')),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              if (!key.currentState!.validate()) return;
              final parsed = DateTime.tryParse(dateCtrl.text.trim());
              if (parsed == null) {
                _toast(context, 'Please enter a valid date (YYYY-MM-DD)');
                return;
              }
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final eventDay = DateTime(parsed.year, parsed.month, parsed.day);
              if (eventDay.difference(today).inDays < 10) {
                _toast(context, 'Resubmissions must still be at least 10 days before event date');
                return;
              }
              final updated = Event(
                id: event.id,
                title: titleCtrl.text.trim(),
                date: dateCtrl.text.trim(),
                time: timeCtrl.text.trim(),
                location: locCtrl.text.trim(),
                category: category,
                organizer: orgCtrl.text.trim(),
                description: descCtrl.text.trim(),
                status: event.status,
                hostStudentId: event.hostStudentId,
                approvalLetterPath: event.approvalLetterPath,
                approvalLetterName: event.approvalLetterName,
                hasApprovalLetter: event.hasApprovalLetter,
                submittedDate: event.submittedDate,
                revisionCount: event.revisionCount,
                messages: event.messages,
              );
              dataService.resubmitEvent(event.id, updated);
              Navigator.pop(ctx);
              _toast(context, 'Event resubmitted');
            },
            child: const Text('Resubmit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }
}

// ── Status Banner Widget ────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color))),
        ]),
        const SizedBox(height: 6),
        Text(body,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Status-aware Event Card (My Events list) ─────────────────────
class _EventStatusCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  final VoidCallback? onManage;
  const _EventStatusCard({
    required this.event,
    required this.onTap,
    this.onManage,
  });

  Color get _accentColor => switch (event.status) {
    'Published'     => const Color(0xFF4CAF50),
    'Rejected'      => const Color(0xFFD65E5E),
    'Needs Revision'=> const Color(0xFFE8B96A),
    'Under Review'  => const Color(0xFF2196F3),
    _               => AppTheme.textMuted,
  };

  IconData get _statusIcon => switch (event.status) {
    'Published'     => Icons.check_circle_rounded,
    'Rejected'      => Icons.cancel_rounded,
    'Needs Revision'=> Icons.edit_note_rounded,
    'Under Review'  => Icons.rate_review_rounded,
    _               => Icons.pending_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _accentColor;
    final isRejected  = event.status == 'Rejected';
    final needsRevision = event.status == 'Needs Revision';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Colored left bar
              Container(
                width: 3, height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${fmtDate(event.date)}  •  ${event.time}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                if (event.revisionCount > 0)
                  Text('Revision #${event.revisionCount}',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textMuted)),
              ])),
              const SizedBox(width: 8),
              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_statusIcon, size: 11, color: color),
                  const SizedBox(width: 4),
                  Text(event.status,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: color)),
                ]),
              ),
            ]),
          ),

          // Rejection reason banner
          if (isRejected && event.rejectionReason != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD65E5E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFD65E5E).withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: Color(0xFFD65E5E)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Rejected: ${event.rejectionReason}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFD65E5E),
                      fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ],

          // Revision notes banner
          if (needsRevision && event.revisionNotes != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8B96A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFE8B96A).withValues(alpha: 0.45)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.edit_note_rounded,
                    size: 13, color: Color(0xFFB8860B)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Required changes: ${event.revisionNotes}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFB8860B),
                      fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ],

          // Bottom action row
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(children: [
              Expanded(child: Text(
                'Organizer: ${event.organizer}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                overflow: TextOverflow.ellipsis,
              )),
              if (onManage != null)
                GestureDetector(
                  onTap: onManage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.dashboard_customize_rounded,
                          color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text('Manage',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                )
              else if (isRejected || needsRevision)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Text('Tap to Resubmit',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700, color: color)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class AdminPendingEventDetailScreen extends StatefulWidget {
  final String id;
  const AdminPendingEventDetailScreen({super.key, required this.id});

  @override
  State<AdminPendingEventDetailScreen> createState() => _AdminPendingEventDetailScreenState();
}

class _AdminPendingEventDetailScreenState extends State<AdminPendingEventDetailScreen> {
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final event = dataService.getEventById(widget.id);
        if (event == null) {
          return Scaffold(
            appBar: _appBar('Pending Event', context),
            body: const EmptyState(
              title: 'Event Not Found',
              subtitle: 'Unable to load this pending event.',
              icon: Icons.error_outline_rounded,
            ),
          );
        }

        final messages = event.messages ?? const <EventMessage>[];
        return Scaffold(
          appBar: _appBar('Pending Event Review', context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminBar(),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                            StatusBadge(event.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InfoRow(label: 'Date', value: fmtDate(event.date)),
                        InfoRow(label: 'Time', value: event.time),
                        InfoRow(label: 'Location', value: event.location),
                        InfoRow(label: 'Organizer', value: event.organizer),
                        if (event.approvalLetterName != null)
                          InfoRow(label: 'Approval Letter', value: event.approvalLetterName!),
                        const Divider(height: 18),
                        Text(event.description,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SectionLabel('Review Actions'),
                Row(
                  children: [
                    Expanded(
                      child: OutlineBtn(
                        label: 'Under Review',
                        color: const Color(0xFF1565C0),
                        onPressed: () {
                          dataService.setEventUnderReview(event.id);
                          _toast(context, 'Moved to Under Review');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlineBtn(
                        label: 'Need Revision',
                        color: AppTheme.goldDark,
                        onPressed: () => _showReasonDialog(
                          context,
                          title: 'Request Revision',
                          onSubmit: (text) {
                            dataService.requestEventRevision(event.id, text);
                            _toast(context, 'Revision requested');
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlineBtn(
                        label: 'Reject',
                        color: AppTheme.danger,
                        onPressed: () => _showReasonDialog(
                          context,
                          title: 'Reject Event',
                          onSubmit: (text) {
                            dataService.rejectEvent(event.id, reason: text);
                            _toast(context, 'Event rejected');
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GradientButton(
                        label: 'Approve',
                        onPressed: () {
                          dataService.approveEvent(event.id);
                          _toast(context, 'Event approved');
                          context.pop();
                        },
                      ),
                    ),
                  ],
                ),
                const SectionLabel('Messages'),
                if (messages.isEmpty)
                  const NoticeBox(message: 'No messages yet.')
                else
                  ...messages.map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: m.senderRole == 'admin'
                            ? AppTheme.red.withValues(alpha: 0.08)
                            : AppTheme.gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.senderRole == 'admin' ? 'Admin' : 'Student',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(m.message, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(m.timestamp, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Message to student...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlineBtn(
                  label: 'Send Message',
                  onPressed: () {
                    final msg = _messageCtrl.text.trim();
                    if (msg.isEmpty) return;
                    dataService.addEventMessage(event.id, 'ADMIN', 'admin', msg);
                    _messageCtrl.clear();
                    _toast(context, 'Message sent');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReasonDialog(
    BuildContext context, {
    required String title,
    required void Function(String reason) onSubmit,
  }) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter details...',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              onSubmit(text);
              Navigator.pop(ctx);
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
