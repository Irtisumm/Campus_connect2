import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';
import '../../services/app_state.dart';

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

/// The dashboard's "In Progress" card represents the active-work portion of
/// the issue pipeline, not only the literal `In Progress` wire value.
bool _isIssueInProgress(Issue issue) =>
    issue.status == 'Triaged' ||
    issue.status == 'Assigned' ||
    issue.status == 'In Progress';

// ── Screen 15: Issues Hub ────────────────────────────────────────
class IssuesHubScreen extends StatefulWidget {
  const IssuesHubScreen({super.key});
  @override
  State<IssuesHubScreen> createState() => _IssuesHubScreenState();
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
        final inProg = issues.where(_isIssueInProgress).length;
        final res = issues.where((i) => i.status == 'Resolved').length;
        final newC = issues.where((i) => i.status == 'New').length;
        final count = issues.length;
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
                  const _IssueInfoCard(),
                  const SizedBox(height: 14),
                  _IssueActionCard(
                    icon: Icons.warning_amber_rounded,
                    title: 'Report an Issue',
                    subtitle: 'Submit a new campus issue',
                    isPrimary: true,
                    onTap: () => context.push('/issues/report'),
                  ),
                  const SizedBox(height: 10),
                  _IssueActionCard(
                    icon: Icons.description_rounded,
                    title: 'My Issues',
                    subtitle: '$count submitted',
                    onTap: () => context.push('/issues/my-issues'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'MY STATS',
                    style: Luxe.sectionLabel.copyWith(
                      color: Luxe.inkSoft,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _IssueStatCard(
                          value: '$inProg',
                          label: 'In Progress',
                          icon: Icons.schedule_rounded,
                          valueColor: Luxe.primary,
                          backgroundColor:
                              Luxe.primary.withValues(alpha: 0.045),
                          iconBackground: Luxe.primary.withValues(alpha: 0.08),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _IssueStatCard(
                          value: '$res',
                          label: 'Resolved',
                          icon: Icons.check_circle_outline_rounded,
                          valueColor: const Color(0xFFF08A24),
                          backgroundColor: const Color(0xFFFFF8F0),
                          iconBackground: const Color(0xFFFFEBD9),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _IssueStatCard(
                          value: '$newC',
                          label: 'New',
                          icon: Icons.add_rounded,
                          valueColor: const Color(0xFF3FA65A),
                          backgroundColor: const Color(0xFFF5FBF5),
                          iconBackground: const Color(0xFFE4F4E5),
                        ),
                      ),
                    ],
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

class _IssueInfoCard extends StatelessWidget {
  const _IssueInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Luxe.primary.withValues(alpha: 0.16)),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: 0.7),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Luxe.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Use this to report facility, safety, IT, or other campus problems. Max 5 reports per day.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: Luxe.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const _IssueInfoIllustration(),
        ],
      ),
    );
  }
}

class _IssueInfoIllustration extends StatelessWidget {
  const _IssueInfoIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 24,
            height: 40,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: Luxe.primary.withValues(alpha: 0.22),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: Luxe.primary,
              size: 19,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 4,
            child: Transform.rotate(
              angle: 0.25,
              child: Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: Luxe.primary.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  const _IssueActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final titleColor = isPrimary ? Colors.white : Luxe.ink;
    final subtitleColor =
        isPrimary ? Colors.white.withValues(alpha: 0.9) : Luxe.inkSoft;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 108,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.18)
                        : Luxe.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: isPrimary ? Colors.white : Luxe.primary,
                  ),
                ),
                const SizedBox(width: 10),
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
                              fontSize: 16,
                              height: 1.18,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
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
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.94)
                        : Luxe.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: Luxe.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IssueStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color valueColor;
  final Color backgroundColor;
  final Color iconBackground;

  const _IssueStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.valueColor,
    required this.backgroundColor,
    required this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: valueColor.withValues(alpha: 0.14)),
        boxShadow: Luxe.lift(tint: valueColor, strength: 0.45),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: valueColor, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: Luxe.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Screen 16: Report Issue ──────────────────────────────────────
class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});
  @override
  State<ReportIssueScreen> createState() => _ReportIssueState();
}

class _ReportIssueState extends State<ReportIssueScreen> {
  final _key = GlobalKey<FormState>();
  String? _cat, _loc;
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  bool _done = false;
  bool _submitting = false;
  List<String> _selectedImages = [];
  static const _cats = ['Facilities', 'Safety', 'Cleanliness', 'IT', 'Other'];
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

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(
        maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (pickedFiles.isNotEmpty) {
      setState(() => _selectedImages = pickedFiles.map((f) => f.path).toList());
    }
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _selectedImages.add(pickedFile.path));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    if (_done)
      return _SuccessIssue(
          onHome: () => context.go('/issues'),
          onView: () => context.push('/issues/my-issues'));
    return Scaffold(
      appBar: _appBar('Report an Issue', context),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
              key: _key,
              child: Column(children: [
                NoticeBox(
                    message:
                        'Please report genuine issues only. Abuse may result in restrictions.',
                    borderColor: AppTheme.danger,
                    bgColor: AppTheme.danger.withOpacity(0.06),
                    textColor: const Color(0xFF8B2020),
                    icon: Icons.warning_amber_rounded),
                _Drop(
                    label: 'Category',
                    value: _cat,
                    items: _cats,
                    onChanged: (v) => setState(() => _cat = v)),
                _Field(
                    label: 'Issue Title',
                    hint: 'Brief title',
                    ctrl: _titleC,
                    validator: (v) => v!.isEmpty ? 'Required' : null),
                _Area(
                    label: 'Description',
                    hint: 'Describe the problem in detail…',
                    ctrl: _descC),
                _Drop(
                    label: 'Location',
                    value: _loc,
                    items: _locs,
                    onChanged: (v) => setState(() => _loc = v)),
                const SizedBox(height: 16),
                // Image attachment section
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Attach Photos (Optional)',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textMuted)),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: OutlinedButton.icon(
                                  onPressed: _pickImages,
                                  icon:
                                      const Icon(Icons.image_rounded, size: 18),
                                  label: const Text('Upload',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    side: const BorderSide(
                                        color: AppTheme.red, width: 1),
                                  ),
                                )),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: OutlinedButton.icon(
                                  onPressed: _captureImage,
                                  icon: const Icon(Icons.camera_alt_rounded,
                                      size: 18),
                                  label: const Text('Camera',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    side: const BorderSide(
                                        color: AppTheme.red, width: 1),
                                  ),
                                )),
                              ]),
                              if (_selectedImages.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                    height: 100,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _selectedImages.length,
                                      itemBuilder: (ctx, i) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 10),
                                        child: Stack(children: [
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.file(
                                                  File(_selectedImages[i]),
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover)),
                                          Positioned(
                                              top: -4,
                                              right: -4,
                                              child: GestureDetector(
                                                onTap: () => _removeImage(i),
                                                child: Container(
                                                    width: 24,
                                                    height: 24,
                                                    decoration:
                                                        const BoxDecoration(
                                                            color:
                                                                AppTheme.danger,
                                                            shape: BoxShape
                                                                .circle),
                                                    child: const Icon(
                                                        Icons.close_rounded,
                                                        color: Colors.white,
                                                        size: 14)),
                                              )),
                                        ]),
                                      ),
                                    )),
                                Text(
                                    '${_selectedImages.length} photo(s) selected',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted)),
                              ],
                            ]))),
                const SizedBox(height: 16),
                GradientButton(
                    label: 'Submit Issue',
                    onPressed: _submitting
                        ? null
                        : () async {
                            if (!(_key.currentState!.validate() &&
                                _cat != null &&
                                _loc != null)) return;
                            setState(() => _submitting = true);
                            final created =
                                await context.read<AppState>().createIssue(
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
                              _toast(context,
                                  'Could not submit the issue. Please try again.');
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
  @override
  State<MyIssuesScreen> createState() => _MyIssuesScreenState();
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
            label: const Text('Report',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          body: isLoading && data.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Issues',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : data.isEmpty
                      ? const EmptyState(
                          title: 'No Issues Yet',
                          subtitle: 'You haven\'t submitted any issues.',
                          icon: Icons.task_alt_rounded)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                          itemCount: data.length,
                          itemBuilder: (ctx, i) {
                            final it = data[i];
                            return CardRow(
                                    title: it.title,
                                    subtitle: '${it.category} · ${it.location}',
                                    extra:
                                        'Updated ${relativeTime(it.updatedDate)}',
                                    status: it.status,
                                    onTap: () =>
                                        context.push('/issues/detail/${it.id}'))
                                .animate()
                                .fadeIn(delay: (i * 60).ms)
                                .slideY(begin: 0.15);
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
    final ok =
        await context.read<AppState>().updateIssueStatus(widget.id, status);
    if (!mounted) return;
    _toast(
        context, ok ? toast : 'Could not update the issue. Please try again.');
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
          return Scaffold(
              appBar: _appBar(widget.id, context),
              body: const Center(
                  child: CircularProgressIndicator(color: AppTheme.red)));
        }
        if (error != null) {
          return Scaffold(
              appBar: _appBar(widget.id, context),
              body: EmptyState(
                title: 'Could Not Load Issue',
                subtitle: error is AuthFailure
                    ? error.message
                    : 'Something went wrong. Please try again.',
                icon: Icons.cloud_off_rounded,
              ));
        }
        if (it == null) {
          return Scaffold(
              appBar: _appBar(widget.id, context),
              body: const EmptyState(
                  title: 'Issue Not Found',
                  subtitle: 'This issue may have been removed.',
                  icon: Icons.search_off_rounded));
        }

        return Scaffold(
          appBar: _appBar(it.id, context),
          body: SingleChildScrollView(
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
                                        child: Text(it.title,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800))),
                                    StatusBadge(it.status)
                                  ]),
                                  const Divider(height: 20),
                                  InfoRow(
                                      label: 'Category', value: it.category),
                                  InfoRow(
                                      label: 'Location', value: it.location),
                                  InfoRow(
                                      label: 'Submitted',
                                      value: fmtDate(it.createdDate)),
                                  InfoRow(
                                      label: 'Last Updated',
                                      value: fmtDate(it.updatedDate)),
                                  const Divider(height: 12),
                                  const Text('Description',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textMuted)),
                                  const SizedBox(height: 8),
                                  Text(it.description,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSecondary,
                                          height: 1.65)),
                                  // Display attached images if any
                                  if (it.imagePaths.isNotEmpty) ...[
                                    const Divider(height: 20),
                                    const Text('Attached Photos',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(height: 10),
                                    Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: it.imagePaths
                                            .map((path) => ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: Image.file(File(path),
                                                    width: 100,
                                                    height: 100,
                                                    fit: BoxFit.cover)))
                                            .toList()),
                                  ],
                                ]))),
                    if (it.status == 'Resolved') ...[
                      const SizedBox(height: 8),
                      Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: AppTheme.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppTheme.red.withOpacity(0.25))),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Is this issue resolved for you?',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                      child: GradientButton(
                                          label: 'Yes, close it',
                                          gradient: const LinearGradient(
                                              colors: [
                                                AppTheme.red,
                                                AppTheme.redDark
                                              ]),
                                          onPressed: () => _setStatus(
                                              'Closed - Verified',
                                              'Issue closed. Thank you!'))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: GradientButton(
                                          label: 'No, still not fixed',
                                          gradient: const LinearGradient(
                                              colors: [
                                                AppTheme.danger,
                                                Color(0xFFC04848)
                                              ]),
                                          onPressed: () => _setStatus(
                                              'In Progress',
                                              'Feedback sent. Issue re-opened.'))),
                                ]),
                              ])),
                    ],
                    StreamBuilder<List<IssueHistory>>(
                      stream: _history,
                      builder: (context, histSnap) {
                        final hist = histSnap.data ?? const <IssueHistory>[];
                        if (hist.isEmpty) return const SizedBox.shrink();
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionLabel('Status Timeline'),
                              ...hist.map((h) => _TimelineItem(
                                  date: h.date,
                                  text: (h.from != null
                                          ? '${h.from} → ${h.to}'
                                          : 'Created: ${h.to}') +
                                      (h.note != null ? ' — ${h.note}' : ''))),
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
class AdminIssuesDashboardScreen extends StatefulWidget {
  const AdminIssuesDashboardScreen({super.key});

  @override
  State<AdminIssuesDashboardScreen> createState() =>
      _AdminIssuesDashboardScreenState();
}

class _AdminIssuesDashboardScreenState
    extends State<AdminIssuesDashboardScreen> {
  /// Keep one subscription for the lifetime of the dashboard. Rebuilding the
  /// parent must not replace the Firestore stream and briefly reset the
  /// dashboard to its loading state.
  late final Stream<List<Issue>> _issues;

  @override
  void initState() {
    super.initState();
    _issues = context.read<AppState>().watchAllIssues();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _issues,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Issue>[];
        final ready = snapshot.hasData && !snapshot.hasError;
        final error = snapshot.error;
        final newCount = all.where((i) => i.status == 'New').length;
        // The card is the active-work bucket for the documented pipeline:
        // New -> Triaged -> Assigned -> In Progress -> Resolved.
        final inProgressCount = all.where(_isIssueInProgress).length;
        final resolvedCount = all
            .where((i) => i.status == 'Resolved' || i.status == 'Closed')
            .length;
        final categoryData = <_AdminIssueCategoryData>[
          _AdminIssueCategoryData(
            label: 'Facilities',
            icon: Icons.business_outlined,
            count: all.where((i) => i.category == 'Facilities').length,
            color: _AdminIssuesPalette.purple,
            tint: _AdminIssuesPalette.purpleTint,
          ),
          _AdminIssueCategoryData(
            label: 'Safety',
            icon: Icons.shield_outlined,
            count: all.where((i) => i.category == 'Safety').length,
            color: _AdminIssuesPalette.pink,
            tint: _AdminIssuesPalette.pinkTint,
          ),
          _AdminIssueCategoryData(
            label: 'IT',
            icon: Icons.desktop_windows_outlined,
            count: all.where((i) => i.category == 'IT').length,
            color: _AdminIssuesPalette.blue,
            tint: _AdminIssuesPalette.blueTint,
          ),
          _AdminIssueCategoryData(
            label: 'Cleanliness',
            icon: Icons.cleaning_services_outlined,
            count: all.where((i) => i.category == 'Cleanliness').length,
            color: _AdminIssuesPalette.orange,
            tint: _AdminIssuesPalette.orangeTint,
          ),
          _AdminIssueCategoryData(
            label: 'Other',
            icon: Icons.grid_view_rounded,
            count: all.where((i) => i.category == 'Other').length,
            color: _AdminIssuesPalette.green,
            tint: _AdminIssuesPalette.greenTint,
          ),
        ];
        String displayCount(int value) => ready ? '$value' : '—';

        return Scaffold(
          backgroundColor: _AdminIssuesPalette.background,
          drawer: const _AdminIssuesDrawer(),
          body: SafeArea(
            top: true,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 640 ? 28.0 : 20.0;
                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    8,
                    horizontal,
                    104 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    const _AdminIssuesIdentityRow(),
                    const SizedBox(height: 12),
                    const _AdminIssuesModeCard(),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _AdminIssueStatCard(
                            icon: Icons.note_add_outlined,
                            value: displayCount(newCount),
                            label: 'New',
                            color: _AdminIssuesPalette.pink,
                            tint: _AdminIssuesPalette.pinkTint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AdminIssueStatCard(
                            icon: Icons.hourglass_empty_rounded,
                            value: displayCount(inProgressCount),
                            label: 'In Progress',
                            color: _AdminIssuesPalette.orange,
                            tint: _AdminIssuesPalette.orangeTint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AdminIssueStatCard(
                            icon: Icons.check_circle_outline_rounded,
                            value: displayCount(resolvedCount),
                            label: 'Resolved',
                            color: _AdminIssuesPalette.green,
                            tint: _AdminIssuesPalette.greenTint,
                          ),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      _AdminIssuesError(
                        message: error is AuthFailure
                            ? error.message
                            : 'Something went wrong. Please try again.',
                      ),
                    ],
                    _AdminIssuesSectionHeader(
                      label: 'Category Breakdown',
                      onViewAll: () => context.push('/admin/issues/list'),
                    ),
                    _AdminIssueCategoryCard(
                      categories: categoryData,
                      ready: ready,
                      total: all.length,
                    ),
                    const SizedBox(height: 20),
                    _AdminIssuesPrimaryButton(
                      onTap: () => context.push('/admin/issues/list'),
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

class _AdminIssuesPalette {
  static const background = Color(0xFFFFFCFB);
  static const ink = Color(0xFF15233B);
  static const muted = Color(0xFF64748B);
  static const hairline = Color(0xFFEFE8EA);
  static const pink = Color(0xFFD71958);
  static const pinkBright = Color(0xFFF65E7B);
  static const pinkTint = Color(0xFFFFE8EF);
  static const gold = Color(0xFFA46808);
  static const goldTint = Color(0xFFFFF2DD);
  static const green = Color(0xFF159447);
  static const greenTint = Color(0xFFE6F5E9);
  static const blue = Color(0xFF2E72D3);
  static const blueTint = Color(0xFFEAF2FF);
  static const purple = Color(0xFF7135B8);
  static const purpleTint = Color(0xFFF3EAFF);
  static const orange = Color(0xFFD97706);
  static const orangeTint = Color(0xFFFFF0DE);
}

class _AdminIssuesIdentityRow extends StatelessWidget {
  const _AdminIssuesIdentityRow();

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
                child: _AdminIssuesRoleChip(
                  onTap: () async {
                    await context.read<AppState>().logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ),
              SizedBox(width: gap),
              _AdminIssuesIconButton(
                size: controlSize,
                icon: Icons.person_outline_rounded,
                onTap: () => context.push('/profile'),
              ),
              SizedBox(width: gap),
              _AdminIssuesNotificationButton(size: controlSize),
            ],
          ),
        );
      },
    );
  }
}

class _AdminIssuesIconButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminIssuesIconButton({
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

class _AdminIssuesRoleChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminIssuesRoleChip({required this.onTap});

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
            children: [
              const Icon(Icons.shield_rounded,
                  color: _AdminIssuesPalette.gold, size: 17),
              const SizedBox(width: 5),
              const Text('Admin',
                  style: TextStyle(
                      color: _AdminIssuesPalette.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 3),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _AdminIssuesPalette.gold, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminIssuesNotificationButton extends StatelessWidget {
  final double size;

  const _AdminIssuesNotificationButton({required this.size});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return StreamBuilder<int>(
      stream: appState.watchUnreadCampusNotifications(),
      initialData: 0,
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _AdminIssuesIconButton(
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
                        color: _AdminIssuesPalette.gold,
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

class _AdminIssuesModeCard extends StatelessWidget {
  const _AdminIssuesModeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _AdminIssuesPalette.goldTint.withValues(alpha: .34),
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
              color: _AdminIssuesPalette.goldTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.shield_outlined,
                color: _AdminIssuesPalette.gold, size: 25),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADMIN MODE',
                  style: TextStyle(
                    color: _AdminIssuesPalette.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'You have full access to manage the platform.',
                  style: TextStyle(
                    color: _AdminIssuesPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: _AdminIssuesPalette.gold, size: 25),
        ],
      ),
    );
  }
}

class _AdminIssueStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color tint;

  const _AdminIssueStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each card receives the same finite width from the parent Row. Keep
        // the height fixed as well so a wrapped status label cannot make one
        // card taller than its neighbours on a narrow phone.
        final compact = constraints.maxWidth < 112;
        final cardHeight = compact ? 94.0 : 100.0;
        final iconBoxSize = compact ? 38.0 : 42.0;
        final iconSize = compact ? 21.0 : 24.0;
        final valueSize = compact ? 27.0 : 29.0;
        final labelSize = compact ? 11.0 : 12.0;

        return SizedBox(
          height: cardHeight,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(21),
              // Rounded borders must use one color on every side. The
              // stronger status accent is painted as a clipped strip below.
              border: Border.all(color: color.withValues(alpha: .08)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .11),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 12,
                      compact ? 12 : 14,
                      compact ? 6 : 10,
                      compact ? 11 : 13,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(icon, color: color, size: iconSize),
                        ),
                        SizedBox(width: compact ? 7 : 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                value,
                                maxLines: 1,
                                style: TextStyle(
                                  color: color,
                                  fontSize: valueSize,
                                  height: .98,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _AdminIssuesPalette.ink,
                                  fontSize: labelSize,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 3,
                      child: ColoredBox(color: color),
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

class _AdminIssueCategoryData {
  final String label;
  final IconData icon;
  final int count;
  final Color color;
  final Color tint;

  const _AdminIssueCategoryData({
    required this.label,
    required this.icon,
    required this.count,
    required this.color,
    required this.tint,
  });
}

class _AdminIssueCategoryCard extends StatelessWidget {
  final List<_AdminIssueCategoryData> categories;
  final bool ready;
  final int total;

  const _AdminIssueCategoryCard({
    required this.categories,
    required this.ready,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _AdminIssuesPalette.hairline),
        boxShadow: [
          BoxShadow(
            color: _AdminIssuesPalette.ink.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            _AdminIssueCategoryRow(
              data: categories[i],
              ready: ready,
              progress: total == 0 ? 0 : categories[i].count / total,
            ),
            if (i < categories.length - 1) const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _AdminIssueCategoryRow extends StatelessWidget {
  final _AdminIssueCategoryData data;
  final bool ready;
  final double progress;

  const _AdminIssueCategoryRow({
    required this.data,
    required this.ready,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.tint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: data.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: const TextStyle(
                    color: _AdminIssuesPalette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ready ? progress : 0,
                    minHeight: 7,
                    backgroundColor:
                        _AdminIssuesPalette.pink.withValues(alpha: .09),
                    color: data.count > 0
                        ? data.color.withValues(alpha: .78)
                        : data.color.withValues(alpha: .16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 20,
            child: Text(
              ready ? '${data.count}' : '—',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _AdminIssuesPalette.muted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Icon(Icons.chevron_right_rounded,
              color: _AdminIssuesPalette.muted, size: 24),
        ],
      ),
    );
  }
}

class _AdminIssuesSectionHeader extends StatelessWidget {
  final String label;
  final VoidCallback? onViewAll;

  const _AdminIssuesSectionHeader({required this.label, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: _AdminIssuesPalette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.05,
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
                        color: _AdminIssuesPalette.pink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: _AdminIssuesPalette.pink, size: 13),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminIssuesPrimaryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminIssuesPrimaryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                _AdminIssuesPalette.pinkBright,
                _AdminIssuesPalette.pink,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _AdminIssuesPalette.pink.withValues(alpha: .24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.format_list_bulleted_rounded,
                  color: Colors.white, size: 25),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'View All Issues',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminIssuesError extends StatelessWidget {
  final String message;

  const _AdminIssuesError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AdminIssuesPalette.pinkTint.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: _AdminIssuesPalette.pink.withValues(alpha: .14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: _AdminIssuesPalette.pink, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _AdminIssuesPalette.muted,
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

class _AdminIssuesDrawer extends StatelessWidget {
  const _AdminIssuesDrawer();

  @override
  Widget build(BuildContext context) {
    void open(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    return Drawer(
      backgroundColor: _AdminIssuesPalette.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Row(
              children: [
                Icon(Icons.school_rounded,
                    color: _AdminIssuesPalette.pink, size: 27),
                SizedBox(width: 10),
                Text(
                  'Admin tools',
                  style: TextStyle(
                    color: _AdminIssuesPalette.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _AdminIssuesDrawerItem(
              icon: Icons.search_rounded,
              label: 'Lost & Found',
              onTap: () => open('/lost-found'),
            ),
            _AdminIssuesDrawerItem(
              icon: Icons.warning_amber_rounded,
              label: 'Issues',
              selected: true,
              onTap: () => Navigator.of(context).pop(),
            ),
            _AdminIssuesDrawerItem(
              icon: Icons.event_outlined,
              label: 'Events',
              onTap: () => open('/events'),
            ),
            _AdminIssuesDrawerItem(
              icon: Icons.lock_outline_rounded,
              label: 'Lockers',
              onTap: () => open('/lockers'),
            ),
            const Divider(height: 30, color: _AdminIssuesPalette.hairline),
            _AdminIssuesDrawerItem(
              icon: Icons.list_alt_rounded,
              label: 'All Issues',
              onTap: () => open('/admin/issues/list'),
            ),
            _AdminIssuesDrawerItem(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Student Registrations',
              onTap: () => open('/admin/registrations'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminIssuesDrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AdminIssuesDrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? _AdminIssuesPalette.pinkTint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    color: selected
                        ? _AdminIssuesPalette.pink
                        : _AdminIssuesPalette.muted,
                    size: 22),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? _AdminIssuesPalette.pink
                        : _AdminIssuesPalette.ink,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        final raw = snapshot.data ?? const <Issue>[];
        final data = raw
            .where((it) => it.status != 'Resolved' && it.status != 'Closed')
            .toList();
        final archivedCount =
            raw.where((it) => it.status == 'Resolved' || it.status == 'Closed').length;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          appBar: _appBar('All Issues', context),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/admin/issues/archive'),
            icon: const Icon(Icons.archive_outlined),
            label: Text(archivedCount > 0
                ? 'Archive ($archivedCount)'
                : 'Archive'),
            backgroundColor: _AdminIssuesPalette.ink,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),
            Expanded(
              child: error != null
                  ? EmptyState(
                      title: 'Could Not Load Issues',
                      subtitle: error is AuthFailure
                          ? error.message
                          : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : isLoading && data.isEmpty && raw.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.red))
                      : data.isEmpty
                          ? const EmptyState(
                              title: 'No Active Issues',
                              subtitle:
                                  'All reported issues have been resolved or closed.',
                              icon: Icons.task_alt_rounded)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                              itemCount: data.length,
                              itemBuilder: (ctx, i) {
                                final it = data[i];
                                return CardRow(
                                        title: it.title,
                                        subtitle:
                                            '${it.studentId ?? ''} · ${it.category} · ${it.location}',
                                        extra: fmtDate(it.createdDate),
                                        status: it.status,
                                        onTap: () => context.push(
                                            '/admin/issues/detail/${it.id}'))
                                    .animate()
                                    .fadeIn(delay: (i * 55).ms)
                                    .slideY(begin: 0.12);
                              }),
            ),
          ]),
        );
      },
    );
  }
}

// ── Screen 20B: Issue Archive (Admin) ────────────────────────────
/// An admin-only read-only listing of every resolved or closed issue.
class AdminIssuesArchiveScreen extends StatelessWidget {
  const AdminIssuesArchiveScreen({super.key});

  static Stream<List<Issue>> _stream(BuildContext ctx) =>
      ctx.read<AppState>().watchAllIssues();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Issue>>(
      stream: _stream(context),
      builder: (context, snapshot) {
        final raw = snapshot.data ?? const <Issue>[];
        final data = raw
            .where((it) => it.status == 'Resolved' || it.status == 'Closed')
            .toList();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.error;
        return Scaffold(
          backgroundColor: _AdminIssuesPalette.background,
          appBar: _appBar(
            'Issue Archive${data.isNotEmpty ? ' (${data.length})' : ''}',
            context,
          ),
          body: error != null
              ? EmptyState(
                  title: 'Could Not Load Archive',
                  subtitle: error is AuthFailure
                      ? error.message
                      : 'Something went wrong. Please try again.',
                  icon: Icons.cloud_off_rounded,
                )
              : isLoading && data.isEmpty && raw.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.red))
                  : data.isEmpty
                      ? const EmptyState(
                          title: 'Archive Empty',
                          subtitle:
                              'No issues have been resolved or closed yet.',
                          icon: Icons.archive_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: data.length,
                          itemBuilder: (ctx, i) {
                            final it = data[i];
                            return CardRow(
                                    title: it.title,
                                    subtitle:
                                        '${it.studentId ?? ''} · ${it.category} · ${it.location}',
                                    extra: fmtDate(it.createdDate),
                                    status: it.status,
                                    onTap: () => context.push(
                                        '/admin/issues/detail/${it.id}'))
                                .animate()
                                .fadeIn(delay: (i * 55).ms)
                                .slideY(begin: 0.12);
                          }),
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
        title: const Text('Delete Issue',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            'Are you sure you want to delete "${issue.title}"?\n\nThis action cannot be undone and will remove the issue from both admin and student views.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await context.read<AppState>().deleteIssue(issue.id);
              if (!mounted) return;
              _toast(
                  context,
                  ok
                      ? 'Issue "${issue.title}" deleted'
                      : 'Could not delete the issue. Please try again.');
              if (ok) context.pop(); // Go back to issues list
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: AppTheme.danger, fontWeight: FontWeight.w700)),
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
          return Scaffold(
              appBar: _appBar('Issue', context),
              body: const Center(
                  child: CircularProgressIndicator(color: AppTheme.red)));
        }
        if (error != null) {
          return Scaffold(
              appBar: _appBar('Issue', context),
              body: EmptyState(
                title: 'Could Not Load Issue',
                subtitle: error is AuthFailure
                    ? error.message
                    : 'Something went wrong. Please try again.',
                icon: Icons.cloud_off_rounded,
              ));
        }
        if (it == null || it.id.isEmpty) {
          return Scaffold(
              appBar: _appBar('Issue', context),
              body: const Center(
                  child: EmptyState(
                      title: 'Issue Not Found',
                      subtitle: 'This issue may have been deleted.',
                      icon: Icons.search_off_rounded)));
        }

        // Only initialize _selectedStatus once from the issue data.
        // After that, the dropdown controls _selectedStatus independently.
        if (!_initialized) {
          _selectedStatus = it.status;
          _initialized = true;
        }

        return Scaffold(
          appBar: _appBar(it.id, context),
          body: SingleChildScrollView(
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
                                    child: Text(it.title,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800))),
                                StatusBadge(it.status)
                              ]),
                              const Divider(height: 18),
                              if (it.studentId != null)
                                InfoRow(
                                    label: 'Student ID', value: it.studentId!),
                              InfoRow(label: 'Category', value: it.category),
                              InfoRow(label: 'Location', value: it.location),
                              InfoRow(
                                  label: 'Created',
                                  value: fmtDate(it.createdDate)),
                              InfoRow(
                                  label: 'Last Updated',
                                  value: fmtDate(it.updatedDate)),
                              const Divider(height: 12),
                              const Text('Description',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textMuted)),
                              const SizedBox(height: 8),
                              Text(it.description,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                      height: 1.65)),
                              // Display attached images if any
                              if (it.imagePaths.isNotEmpty) ...[
                                const Divider(height: 20),
                                const Text('Attached Photos',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textMuted)),
                                const SizedBox(height: 10),
                                Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: it.imagePaths
                                        .map((path) => ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.file(File(path),
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover)))
                                        .toList()),
                              ],
                            ]))),
                    const SectionLabel('Update Status'),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedStatus,
                                    decoration: const InputDecoration(
                                        labelText: 'Change Status'),
                                    items: [
                                      'New',
                                      'Triaged',
                                      'Assigned',
                                      'In Progress',
                                      'Resolved',
                                      'Closed - Verified'
                                    ]
                                        .map((s) => DropdownMenuItem(
                                            value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _selectedStatus = value),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: 'Facilities Management',
                                    decoration: const InputDecoration(
                                        labelText: 'Assigned Department'),
                                    items: [
                                      'Facilities Management',
                                      'IT Services',
                                      'Security Office',
                                      'Housekeeping',
                                      'General Admin'
                                    ]
                                        .map((s) => DropdownMenuItem(
                                            value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: (_) {},
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                      maxLines: 3,
                                      decoration: const InputDecoration(
                                          labelText: 'Admin Note',
                                          hintText:
                                              'Note about this status change…',
                                          alignLabelWithHint: true)),
                                ]))),
                    const SizedBox(height: 4),
                    GradientButton(
                      label: 'Update Status',
                      onPressed: () async {
                        if (_selectedStatus != null &&
                            _selectedStatus != it.status) {
                          final ok = await context
                              .read<AppState>()
                              .updateIssueStatus(it.id, _selectedStatus!);
                          if (!mounted) return;
                          if (ok) {
                            _toast(
                                context, 'Status updated to $_selectedStatus');
                            // Reset initialized so the next stream emission re-syncs
                            // _selectedStatus from the persisted document.
                            setState(() => _initialized = false);
                          } else {
                            _toast(context,
                                'Could not update the issue. Please try again.');
                          }
                        } else if (_selectedStatus == it.status) {
                          _toast(
                              context, 'Status is already "$_selectedStatus"');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    // Delete Issue button with confirmation
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDelete(context, it),
                        icon: const Icon(Icons.delete_forever_rounded,
                            color: AppTheme.danger),
                        label: const Text('Delete Issue',
                            style: TextStyle(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppTheme.danger, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    StreamBuilder<List<IssueHistory>>(
                      stream: _history,
                      builder: (context, histSnap) {
                        final hist = histSnap.data ?? const <IssueHistory>[];
                        if (hist.isEmpty) return const SizedBox.shrink();
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionLabel('Timeline'),
                              ...hist.map((h) => _TimelineItem(
                                  date: h.date,
                                  text: (h.from != null
                                          ? '${h.from} → ${h.to}'
                                          : 'Created: ${h.to}') +
                                      (h.note != null ? ' — ${h.note}' : ''))),
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
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 10),
      child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: AppTheme.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.creamLight, width: 2))),
          Expanded(
              child: Container(width: 2, color: AppTheme.red.withOpacity(0.2)))
        ]),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtDate(date),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.red)),
          const SizedBox(height: 2),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
          const SizedBox(height: 8)
        ])),
      ])));
}

// ── Shared helpers ────────────────────────────────────────────────
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

class _SuccessIssue extends StatelessWidget {
  final VoidCallback onHome, onView;
  const _SuccessIssue({required this.onHome, required this.onView});
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
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            color: AppTheme.red, size: 40))
                    .animate()
                    .scale(
                        delay: 100.ms,
                        duration: 400.ms,
                        curve: Curves.elasticOut),
                const SizedBox(height: 24),
                const Text('Issue Reported!',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800))
                    .animate()
                    .fadeIn(delay: 200.ms),
                const SizedBox(height: 12),
                const Text(
                        'Your issue has been submitted. You will be notified as the status updates.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.65))
                    .animate()
                    .fadeIn(delay: 300.ms),
                const SizedBox(height: 28),
                GradientButton(label: 'View My Issues', onPressed: onView),
                const SizedBox(height: 10),
                OutlineBtn(label: 'Back to Hub', onPressed: onHome),
              ]))));
}
