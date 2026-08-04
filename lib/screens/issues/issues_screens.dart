import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../services/data_service.dart';
import '../../services/app_state.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
  content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
  behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.textPrimary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
  title: Text(t), backgroundColor: Colors.transparent,
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => ctx.pop()));

// ── Screen 15: Issues Hub ────────────────────────────────────────
class IssuesHubScreen extends StatefulWidget {
  const IssuesHubScreen({super.key});
  @override State<IssuesHubScreen> createState() => _IssuesHubScreenState();
}

class _IssuesHubScreenState extends State<IssuesHubScreen> {
  late final Stream<List<Issue>> _issues;

  @override
  void initState() {
    super.initState();
    _issues = context.read<AppState>().watchMyIssues();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _issues,
      builder: (context, snapshot) {
        final issues = snapshot.data ?? const <Issue>[];
        final inProg = issues.where((i) => i.status == 'In Progress').length;
        final res    = issues.where((i) => i.status == 'Resolved').length;
        final newC   = issues.where((i) => i.status == 'New').length;
        final count  = issues.length;
        return Scaffold(
          body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NoticeBox(message: 'Use this to report facility, safety, IT, or other campus problems. Max 5 reports per day.'),
            HubButton(icon: Icons.warning_amber_rounded, label: 'Report an Issue', subtitle: 'Submit a new campus issue', isPrimary: true, onTap: () => context.push('/issues/report')).animate().fadeIn(delay:50.ms).slideY(begin:0.2),
            HubButton(icon: Icons.description_rounded, label: 'My Issues', subtitle: '$count submitted', onTap: () => context.push('/issues/my-issues')).animate().fadeIn(delay:100.ms).slideY(begin:0.2),
            const SectionLabel('My Stats'),
            Row(children: [
              Expanded(child: StatCard(value: '$inProg', label: 'In Progress', valueColor: AppTheme.red, bgColor: AppTheme.red.withOpacity(0.06))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '$res', label: 'Resolved', valueColor: AppTheme.redDark, bgColor: AppTheme.red.withOpacity(0.07))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '$newC', label: 'New')),
            ]).animate().fadeIn(delay:150.ms),
          ]))),
        );
      },
    );
  }
}

// ── Screen 16: Report Issue ──────────────────────────────────────
class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});
  @override State<ReportIssueScreen> createState() => _ReportIssueState();
}
class _ReportIssueState extends State<ReportIssueScreen> {
  final _key = GlobalKey<FormState>();
  String? _cat, _loc;
  final _titleC = TextEditingController();
  final _descC  = TextEditingController();
  bool _done = false;
  bool _submitting = false;
  List<String> _selectedImages = [];
  static const _cats = ['Facilities','Safety','Cleanliness','IT','Other'];
  static const _locs = ['Block A','Block B','Block C','Library','Cafeteria','Sports Complex','Main Entrance','Other'];

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (pickedFiles.isNotEmpty) {
      setState(() => _selectedImages = pickedFiles.map((f) => f.path).toList());
    }
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _selectedImages.add(pickedFile.path));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _SuccessIssue(onHome: () => context.go('/issues'), onView: () => context.push('/issues/my-issues'));
    return Scaffold(
      appBar: _appBar('Report an Issue', context),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _key, child: Column(children: [
        NoticeBox(message: 'Please report genuine issues only. Abuse may result in restrictions.', borderColor: AppTheme.danger, bgColor: AppTheme.danger.withOpacity(0.06), textColor: const Color(0xFF8B2020), icon: Icons.warning_amber_rounded),
        _Drop(label: 'Category', value: _cat, items: _cats, onChanged: (v) => setState(() => _cat = v)),
        _Field(label: 'Issue Title', hint: 'Brief title', ctrl: _titleC, validator: (v) => v!.isEmpty ? 'Required' : null),
        _Area(label: 'Description', hint: 'Describe the problem in detail…', ctrl: _descC),
        _Drop(label: 'Location', value: _loc, items: _locs, onChanged: (v) => setState(() => _loc = v)),
        const SizedBox(height: 16),
        // Image attachment section
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attach Photos (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.image_rounded, size: 18),
              label: const Text('Upload', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: AppTheme.red, width: 1),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: _captureImage,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Camera', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: AppTheme.red, width: 1),
              ),
            )),
          ]),
          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(height: 100, child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_selectedImages[i]), width: 100, height: 100, fit: BoxFit.cover)),
                  Positioned(top: -4, right: -4, child: GestureDetector(
                    onTap: () => _removeImage(i),
                    child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)),
                  )),
                ]),
              ),
            )),
            Text('${_selectedImages.length} photo(s) selected', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ]))),
        const SizedBox(height: 16),
        GradientButton(label: 'Submit Issue', onPressed: _submitting ? null : () async {
          if (!(_key.currentState!.validate() && _cat != null && _loc != null)) return;
          setState(() => _submitting = true);
          final created = await context.read<AppState>().createIssue(
            title: _titleC.text.trim(),
            category: _cat!,
            location: _loc!,
            description: _descC.text.trim(),
            imagePaths: _selectedImages,
          );
          if (!mounted) return;
          if (created != null) {
            setState(() => _done = true);
          } else {
            setState(() => _submitting = false);
            _toast(context, 'Could not submit the issue. Please try again.');
          }
        }),
        const SizedBox(height: 10),
        OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
      ]))),
    );
  }
}

// ── Screen 17: My Issues ─────────────────────────────────────────
class MyIssuesScreen extends StatefulWidget {
  const MyIssuesScreen({super.key});
  @override State<MyIssuesScreen> createState() => _MyIssuesScreenState();
}

class _MyIssuesScreenState extends State<MyIssuesScreen> {
  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<List<Issue>> _issues;

  @override
  void initState() {
    super.initState();
    _issues = context.read<AppState>().watchMyIssues();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _issues,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <Issue>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        // The service maps every FirebaseException to an AuthFailure, so this
        // message is already safe to show.
        final error = snapshot.error;
        return Scaffold(
          appBar: _appBar('My Issues', context),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/issues/report'),
            backgroundColor: AppTheme.red,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          body: isLoading && data.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Issues',
                      subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : data.isEmpty
                      ? const EmptyState(title: 'No Issues Yet', subtitle: 'You haven\'t submitted any issues.', icon: Icons.task_alt_rounded)
                      : ListView.builder(padding: const EdgeInsets.fromLTRB(16,16,16,80), itemCount: data.length, itemBuilder: (ctx, i) {
                          final it = data[i];
                          return CardRow(title: it.title, subtitle: '${it.category} · ${it.location}', extra: 'Updated ${relativeTime(it.updatedDate)}', status: it.status, onTap: () => context.push('/issues/detail/${it.id}')).animate().fadeIn(delay: (i*60).ms).slideY(begin:0.15);
                        }),
        );
      },
    );
  }
}

// ── Screen 18: Issue Detail (Student) ───────────────────────────
class IssueDetailScreen extends StatefulWidget {
  final String id;
  const IssueDetailScreen({super.key, required this.id});
  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  /// Held in fields so rebuilds do not re-subscribe to Firestore.
  late final Stream<Issue?> _issue;
  late final Stream<List<IssueHistory>> _history;

  @override
  void initState() {
    super.initState();
    // The screen knows only the document ID from the route; AppState resolves
    // the streams against the signed-in caller. No Firebase import here.
    final appState = context.read<AppState>();
    _issue = appState.watchIssue(widget.id);
    _history = appState.watchIssueHistory(widget.id);
  }

  Future<void> _setStatus(String status, String toast) async {
    final ok = await context.read<AppState>().updateIssueStatus(widget.id, status);
    if (!mounted) return;
    _toast(context, ok ? toast : 'Could not update the issue. Please try again.');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Issue?>(
      stream: _issue,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final it = snapshot.data;

        if (isLoading && it == null) {
          return Scaffold(appBar: _appBar(widget.id, context), body: const Center(child: CircularProgressIndicator(color: AppTheme.red)));
        }
        if (error != null) {
          return Scaffold(appBar: _appBar(widget.id, context), body: EmptyState(
            title: 'Could Not Load Issue',
            subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
            icon: Icons.cloud_off_rounded,
          ));
        }
        if (it == null) {
          return Scaffold(appBar: _appBar(widget.id, context), body: const EmptyState(title: 'Issue Not Found', subtitle: 'This issue may have been removed.', icon: Icons.search_off_rounded));
        }

        return Scaffold(
          appBar: _appBar(it.id, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), StatusBadge(it.status)]),
              const Divider(height: 20),
              InfoRow(label: 'Category', value: it.category),
              InfoRow(label: 'Location', value: it.location),
              InfoRow(label: 'Submitted', value: fmtDate(it.createdDate)),
              InfoRow(label: 'Last Updated', value: fmtDate(it.updatedDate)),
              const Divider(height: 12),
              const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text(it.description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.65)),
              // Display attached images if any
              if (it.imagePaths.isNotEmpty) ...[
                const Divider(height: 20),
                const Text('Attached Photos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: it.imagePaths.map((path) =>
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover))
                ).toList()),
              ],
            ]))),
            if (it.status == 'Resolved') ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.red.withOpacity(0.25))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Is this issue resolved for you?', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: GradientButton(label: 'Yes, close it', gradient: const LinearGradient(colors: [AppTheme.red, AppTheme.redDark]), onPressed: () => _setStatus('Closed - Verified', 'Issue closed. Thank you!'))),
                  const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'No, still not fixed', gradient: const LinearGradient(colors: [AppTheme.danger, Color(0xFFC04848)]), onPressed: () => _setStatus('In Progress', 'Feedback sent. Issue re-opened.'))),
                ]),
              ])),
            ],
            StreamBuilder<List<IssueHistory>>(
              stream: _history,
              builder: (context, histSnap) {
                final hist = histSnap.data ?? const <IssueHistory>[];
                if (hist.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Status Timeline'),
                  ...hist.map((h) => _TimelineItem(date: h.date, text: (h.from != null ? '${h.from} → ${h.to}' : 'Created: ${h.to}') + (h.note != null ? ' — ${h.note}' : ''))),
                ]);
              },
            ),
          ])),
        );
      },
    );
  }
}

// ── Screen 19: Issues Dashboard (Admin) ─────────────────────────
class AdminIssuesDashboardScreen extends StatelessWidget {
  const AdminIssuesDashboardScreen({super.key});

  /// Held in a field so the widget is const-constructible while still
  /// subscribing once per AppState instance.
  static Stream<List<Issue>> _stream(BuildContext ctx) =>
      ctx.read<AppState>().watchAllIssues();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _stream(context),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Issue>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final cats = ['Facilities','Safety','IT','Cleanliness','Other'];
        return Scaffold(
          body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 10),
            if (error != null)
              EmptyState(
                title: 'Could Not Load Issues',
                subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
                icon: Icons.cloud_off_rounded,
              )
            else ...[
              Row(children: [
                Expanded(child: StatCard(value: '${all.where((i) => i.status=='New').length}', label: 'New')),
                const SizedBox(width: 10),
                Expanded(child: StatCard(value: '${all.where((i) => i.status=='In Progress' || i.status=='Assigned').length}', label: 'In Progress', valueColor: AppTheme.red, bgColor: AppTheme.red.withOpacity(0.06))),
                const SizedBox(width: 10),
                Expanded(child: StatCard(value: '${all.where((i) => i.status=='Resolved').length}', label: 'Resolved', valueColor: AppTheme.redDark, bgColor: AppTheme.red.withOpacity(0.07))),
              ]).animate().fadeIn(delay:50.ms),
              if (isLoading && all.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator(color: AppTheme.red))),
              const SectionLabel('Category Breakdown'),
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: cats.map((cat) {
                final count = all.where((i) => i.category == cat).length;
                final pct   = all.isNotEmpty ? count / all.length : 0.0;
                return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(cat, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), Text('$count', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))]),
                  const SizedBox(height: 5),
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pct, backgroundColor: AppTheme.red.withOpacity(0.08), color: AppTheme.red, minHeight: 6)),
                ]));
              }).toList()))),
              GradientButton(label: 'View All Issues', onPressed: () => context.push('/admin/issues/list')),
            ],
          ]))),
        );
      },
    );
  }
}

// ── Screen 20: Issues List (Admin) ───────────────────────────────
class AdminIssuesListScreen extends StatelessWidget {
  const AdminIssuesListScreen({super.key});

  static Stream<List<Issue>> _stream(BuildContext ctx) =>
      ctx.read<AppState>().watchAllIssues();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _stream(context),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <Issue>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _appBar('All Issues', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Expanded(child: error != null
                ? EmptyState(
                    title: 'Could Not Load Issues',
                    subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
                    icon: Icons.cloud_off_rounded,
                  )
                : isLoading && data.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
                    : data.isEmpty
                        ? const EmptyState(title: 'No Issues', subtitle: 'No issues have been reported yet.', icon: Icons.task_alt_rounded)
                        : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                            final it = data[i];
                            return CardRow(title: it.title, subtitle: '${it.studentId ?? ''} · ${it.category} · ${it.location}', extra: fmtDate(it.createdDate), status: it.status, onTap: () => context.push('/admin/issues/detail/${it.id}')).animate().fadeIn(delay: (i*55).ms).slideY(begin:0.12);
                          }),
            ),
          ]),
        );
      },
    );
  }
}

// ── Screen 21: Issue Detail (Admin) ─────────────────────────────
// CRITICAL BUG FIX: _selectedStatus was being reset on every rebuild
// because it was assigned inside build(). Now uses _initialized flag
// to only set it once from the issue data, preserving dropdown changes.
class AdminIssueDetailScreen extends StatefulWidget {
  final String id;
  const AdminIssueDetailScreen({super.key, required this.id});
  @override
  State<AdminIssueDetailScreen> createState() => _AdminIssueDetailScreenState();
}

class _AdminIssueDetailScreenState extends State<AdminIssueDetailScreen> {
  String? _selectedStatus;
  bool _initialized = false;

  /// Held in fields so rebuilds do not re-subscribe to Firestore.
  late final Stream<Issue?> _issue;
  late final Stream<List<IssueHistory>> _history;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _issue = appState.watchIssue(widget.id);
    _history = appState.watchIssueHistory(widget.id);
  }

  void _confirmDelete(BuildContext context, Issue issue) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Issue', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete "${issue.title}"?\n\nThis action cannot be undone and will remove the issue from both admin and student views.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await context.read<AppState>().deleteIssue(issue.id);
              if (!mounted) return;
              _toast(context, ok ? 'Issue "${issue.title}" deleted' : 'Could not delete the issue. Please try again.');
              if (ok) context.pop(); // Go back to issues list
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Issue?>(
      stream: _issue,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        final it = snapshot.data;

        if (isLoading && it == null) {
          return Scaffold(appBar: _appBar('Issue', context), body: const Center(child: CircularProgressIndicator(color: AppTheme.red)));
        }
        if (error != null) {
          return Scaffold(appBar: _appBar('Issue', context), body: EmptyState(
            title: 'Could Not Load Issue',
            subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
            icon: Icons.cloud_off_rounded,
          ));
        }
        if (it == null || it.id.isEmpty) {
          return Scaffold(appBar: _appBar('Issue', context), body: const Center(child: EmptyState(title: 'Issue Not Found', subtitle: 'This issue may have been deleted.', icon: Icons.search_off_rounded)));
        }

        // Only initialize _selectedStatus once from the issue data.
        // After that, the dropdown controls _selectedStatus independently.
        if (!_initialized) {
          _selectedStatus = it.status;
          _initialized = true;
        }

        return Scaffold(
          appBar: _appBar(it.id, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [Expanded(child: Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), StatusBadge(it.status)]),
              const Divider(height: 18),
              if (it.studentId != null) InfoRow(label: 'Student ID', value: it.studentId!),
              InfoRow(label: 'Category', value: it.category),
              InfoRow(label: 'Location', value: it.location),
              InfoRow(label: 'Created', value: fmtDate(it.createdDate)),
              InfoRow(label: 'Last Updated', value: fmtDate(it.updatedDate)),
              const Divider(height: 12),
              const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Text(it.description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.65)),
              // Display attached images if any
              if (it.imagePaths.isNotEmpty) ...[
                const Divider(height: 20),
                const Text('Attached Photos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: it.imagePaths.map((path) =>
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover))
                ).toList()),
              ],
            ]))),
            const SectionLabel('Update Status'),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(labelText: 'Change Status'),
                items: ['New','Triaged','Assigned','In Progress','Resolved','Closed - Verified'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (value) => setState(() => _selectedStatus = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: 'Facilities Management',
                decoration: const InputDecoration(labelText: 'Assigned Department'),
                items: ['Facilities Management','IT Services','Security Office','Housekeeping','General Admin'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              TextFormField(maxLines: 3, decoration: const InputDecoration(labelText: 'Admin Note', hintText: 'Note about this status change…', alignLabelWithHint: true)),
            ]))),
            const SizedBox(height: 4),
            GradientButton(
              label: 'Update Status',
              onPressed: () async {
                if (_selectedStatus != null && _selectedStatus != it.status) {
                  final ok = await context.read<AppState>().updateIssueStatus(it.id, _selectedStatus!);
                  if (!mounted) return;
                  if (ok) {
                    _toast(context, 'Status updated to $_selectedStatus');
                    // Reset initialized so the next stream emission re-syncs
                    // _selectedStatus from the persisted document.
                    setState(() => _initialized = false);
                  } else {
                    _toast(context, 'Could not update the issue. Please try again.');
                  }
                } else if (_selectedStatus == it.status) {
                  _toast(context, 'Status is already "$_selectedStatus"');
                }
              },
            ),
            const SizedBox(height: 8),
            // Delete Issue button with confirmation
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmDelete(context, it),
                icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger),
                label: const Text('Delete Issue', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.danger, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            StreamBuilder<List<IssueHistory>>(
              stream: _history,
              builder: (context, histSnap) {
                final hist = histSnap.data ?? const <IssueHistory>[];
                if (hist.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Timeline'),
                  ...hist.map((h) => _TimelineItem(date: h.date, text: (h.from != null ? '${h.from} → ${h.to}' : 'Created: ${h.to}') + (h.note != null ? ' — ${h.note}' : ''))),
                ]);
              },
            ),
          ])),
        );
      },
    );
  }
}

// ── Timeline Item ────────────────────────────────────────────────
class _TimelineItem extends StatelessWidget {
  final String date, text;
  const _TimelineItem({required this.date, required this.text});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(left: 16, bottom: 10), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Column(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: AppTheme.red, shape: BoxShape.circle, border: Border.all(color: AppTheme.creamLight, width: 2))), Expanded(child: Container(width: 2, color: AppTheme.red.withOpacity(0.2)))]),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(fmtDate(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.red)), const SizedBox(height: 2), Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5)), const SizedBox(height: 8)])),
  ])));
}

// ── Shared helpers ────────────────────────────────────────────────
class _Drop extends StatelessWidget {
  final String label; final String? value; final List<String> items; final void Function(String?) onChanged;
  const _Drop({required this.label, required this.value, required this.items, required this.onChanged});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(initialValue: value, decoration: InputDecoration(labelText: label),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged));
}
class _Field extends StatelessWidget {
  final String label, hint; final TextEditingController ctrl; final String? Function(String?)? validator;
  const _Field({required this.label, required this.hint, required this.ctrl, this.validator});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: ctrl, validator: validator, decoration: InputDecoration(labelText: label, hintText: hint)));
}
class _Area extends StatelessWidget {
  final String label, hint; final TextEditingController ctrl;
  const _Area({required this.label, required this.hint, required this.ctrl});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: ctrl, maxLines: 4, decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: true)));
}

class _SuccessIssue extends StatelessWidget {
  final VoidCallback onHome, onView;
  const _SuccessIssue({required this.onHome, required this.onView});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.2), AppTheme.redLight.withOpacity(0.15)]), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: AppTheme.red, size: 40)).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.elasticOut),
    const SizedBox(height: 24),
    const Text('Issue Reported!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)).animate().fadeIn(delay: 200.ms),
    const SizedBox(height: 12),
    const Text('Your issue has been submitted. You will be notified as the status updates.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.65)).animate().fadeIn(delay: 300.ms),
    const SizedBox(height: 28),
    GradientButton(label: 'View My Issues', onPressed: onView),
    const SizedBox(height: 10),
    OutlineBtn(label: 'Back to Hub', onPressed: onHome),
  ]))));
}
