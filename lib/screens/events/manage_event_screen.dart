import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/mock_data.dart';
import '../../services/app_state.dart';
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

// ── Manage My Event Screen ────────────────────────────────────────
class ManageMyEventScreen extends StatefulWidget {
  final String id;
  const ManageMyEventScreen({super.key, required this.id});

  @override
  State<ManageMyEventScreen> createState() => _ManageMyEventScreenState();
}

class _ManageMyEventScreenState extends State<ManageMyEventScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _qrCtrl = TextEditingController();
  final _sidCtrl = TextEditingController();
  String _participantFilter = 'All';
  String _selectedRole = 'Staff';
  final List<String> _selectedPerms = ['scan_qr', 'manage_participants'];

  static const _roleOptions = ['Organizer', 'Staff', 'Volunteer'];
  static const _roleDefaultPerms = {
    'Organizer': ['scan_qr', 'manage_participants', 'edit_event'],
    'Staff':     ['scan_qr', 'manage_participants'],
    'Volunteer': ['scan_qr'],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _qrCtrl.dispose();
    _sidCtrl.dispose();
    super.dispose();
  }

  // ── Tab 0: Overview ─────────────────────────────────────────────
  Widget _buildOverview(BuildContext ctx, AppState appState, Event ev) {
    return StreamBuilder<List<EventJoining>>(
      stream: appState.watchEventJoinings(ev.id),
      builder: (context, joiningsSnap) {
        final allReqs = joiningsSnap.data ?? const <EventJoining>[];
        final pending  = allReqs.where((j) => j.status == 'Pending').length;
        final approved = allReqs.where((j) => j.status == 'Approved').toList();
        final attended = approved.where((a) => a.hasAttended).length;
        final messages = ev.messages ?? const <EventMessage>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.verified_rounded, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('APPROVED & PUBLISHED', style: TextStyle(
                color: Colors.white70, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ]),
            const SizedBox(height: 8),
            Text(ev.title, style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${fmtDate(ev.date)}  •  ${ev.time}  •  ${ev.location}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),

        // Stats
        Row(children: [
          _StatCard('Registered', '${approved.length}', Icons.people_rounded, const Color(0xFF4CAF50)),
          const SizedBox(width: 10),
          _StatCard('Pending', '$pending', Icons.pending_actions_rounded, AppTheme.gold),
          const SizedBox(width: 10),
          _StatCard('Attended', '$attended', Icons.check_circle_rounded, AppTheme.red),
        ]),
        const SizedBox(height: 14),

        // Edit button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Edit Event Details'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.red.withOpacity(0.4)),
              foregroundColor: AppTheme.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _showEditDialog(ctx, appState, ev),
          ),
        ),
        const SizedBox(height: 14),

        // Event info
        const SectionLabel('Event Info'),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          InfoRow(label: 'Category',  value: ev.category),
          InfoRow(label: 'Organizer', value: ev.organizer),
          InfoRow(label: 'Type',      value: ev.eventType),
          if (ev.isPaid) InfoRow(label: 'Entry Fee', value: 'RM ${ev.price.toStringAsFixed(2)}'),
          if (ev.submittedDate != null) InfoRow(label: 'Submitted', value: ev.submittedDate!),
          InfoRow(label: 'Description', value: ev.description),
        ]))),

        // Admin messages
        if (messages.isNotEmpty) ...[
          const SectionLabel('Admin Messages'),
          ...messages.map((m) => _MessageBubble(m)),
        ],
      ]),
    );
          },
        );
  }

  // ── Tab 1: Participants ──────────────────────────────────────────
  Widget _buildParticipants(BuildContext ctx, AppState appState, String eventId, bool isPaid) {
    return StreamBuilder<List<EventJoining>>(
      stream: appState.watchEventJoinings(eventId),
      builder: (context, joiningsSnap) {
        final allReqs = joiningsSnap.data ?? const <EventJoining>[];
        final filtered = _participantFilter == 'All'
            ? allReqs
            : allReqs.where((j) => j.status == _participantFilter).toList();

    return Column(children: [
      // Filter chips
      Container(
        color: AppTheme.bgApp,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Pending', 'Approved', 'Rejected'].map((f) {
              final selected = _participantFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (_) => setState(() => _participantFilter = f),
                  selectedColor: AppTheme.red,
                  backgroundColor: AppTheme.bgCard,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      // Count
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${filtered.length} participant${filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
      ),
      // List
      Expanded(
        child: filtered.isEmpty
            ? const EmptyState(
                title: 'No Participants',
                subtitle: 'No participants match this filter.',
                icon: Icons.people_outline_rounded)
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final req = filtered[i];
                  return _ParticipantCard(
                    joining: req,
                    isPaid: isPaid,
                    onApprove: req.status == 'Pending' ? () async {
                      await appState.approveJoining(req);
                      _toast(ctx, '✅ ${req.name} approved');
                    } : null,
                    onReject: req.status == 'Pending' ? () async {
                      await appState.rejectJoining(req);
                      _toast(ctx, '❌ ${req.name} rejected');
                    } : null,
                  );
                },
              ),
      ),
    ]);
          },
        );
  }

  // ── Tab 2: Roles ─────────────────────────────────────────────────
  Widget _buildRoles(BuildContext ctx, AppState appState, String eventId,
      String creatorId, String creatorName) {
    return StreamBuilder<List<EventRole>>(
      stream: appState.watchEventRoles(eventId),
      builder: (context, rolesSnap) {
        final roles = rolesSnap.data ?? const <EventRole>[];
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(16), children: [
        // Header notice
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.red.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.red.withOpacity(0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.red),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Assign roles to your team. Staff can approve participants and scan QR codes.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            )),
          ]),
        ),
        // Creator card (non-removable)
        _RoleCard(
          name: creatorName, studentId: creatorId, role: 'Creator',
          permissions: const ['scan_qr', 'manage_participants', 'edit_event'],
          onRemove: null,
        ),
        const SizedBox(height: 8),
        if (roles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No team members added yet.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
          ),
        ...roles.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _RoleCard(
            name: r.studentName, studentId: r.studentId,
            role: r.role, permissions: r.permissions,
            onRemove: () async {
              await appState.removeEventRole(r.id);
              _toast(ctx, 'Role removed for ${r.studentName}');
            },
          ),
        )),
        const SizedBox(height: 80),
      ]),
      Positioned(
        bottom: 16, right: 16,
        child: FloatingActionButton.extended(
          backgroundColor: AppTheme.red,
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: const Text('Add Team Member',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          onPressed: () => _showAddRoleDialog(ctx, appState, eventId),
        ),
      ),
    ]);
      },
    );
  }

  // ── Tab 3: Entry Verification ────────────────────────────────────
  Widget _buildEntry(BuildContext ctx, AppState appState, String eventId) {
    return StreamBuilder<List<EventJoining>>(
      stream: appState.watchEventJoinings(eventId),
      builder: (context, joiningsSnap) {
        final allJoinings = joiningsSnap.data ?? const <EventJoining>[];
        final attendees = allJoinings.where((j) => j.status == 'Approved').toList();
        final attended  = attendees.where((a) => a.hasAttended).toList();
        final notYet    = attendees.where((a) => !a.hasAttended).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Scanner card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            // Progress indicator
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Entry Verification',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${attended.length} / ${attendees.length} in',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: attendees.isEmpty ? 0 : attended.length / attendees.length,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
              ),
            ),
            const SizedBox(height: 18),
            // QR input
            TextField(
              controller: _qrCtrl,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter or paste QR code here...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded, color: Colors.white60, size: 18),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) setState(() => _qrCtrl.text = data!.text!);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Verify & Check In',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final code = _qrCtrl.text.trim();
                  if (code.isEmpty) { _toast(ctx, 'Enter a QR code first'); return; }
                  final ok = await appState.verifyTicket(eventId, code);
                  if (ok) {
                    _toast(ctx, '✅ Entry verified! Participant checked in.');
                    _qrCtrl.clear();
                  } else {
                    _toast(ctx, '❌ Invalid or unapproved QR code.');
                  }
                },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Checked-in list
        const SectionLabel('Checked In'),
        attended.isEmpty
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('No one checked in yet.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
              )
            : Column(children: attended.map((a) => _AttendeeRow(a, checked: true)).toList()),

        // Not yet checked in
        if (notYet.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionLabel('Awaiting Check-In'),
          ...notYet.map((a) => _AttendeeRow(a, checked: false)),
        ],
      ]),
    );
          },
        );
  }

  // ── Dialogs ──────────────────────────────────────────────────────
  void _showEditDialog(BuildContext ctx, AppState appState, Event ev) {
    final titleCtrl = TextEditingController(text: ev.title);
    final dateCtrl  = TextEditingController(text: ev.date);
    final timeCtrl  = TextEditingController(text: ev.time);
    final locCtrl   = TextEditingController(text: ev.location);
    final orgCtrl   = TextEditingController(text: ev.organizer);
    final descCtrl  = TextEditingController(text: ev.description);

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Event Details',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: dateCtrl,
                decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
            const SizedBox(height: 8),
            TextField(controller: timeCtrl,
                decoration: const InputDecoration(labelText: 'Time')),
            const SizedBox(height: 8),
            TextField(controller: locCtrl,
                decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 8),
            TextField(controller: orgCtrl,
                decoration: const InputDecoration(labelText: 'Organizer')),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description', alignLabelWithHint: true)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red, foregroundColor: Colors.white),
            onPressed: () async {
              final updated = ev.copyWith(
                title: titleCtrl.text.trim(),
                date: dateCtrl.text.trim(),
                time: timeCtrl.text.trim(),
                location: locCtrl.text.trim(),
                organizer: orgCtrl.text.trim(),
                description: descCtrl.text.trim(),
              );
              await appState.updateEvent(updated);
              Navigator.pop(dialogCtx);
              _toast(ctx, '✅ Event details updated');
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showAddRoleDialog(BuildContext ctx, AppState appState, String eventId) {
    _sidCtrl.clear();
    _selectedRole = 'Staff';
    _selectedPerms
      ..clear()
      ..addAll(_roleDefaultPerms['Staff']!);

    showDialog(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Team Member',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _sidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    hintText: 'e.g. S002',
                    prefixIcon: Icon(Icons.person_search_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Role', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12,
                    color: AppTheme.textMuted)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: _roleOptions.map((r) => ChoiceChip(
                  label: Text(r),
                  selected: _selectedRole == r,
                  selectedColor: AppTheme.red,
                  onSelected: (_) => setD(() {
                    _selectedRole = r;
                    _selectedPerms
                      ..clear()
                      ..addAll(_roleDefaultPerms[r]!);
                  }),
                  labelStyle: TextStyle(
                    color: _selectedRole == r ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600, fontSize: 12),
                )).toList()),
                const SizedBox(height: 16),
                const Text('Permissions', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12,
                    color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                ...[
                  ('scan_qr',             'Scan QR Codes',          Icons.qr_code_scanner_rounded),
                  ('manage_participants', 'Manage Participants',     Icons.people_rounded),
                  ('edit_event',          'Edit Event Details',      Icons.edit_rounded),
                ].map((p) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Row(children: [
                    Icon(p.$3, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(p.$2, style: const TextStyle(fontSize: 12)),
                  ]),
                  value: _selectedPerms.contains(p.$1),
                  onChanged: (v) => setD(() {
                    if (v == true) { _selectedPerms.add(p.$1); }
                    else { _selectedPerms.remove(p.$1); }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.red, foregroundColor: Colors.white),
              onPressed: () async {
                final sid = _sidCtrl.text.trim();
                if (sid.isEmpty) { _toast(ctx, 'Enter a student ID'); return; }
                await appState.assignEventRole(
                  eventId: eventId, studentId: sid, studentName: sid,
                  role: _selectedRole, permissions: List.from(_selectedPerms),
                );
                Navigator.pop(dialogCtx);
                _toast(ctx, '✅ $_selectedRole role assigned to $sid');
              },
              child: const Text('Assign Role'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final userId = appState.userId ?? '';
        return StreamBuilder<Event?>(
          stream: appState.watchEvent(widget.id),
          builder: (context, eventSnap) {
            final event = eventSnap.data;
            return StreamBuilder<List<EventRole>>(
              stream: appState.watchEventRoles(widget.id),
              builder: (context, rolesSnap) {
                final roles = rolesSnap.data ?? const <EventRole>[];
        final isCreator = event?.hostStudentId == userId;
        final isTeamMember = roles.any((r) => r.studentId == userId);

        // Access guard: event must be published and user must be creator
        if (event == null || event.status != 'Published') {
          return _guardScaffold(context, 'Not Available',
              'This event must be approved and published first.',
              Icons.event_busy_rounded);
        }
        if (!isCreator && !isTeamMember) {
          return _guardScaffold(context, 'Access Denied',
              'Only the event creator and assigned team members can access this panel.',
              Icons.lock_rounded);
        }

        final profile     = appState.currentUserProfile;
        final creatorName = profile?.name ?? userId;

        return Scaffold(
          backgroundColor: AppTheme.bgApp,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
                decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis),
              const Text('Creator Dashboard',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_rounded, size: 20), text: 'Overview'),
                Tab(icon: Icon(Icons.people_rounded,    size: 20), text: 'Participants'),
                Tab(icon: Icon(Icons.badge_rounded,     size: 20), text: 'Roles'),
                Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 20), text: 'Entry'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOverview(context, appState, event),
              _buildParticipants(context, appState, event.id, event.isPaid),
              _buildRoles(context, appState, event.id, userId, creatorName),
              _buildEntry(context, appState, event.id),
            ],
          ),
        );
              },
            );
          },
        );
      },
    );
  }

  Scaffold _guardScaffold(
      BuildContext ctx, String title, String subtitle, IconData icon) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => ctx.pop(),
        ),
        title: const Text('Manage Event',
            style: TextStyle(color: Colors.white)),
      ),
      body: EmptyState(title: title, subtitle: subtitle, icon: icon),
    );
  }
}

// ── Shared Helper Widgets ─────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(
                fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final EventMessage m;
  const _MessageBubble(this.m);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.senderRole == 'admin'
              ? AppTheme.red.withOpacity(0.06)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: m.senderRole == 'admin'
                ? AppTheme.red.withOpacity(0.2)
                : AppTheme.textMuted.withOpacity(0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              m.senderRole == 'admin'
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded,
              size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(m.senderRole == 'admin' ? 'Admin' : 'You',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(m.timestamp,
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          ]),
          const SizedBox(height: 6),
          Text(m.message,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ]),
      );
}

class _ParticipantCard extends StatelessWidget {
  final EventJoining joining;
  final bool isPaid;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  const _ParticipantCard({
    required this.joining, required this.isPaid,
    this.onApprove, this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (joining.status) {
      'Approved' => const Color(0xFF4CAF50),
      'Rejected'  => AppTheme.danger,
      _           => AppTheme.gold,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.red.withOpacity(0.1),
              child: Text(
                joining.name.isNotEmpty ? joining.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppTheme.red, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(joining.name, style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
              Text(joining.courseName, style: const TextStyle(
                  fontSize: 11, color: AppTheme.textMuted)),
              if (joining.clubId != null && joining.clubId!.isNotEmpty)
                Text('Club: ${joining.clubId}', style: const TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _MiniChip(joining.status, statusColor),
              if (isPaid) ...[
                const SizedBox(height: 4),
                _MiniChip(
                  joining.paymentStatus == 'Completed' ? 'Paid' : 'Unpaid',
                  joining.paymentStatus == 'Completed'
                      ? const Color(0xFF4CAF50)
                      : AppTheme.gold,
                ),
              ],
              if (joining.hasAttended) ...[
                const SizedBox(height: 4),
                const _MiniChip('Attended', AppTheme.red),
              ],
            ]),
          ]),
          // QR code preview
          if (joining.qrTicketCode != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.bgApp,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.textMuted.withOpacity(0.15)),
              ),
              child: Row(children: [
                const Icon(Icons.qr_code_rounded, size: 12, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(joining.qrTicketCode!,
                    style: const TextStyle(fontSize: 10,
                        fontFamily: 'monospace', color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
          // Approve / Reject buttons (pending only)
          if (joining.status == 'Pending' &&
              (onApprove != null || onReject != null)) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (onReject != null)
                Expanded(child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.danger.withOpacity(0.5)),
                    foregroundColor: AppTheme.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Reject',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                )),
              const SizedBox(width: 8),
              if (onApprove != null)
                Expanded(child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Approve',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                )),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String name, studentId, role;
  final List<String> permissions;
  final VoidCallback? onRemove;
  const _RoleCard({
    required this.name, required this.studentId,
    required this.role, required this.permissions, this.onRemove,
  });

  Color get _roleColor => switch (role) {
    'Creator'    => AppTheme.red,
    'Organizer'  => const Color(0xFF9C27B0),
    'Staff'      => const Color(0xFF2196F3),
    _            => const Color(0xFF4CAF50),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _roleColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roleColor.withOpacity(0.25)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _roleColor.withOpacity(0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: _roleColor,
                fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13)),
          Text(studentId, style: const TextStyle(
              fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _MiniChip(role, _roleColor),
            ...permissions.map((p) => _MiniChip(switch (p) {
              'scan_qr'             => 'Scan QR',
              'manage_participants' => 'Manage',
              'edit_event'          => 'Edit',
              _                     => p,
            }, AppTheme.textMuted)),
          ]),
        ])),
        if (onRemove != null)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                color: AppTheme.danger, size: 20),
            onPressed: onRemove,
          ),
      ]),
    );
  }
}

class _AttendeeRow extends StatelessWidget {
  final EventJoining joining;
  final bool checked;
  const _AttendeeRow(this.joining, {required this.checked});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked
                ? const Color(0xFF4CAF50).withOpacity(0.35)
                : AppTheme.textMuted.withOpacity(0.15)),
        ),
        child: Row(children: [
          Icon(
            checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: checked ? const Color(0xFF4CAF50) : AppTheme.textMuted,
            size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(joining.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Text(joining.courseName,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ]),
      );
}

class _MiniChip extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniChip(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w700, color: color)),
      );
}
