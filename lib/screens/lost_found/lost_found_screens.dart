import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';
import '../../services/data_service.dart';
import '../../services/lost_found_service.dart';
import '../../services/app_state.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppTheme.textPrimary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    duration: const Duration(seconds: 2),
  ));
}

AppBar _gradientAppBar(String title, BuildContext context, {List<Widget>? actions}) => AppBar(
  title: Text(title),
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  backgroundColor: Colors.transparent,
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
  actions: actions,
);

// ── Screen 1: Hub ────────────────────────────────────────────────
class LostFoundHubScreen extends StatelessWidget {
  const LostFoundHubScreen({super.key});

  /// Maps a report status onto the semantic palette. Kept tolerant of
  /// wording so new statuses degrade to neutral rather than crash.
  static Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('match') || s.contains('resolved') || s.contains('claimed')) {
      return Luxe.success;
    }
    if (s.contains('review') || s.contains('pending')) return Luxe.warning;
    if (s.contains('active') || s.contains('inventory')) return Luxe.info;
    return Luxe.inkMuted;
  }

  /// 'Matched - Pending' → 'Matched'. Keeps chips to a single word or two.
  static String _shortStatus(String status) => status.split(' - ').first.trim();

  /// Groups statuses into ordered {label: count} pairs for the chip row.
  static List<MapEntry<String, int>> _group(Iterable<String> statuses) {
    final counts = <String, int>{};
    for (final s in statuses) {
      final key = _shortStatus(s);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final lost = dataService.myLostReports;
        final found = dataService.myFoundReports;

        return Scaffold(
          backgroundColor: Luxe.bg,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(
                Luxe.s5 - 4, Luxe.s5, Luxe.s5 - 4, Luxe.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PrivacyCard()
                    .animate()
                    .fadeIn(duration: 420.ms)
                    .slideY(begin: 0.12, curve: Curves.easeOutCubic),
                const SizedBox(height: Luxe.s6),

                const LuxeSectionHeader('Report an Item'),
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
                )
                    .animate()
                    .fadeIn(delay: 80.ms, duration: 420.ms)
                    .slideY(begin: 0.14, curve: Curves.easeOutCubic),
                const SizedBox(height: Luxe.s3 + 2),
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
                )
                    .animate()
                    .fadeIn(delay: 150.ms, duration: 420.ms)
                    .slideY(begin: 0.14, curve: Curves.easeOutCubic),

                const SizedBox(height: Luxe.s6),
                const LuxeSectionHeader('My Reports'),
                _ReportSummaryCard(
                  title: 'My Lost Reports',
                  icon: Icons.description_rounded,
                  tint: Luxe.primary,
                  total: lost.length,
                  chips: _group(lost.map((r) => r.status)),
                  colorOf: _statusColor,
                  onTap: () => context.push('/lost-found/my-lost'),
                )
                    .animate()
                    .fadeIn(delay: 220.ms, duration: 420.ms)
                    .slideY(begin: 0.14, curve: Curves.easeOutCubic),
                const SizedBox(height: Luxe.s3 + 2),
                _ReportSummaryCard(
                  title: 'My Found Reports',
                  icon: Icons.upload_file_rounded,
                  tint: Luxe.accent,
                  total: found.length,
                  chips: _group(found.map((r) => r.status)),
                  colorOf: _statusColor,
                  onTap: () => context.push('/lost-found/my-found'),
                )
                    .animate()
                    .fadeIn(delay: 290.ms, duration: 420.ms)
                    .slideY(begin: 0.14, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ── Privacy card ──────────────────────────────────────────────────
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Luxe.s5 - 4),
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
                  const SizedBox(width: Luxe.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Privacy Protected',
                            style: Luxe.title.copyWith(fontSize: 18)),
                        const SizedBox(height: 5),
                        Text(
                          'Your information is securely encrypted and visible '
                          'only to authorised university staff.',
                          style: Luxe.body.copyWith(
                              fontSize: 13, color: Luxe.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Luxe.s4),
              Container(height: 1, color: Luxe.hairline),
              const SizedBox(height: Luxe.s3),
              const Wrap(
                spacing: Luxe.s2,
                runSpacing: Luxe.s2,
                children: [
                  LuxeSecurityChip('Secure'),
                  LuxeSecurityChip('Encrypted'),
                  LuxeSecurityChip('Trusted'),
                ],
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
    return Pressable(
      onTap: onTap,
      child: Container(
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
              padding: const EdgeInsets.symmetric(
                  horizontal: Luxe.s5 - 4, vertical: Luxe.s5),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(Luxe.rSmall + 4),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32)),
                    ),
                    child: Icon(icon, color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: Luxe.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Luxe.cardTitle.copyWith(color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Luxe.body.copyWith(
                                fontSize: 13,
                                height: 1.3,
                                color: Colors.white.withValues(alpha: 0.88))),
                      ],
                    ),
                  ),
                  const SizedBox(width: Luxe.s3),
                  const LuxeArrowButton(onDark: true, size: 44),
                ],
              ),
            ),
          ],
        ),
      ),
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
                              style: Luxe.caption
                                  .copyWith(color: Luxe.inkMuted)),
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
                          label: '${e.value} ${e.key}',
                          color: colorOf(e.key)),
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
  @override State<ReportLostScreen> createState() => _ReportLostState();
}
class _ReportLostState extends State<ReportLostScreen> {
  final _key = GlobalKey<FormState>();
  String? _cat, _loc;
  final _titleC = TextEditingController();
  final _descC  = TextEditingController();
  bool _done = false;
  bool _saving = false;

  static const _cats = ['Phone','Wallet','ID Card','Keys','Bag','Laptop','Books','Other'];
  static const _locs = ['Block A','Block B','Block C','Library','Cafeteria','Sports Complex','Main Entrance','Other'];

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
    final service = context.read<LostFoundService>();

    setState(() => _saving = true);
    try {
      await service.createItem(Item(
        type: ItemType.lost,
        title: _titleC.text,
        category: _cat!,
        description: _descC.text,
        whereLost: _loc!,
        whenLost: DateTime.now(),
        reportedByUid: appState.firebaseUid ?? '',
        reportedByStudentId: appState.userId ?? '',
      ));
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not submit your report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _SuccessView(title: 'Report Submitted!', msg: "Your item has been reported. Admin will review it. We'll notify you if a match is found.", onHome: () => context.go('/lost-found'), onSub: () => context.push('/lost-found/my-lost'), subLabel: 'View My Reports');
    return Scaffold(
      appBar: _gradientAppBar('Report Lost Item', context),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _key, child: Column(children: [
        const NoticeBox(message: 'Max 5 active reports. Provide a detailed description to improve match accuracy.'),
        _Drop(label: 'Category', value: _cat, items: _cats, onChanged: (v) => setState(() => _cat = v)),
        _Field(label: 'Item Title', hint: 'e.g. Blue Samsung Galaxy S23', ctrl: _titleC, validator: (v) => v!.isEmpty ? 'Required' : null),
        _Area(label: 'Description', hint: 'Color, brand, markings…', ctrl: _descC),
        _Drop(label: 'Where Lost', value: _loc, items: _locs, onChanged: (v) => setState(() => _loc = v)),
        _PhotoBox(),
        const SizedBox(height: 16),
        GradientButton(label: 'Submit Report', onPressed: _saving ? null : _submit),
        const SizedBox(height: 10),
        OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
      ]))),
    );
  }
}

// ── Screen 3: Report Found ───────────────────────────────────────
class ReportFoundScreen extends StatefulWidget {
  const ReportFoundScreen({super.key});
  @override State<ReportFoundScreen> createState() => _ReportFoundState();
}
class _ReportFoundState extends State<ReportFoundScreen> {
  String? _cat, _loc;
  final _descC = TextEditingController();
  bool _done = false;
  bool _saving = false;

  static const _cats = ['Phone','Wallet','ID Card','Keys','Bag','Laptop','Books','Other'];
  static const _locs = ['Block A','Block B','Block C','Library','Cafeteria','Sports Complex','Main Entrance','Other'];

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
    final service = context.read<LostFoundService>();

    setState(() => _saving = true);
    try {
      await service.createItem(Item(
        type: ItemType.found,
        // This form collects one free-text field. It is the item's headline in
        // every list that shows found reports, so it fills `title` as well —
        // `Item.title` is shared with the lost flow and the admin screens.
        title: _descC.text,
        category: _cat!,
        description: _descC.text,
        // `Item` has one location/date pair for both report types; for a found
        // report these hold where and when it was found.
        whereLost: _loc!,
        whenLost: DateTime.now(),
        reportedByUid: appState.firebaseUid ?? '',
        reportedByStudentId: appState.userId ?? '',
      ));
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not submit your report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _FoundReportStepperView(onHome: () => context.go('/lost-found'), onViewReports: () => context.push('/lost-found/my-found'));
    return Scaffold(
      appBar: _gradientAppBar('Report Found Item', context),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
        NoticeBox(message: 'Please hand the item to Lost & Found Office (Block A, Level 1) after submitting.', borderColor: AppTheme.red, bgColor: AppTheme.red.withOpacity(0.08), textColor: const Color(0xFF8B1428)),
        _Drop(label: 'Category', value: _cat, items: _cats, onChanged: (v) => setState(() => _cat = v)),
        _Area(label: 'Description', hint: 'Describe what you found', ctrl: _descC),
        _Drop(label: 'Where Found', value: _loc, items: _locs, onChanged: (v) => setState(() => _loc = v)),
        _PhotoBox(),
        const SizedBox(height: 16),
        GradientButton(label: 'Submit Report', onPressed: _saving ? null : _submit),
        const SizedBox(height: 10),
        OutlineBtn(label: 'Cancel', onPressed: () => context.pop()),
      ])),
    );
  }
}

// ── Screen 4: My Lost Reports ────────────────────────────────────
class MyLostReportsScreen extends StatefulWidget {
  const MyLostReportsScreen({super.key});
  @override State<MyLostReportsScreen> createState() => _MyLostReportsScreenState();
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
            TextButton.icon(onPressed: () => context.push('/lost-found/report-lost'), icon: const Icon(Icons.add, color: Colors.white, size: 16), label: const Text('Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ]),
          body: isLoading && data.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Reports',
                      subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : data.isEmpty
                      ? const EmptyState(title: 'No Lost Reports', icon: Icons.search_off_rounded)
                      : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                          final r = data[i];
                          return CardRow(title: r.title, subtitle: '${r.category} · ${r.whereLost}', extra: relativeTime(r.whenLostLabel), status: r.status.wireValue, onTap: () => context.push('/lost-found/lost/${r.id}')).animate().fadeIn(delay: (i*60).ms).slideY(begin: 0.15);
                        }),
        );
      },
    );
  }
}

// ── Screen 5: My Found Reports ───────────────────────────────────
class MyFoundReportsScreen extends StatefulWidget {
  const MyFoundReportsScreen({super.key});
  @override State<MyFoundReportsScreen> createState() => _MyFoundReportsScreenState();
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
              ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
              : error != null
                  ? EmptyState(
                      title: 'Could Not Load Reports',
                      subtitle: error is AuthFailure ? error.message : 'Something went wrong. Please try again.',
                      icon: Icons.cloud_off_rounded,
                    )
                  : data.isEmpty
                      ? const EmptyState(title: 'No Found Reports', icon: Icons.upload_file_rounded)
                      : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                          final r = data[i];
                          return CardRow(
                            title: r.description,
                            subtitle: '${r.category} · ${r.whereLost}',
                            extra: relativeTime(r.whenLostLabel),
                            status: r.status.wireValue,
                            onTap: () => context.push('/lost-found/found/${r.id}'),
                          ).animate().fadeIn(delay: (i*60).ms).slideY(begin: 0.15);
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

  @override
  void initState() {
    super.initState();
    // The screen knows only the document ID from the route; AppState resolves
    // the stream against the signed-in caller. No Firebase import here.
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
              ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
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
    // `matchStatus` (AI match banner) has no Firestore counterpart yet — AI
    // matching is out of scope for this phase. Held as an inert local so the
    // original NoticeBox keeps its place in the tree but renders only when a
    // match exists, which is never for a plain Firestore document today.
    const String? matchStatus = null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (matchStatus != null) NoticeBox(message: matchStatus, borderColor: AppTheme.red, icon: Icons.link_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(r.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                    StatusBadge(r.status.wireValue),
                  ]),
                  const Divider(height: 20),
                  InfoRow(label: 'Category', value: r.category),
                  InfoRow(label: 'Where Lost', value: r.whereLost),
                  InfoRow(label: 'When Lost', value: fmtDate(r.whenLostLabel)),
                  const Divider(height: 12),
                  const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  Text(r.description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.65)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // The "Close Report" action is mock-backed and out of scope for this
          // phase (no Firestore write path exists yet). The button is kept
          // visually unchanged per the no-redesign rule, but its tap surfaces the
          // situation instead of calling DataService or fabricating a write.
          if (r.status == ItemStatus.active) OutlineBtn(
            label: 'Close Report',
            color: AppTheme.danger,
            onPressed: () => _toast(context, 'Closing reports is not available yet.'),
          ),
        ],
      ),
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
  final _qrController = TextEditingController();

  /// Held in a field so rebuilds do not re-subscribe to Firestore.
  late final Stream<Item?> _report;

  @override
  void initState() {
    super.initState();
    // Only the route's document ID is needed; AppState resolves the stream. No
    // Firebase import reaches this file.
    _report = context.read<AppState>().watchReport(widget.id);
  }

  @override
  void dispose() {
    _qrController.dispose();
    super.dispose();
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
              ? const Center(child: CircularProgressIndicator(color: AppTheme.red))
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
    // QR / handover fields (`qrCode`, `qrScanned`, `handoverStatus`,
    // `handoverStep`) exist only in mock_data.dart — they have no Firestore
    // counterpart yet, and QR handover is out of scope for this phase. The
    // original widgets are kept in the tree per the no-redesign rule; with no
    // backing data the QR section and handover notice simply do not render,
    // and the stepper sits at its initial step.
    final String? qrCode = null;
    final bool qrScanned = false;
    final String? handoverStatus = null;
    // Found reports store their location/date in the shared `whereLost` /
    // `whenLost` fields (see Phase 4's `_ReportFoundState._submit`), so those
    // back the "Where Found" / "When Found" rows here.
    final String whereFound = r.whereLost;
    final String whenFound = r.whenLostLabel;

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
                    Expanded(child: Text(r.description, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                    StatusBadge(r.status.wireValue),
                  ]),
                  const Divider(height: 20),
                  InfoRow(label: 'Category', value: r.category),
                  InfoRow(label: 'Where Found', value: whereFound),
                  InfoRow(label: 'When Found', value: fmtDate(whenFound)),
                  if (handoverStatus != null) ...[
                    const Divider(height: 16),
                    InfoRow(label: 'Handover Status', value: handoverStatus),
                  ],
                  if (qrScanned) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('QR Code verified - Item handover confirmed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Handover Progress Stepper
          const SizedBox(height: 10),
          const _HandoverStepper(currentStep: 1),

          // QR Scan section - shown when handover is pending (QR generated by admin but not yet scanned)
          if (qrCode != null && !qrScanned) ...[
            const SectionLabel('Scan QR Code'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const NoticeBox(
                message: 'The admin has generated a QR code for item handover. Enter the code below to confirm you have handed over the item.',
                icon: Icons.qr_code_scanner_rounded,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _qrController,
                decoration: InputDecoration(
                  hintText: 'Enter QR code here...',
                  prefixIcon: const Icon(Icons.qr_code_rounded, color: AppTheme.red),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.red.withOpacity(0.3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.red, width: 2)),
                ),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              const SizedBox(height: 14),
              GradientButton(
                label: 'Verify & Confirm Handover',
                // QR handover is mock-backed and out of scope for this phase.
                // The button never renders (its `if` guard is false without a
                // Firestore QR field), but to stay free of DataService it
                // surfaces the situation if it ever did.
                onPressed: () => _toast(context, 'QR handover is not available yet.'),
              ),
            ]))),
          ],

          // Show info when no QR generated yet
          if (qrCode == null && !qrScanned && r.status.wireValue == 'In Inventory') ...[
            const SizedBox(height: 10),
            const NoticeBox(
              message: 'Please hand the item to the Lost & Found Office (Block A, Level 1). The admin will generate a QR code for you to scan as proof of handover.',
              icon: Icons.info_outline_rounded,
            ),
          ],
        ],
      ),
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
          Text('Done!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Item handover has been confirmed successfully.\n\nThank you for handing over the found item. You can track the progress in "My Found Reports".', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.55)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Screen 8: Notifications ──────────────────────────────────────
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final ns = dataService.getNotificationsForUser(appState.userId, appState.isAdmin);
        return Scaffold(
          appBar: _gradientAppBar('Notifications', context),
          body: ns.isEmpty
              ? const EmptyState(title: 'No Notifications', icon: Icons.notifications_off_rounded)
              : ListView.builder(padding: const EdgeInsets.all(16), itemCount: ns.length, itemBuilder: (ctx, i) {
                  final n = ns[i];
                  return GestureDetector(
                    onTap: () {
                      if (!n.read) {
                        dataService.markNotificationAsRead(n.id);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: n.read ? AppTheme.bgCard : AppTheme.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: n.read ? AppTheme.red.withOpacity(0.1) : AppTheme.red.withOpacity(0.25)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        leading: CircleAvatar(backgroundColor: n.type == 'personal' ? AppTheme.red.withOpacity(0.12) : AppTheme.gold.withOpacity(0.2),
                            child: Icon(n.type == 'personal' ? Icons.person_rounded : Icons.campaign_rounded, color: n.type == 'personal' ? AppTheme.red : AppTheme.goldDark, size: 20)),
                        title: Text(n.text, style: TextStyle(fontSize: 13, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700, color: AppTheme.textPrimary)),
                        subtitle: Text(n.time, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        trailing: n.read ? null : Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.red, shape: BoxShape.circle)),
                      ),
                    ),
                  ).animate().fadeIn(delay: (i*55).ms).slideX(begin: 0.1);
                }),
        );
      },
    );
  }
}

// ── Screen 9: Admin L&F Dashboard ───────────────────────────────
class AdminLFDashboardScreen extends StatelessWidget {
  const AdminLFDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final active = dataService.allLostReports.where((r) => r.status == 'Active').length;
        final pending = dataService.matches.where((m) => m.status == 'Pending').length;
        return Scaffold(
          body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatCard(value: '$active', label: 'Active Lost')),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '${dataService.myFoundReports.length}', label: 'In Inventory', valueColor: AppTheme.redDark, bgColor: AppTheme.red.withOpacity(0.07))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '$pending', label: 'Pending Matches', valueColor: const Color(0xFFB03030), bgColor: const Color(0x08D65E5E))),
            ]).animate().fadeIn(delay: 50.ms),
            const SectionLabel('Quick Actions'),
            HubButton(icon: Icons.list_alt_rounded, label: 'View Lost Reports', subtitle: '${dataService.allLostReports.length} total', onTap: () => context.push('/admin/lost-found/lost-list')).animate().fadeIn(delay:100.ms),
            HubButton(icon: Icons.inventory_rounded, label: 'Found / Inventory', subtitle: '${dataService.myFoundReports.length} items', isAmber: true, onTap: () => context.push('/admin/lost-found/found-list')).animate().fadeIn(delay:150.ms),
            HubButton(icon: Icons.compare_arrows_rounded, label: 'Review Matches', subtitle: '$pending pending', onTap: () => context.push('/admin/lost-found/match-list')).animate().fadeIn(delay:200.ms),
            const SectionLabel('Admin Tools'),
            HubButton(icon: Icons.person_add_rounded, label: 'Student Registrations', subtitle: '${appState.pendingStudentAccounts} pending approval', onTap: () => context.push('/admin/registrations')).animate().fadeIn(delay:250.ms),
            // ── User Analytics Section ──
            const SectionLabel('User Analytics'),
            Row(children: [
              Expanded(child: StatCard(value: '${appState.totalAccounts}', label: 'Total Accounts', valueColor: const Color(0xFF1B5E20), bgColor: const Color(0x0A4CAF50))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '${appState.totalStudentAccounts}', label: 'Students', valueColor: const Color(0xFF0D47A1), bgColor: const Color(0x0A2196F3))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(value: '${appState.totalAdminAccounts}', label: 'Admins', valueColor: const Color(0xFF6A1B9A), bgColor: const Color(0x0A9C27B0))),
            ]).animate().fadeIn(delay: 300.ms),
          ]))),
        );
      },
    );
  }
}

// ── Screen 10: Admin Lost List ───────────────────────────────────
class AdminLostListScreen extends StatelessWidget {
  const AdminLostListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final data = dataService.allLostReports;
        return Scaffold(
          appBar: _gradientAppBar('All Lost Reports', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Expanded(child: data.isEmpty
                ? const EmptyState(title: 'No Lost Reports', icon: Icons.search_off_rounded)
                : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                    final r = data[i];
                    return CardRow(
                      title: r.title, subtitle: '${r.studentId} · ${r.category}', extra: fmtDate(r.createdDate), status: r.status,
                      trailing: r.aiScore != null ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(999)),
                          child: Text('AI ${r.aiScore}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))) : null,
                      onTap: () => context.push('/admin/lost-found/lost/${r.id}'),
                    ).animate().fadeIn(delay: (i*55).ms).slideY(begin: 0.12);
                  })),
          ]),
        );
      },
    );
  }
}

// ── Screen 11: Admin Found List ──────────────────────────────────
class AdminFoundListScreen extends StatelessWidget {
  const AdminFoundListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final data = dataService.myFoundReports;
        return Scaffold(
          appBar: _gradientAppBar('Found / Inventory', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Expanded(child: data.isEmpty
                ? const EmptyState(title: 'No Found Reports', icon: Icons.inventory_rounded)
                : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                    final r = data[i];
                    return CardRow(title: r.description, subtitle: '${r.category} · ${r.whereFound}', extra: fmtDate(r.whenFound), status: r.status, onTap: () => context.push('/admin/lost-found/found/${r.id}')).animate().fadeIn(delay: (i*55).ms);
                  })),
          ]),
        );
      },
    );
  }
}

// ── Screen 12: Admin Lost Detail ─────────────────────────────────
class AdminLostDetailScreen extends StatelessWidget {
  final String id;
  const AdminLostDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final r = dataService.allLostReports.firstWhere((x) => x.id == id, orElse: () => dataService.allLostReports.first);
        final matchList = dataService.matches.where((m) => m.lostId == r.id).toList();
        return Scaffold(
          appBar: _gradientAppBar(r.id, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [Expanded(child: Text(r.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), StatusBadge(r.status)]),
              const Divider(height: 18),
              InfoRow(label: 'Student ID', value: r.studentId),
              InfoRow(label: 'Category', value: r.category),
              InfoRow(label: 'Where Lost', value: r.whereLost),
              InfoRow(label: 'Submitted', value: fmtDate(r.createdDate)),
            ]))),
            if (r.aiScore != null) ...[
              const SectionLabel('AI Match Score'),
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.08), AppTheme.redLight.withOpacity(0.06)]), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.red.withOpacity(0.2))),
                  child: Row(children: [const Icon(Icons.psychology_rounded, color: AppTheme.red, size: 28), const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('AI Confidence', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.red)),
                      Text('${r.aiScore}% match with ${r.matchedFoundId ?? "found item"}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ])])),
            ],
            if (matchList.isNotEmpty) ...[
              const SectionLabel('Potential Matches'),
              ...matchList.map((m) => Card(child: ListTile(title: Text('Found: ${m.foundId}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(m.notes), trailing: StatusBadge(m.status), onTap: () => context.push('/admin/lost-found/match/${m.id}')))),
            ],
            const SizedBox(height: 10),
            if (r.status != 'Resolved') GradientButton(label: 'Mark as Resolved', onPressed: () {
              dataService.updateAdminLostReportStatus(r.id, 'Resolved');
              _toast(context, 'Status updated to Resolved');
              context.pop();
            }),
          ])),
        );
      },
    );
  }
}

// ── Screen 13: Admin Found Detail ───────────────────────────────
class AdminFoundDetailScreen extends StatelessWidget {
  final String id;
  const AdminFoundDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final r = dataService.myFoundReports.firstWhere((x) => x.id == id, orElse: () => dataService.myFoundReports.first);
        return Scaffold(
          appBar: _gradientAppBar(r.id, context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
            const AdminBar(), const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [Expanded(child: Text(r.description, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), StatusBadge(r.status)]),
              const Divider(height: 18),
              InfoRow(label: 'Category', value: r.category),
              InfoRow(label: 'Where Found', value: r.whereFound),
              InfoRow(label: 'When Found', value: fmtDate(r.whenFound)),
              if (r.handoverStatus != null) ...[
                const Divider(height: 16),
                InfoRow(label: 'Handover Status', value: r.handoverStatus!),
              ],
              if (r.qrCode != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.red.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.qr_code_rounded, color: AppTheme.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('QR: ${r.qrCode}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary))),
                    if (r.qrScanned) const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                  ]),
                ),
              ],
            ]))),
            const SizedBox(height: 10),
            // Action buttons based on current status
            if (r.status == 'In Inventory') ...[
              GradientButton(label: 'Receive (Generate QR)', onPressed: () {
                final code = dataService.generateReceiveQR(r.id);
                _showQRDialog(context, 'Receive QR Code', code, 'Show this QR code to the student who found the item. They must scan it to confirm handover.');
              }),
              const SizedBox(height: 10),
              GradientButton(label: 'Handover to Claimant', onPressed: () {
                final code = dataService.generateHandoverQR(r.id);
                _showQRDialog(context, 'Handover QR Code', code, 'Show this QR code to the claiming student.\n\nPlease also:\n1. Fill in the Google Form for records\n2. Have both parties sign the register book\n\nAfter completion, tap "Complete Handover" to finalize.');
              }),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Mark as Resolved', onPressed: () {
                dataService.updateFoundReportStatus(r.id, 'Resolved');
                _toast(context, 'Marked as Resolved');
                context.pop();
              }),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Archive', color: AppTheme.danger, onPressed: () {
                dataService.updateFoundReportStatus(r.id, 'Archived');
                _toast(context, 'Archived');
                context.pop();
              }),
            ],
            if (r.status == 'Claiming') ...[
              GradientButton(label: 'Complete Handover', onPressed: () {
                dataService.completeHandover(r.id);
                _toast(context, 'Handover completed. Item resolved.');
                context.pop();
              }),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Cancel Handover', color: AppTheme.danger, onPressed: () {
                dataService.updateFoundReportStatus(r.id, 'In Inventory');
                _toast(context, 'Handover cancelled. Item back in inventory.');
              }),
            ],
            if (r.status == 'Received' || r.status == 'Resolved') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    r.status == 'Resolved' ? 'This item has been resolved and claimed.' : 'This item has been received.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green),
                  )),
                ]),
              ),
              if (r.status != 'Resolved') ...[
                const SizedBox(height: 10),
                OutlineBtn(label: 'Archive', color: AppTheme.danger, onPressed: () {
                  dataService.updateFoundReportStatus(r.id, 'Archived');
                  _toast(context, 'Archived');
                  context.pop();
                }),
              ],
            ],
          ])),
        );
      },
    );
  }
}

void _showQRDialog(BuildContext context, String title, String code, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.qr_code_2_rounded, color: AppTheme.red, size: 28),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.08), AppTheme.redLight.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.red.withOpacity(0.3), width: 2),
          ),
          child: Column(children: [
            const Icon(Icons.qr_code_2_rounded, size: 48, color: AppTheme.red),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(message, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.55), textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.red)),
        ),
      ],
    ),
  );
}

// ── Screen 14: Match Review ──────────────────────────────────────
class AdminMatchListScreen extends StatelessWidget {
  const AdminMatchListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final data = dataService.matches;
        return Scaffold(
          appBar: _gradientAppBar('Review Matches', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16,8,16,0), child: AdminBar()),
            Expanded(child: data.isEmpty
                ? const EmptyState(title: 'No Matches', icon: Icons.compare_arrows_rounded)
                : ListView.builder(padding: const EdgeInsets.all(16), itemCount: data.length, itemBuilder: (ctx, i) {
                    final m = data[i];
                    return CardRow(title: '${m.lostId} ↔ ${m.foundId}', subtitle: m.notes, status: m.status,
                      trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(999)),
                          child: Text('${m.score}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
                      onTap: () => context.push('/admin/lost-found/match/${m.id}'),
                    ).animate().fadeIn(delay: (i*60).ms);
                  })),
          ]),
        );
      },
    );
  }
}

class AdminMatchDetailScreen extends StatelessWidget {
  final String id;
  const AdminMatchDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final m = dataService.matches.firstWhere((x) => x.id == id, orElse: () => dataService.matches.first);
        return Scaffold(
          appBar: _gradientAppBar('Match ${m.id}', context),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AdminBar(), const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(10)),
                    child: Text('${m.score}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
                const SizedBox(width: 14),
                const Expanded(child: Text('AI Confidence Score', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                StatusBadge(m.status),
              ]),
              const Divider(height: 18),
              InfoRow(label: 'Lost Report', value: m.lostId),
              InfoRow(label: 'Found Report', value: m.foundId),
              const SizedBox(height: 10),
              Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.creamLight, borderRadius: BorderRadius.circular(10)),
                  child: Text(m.notes, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.55))),
            ]))),
            const SizedBox(height: 10),
            GradientButton(label: 'Confirm Match - Notify Student', onPressed: () => _toast(context, 'Match confirmed. Student notified.')),
            const SizedBox(height: 10),
            OutlineBtn(label: 'Reject Match', color: AppTheme.danger, onPressed: () => _toast(context, 'Match rejected')),
          ])),
        );
      },
    );
  }
}

// ── Shared Private Widgets ────────────────────────────────────────
class _Drop extends StatelessWidget {
  final String label; final String? value; final List<String> items; final void Function(String?) onChanged;
  const _Drop({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(initialValue: value, decoration: InputDecoration(labelText: label),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged));
}
class _Field extends StatelessWidget {
  final String label, hint; final TextEditingController ctrl; final String? Function(String?)? validator;
  const _Field({required this.label, required this.hint, required this.ctrl, this.validator});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: ctrl, validator: validator, decoration: InputDecoration(labelText: label, hintText: hint)));
}
class _Area extends StatelessWidget {
  final String label, hint; final TextEditingController ctrl;
  const _Area({required this.label, required this.hint, required this.ctrl});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(controller: ctrl, maxLines: 4, decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: true)));
}
class _PhotoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _toast(context, 'Photo upload available in installed APK'),
    child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.04), border: Border.all(color: AppTheme.red.withOpacity(0.25), width: 1.5), borderRadius: BorderRadius.circular(14)),
      child: const Column(children: [Icon(Icons.add_photo_alternate_rounded, size: 36, color: AppTheme.textMuted), SizedBox(height: 8),
        Text('Tap to add photo', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        Text('Optional', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))])));
}

class _SuccessView extends StatelessWidget {
  final String title, msg; final VoidCallback onHome; final VoidCallback? onSub; final String? subLabel;
  const _SuccessView({required this.title, required this.msg, required this.onHome, this.onSub, this.subLabel});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.2), AppTheme.redLight.withOpacity(0.15)]), shape: BoxShape.circle, border: Border.all(color: AppTheme.red.withOpacity(0.3))),
        child: const Icon(Icons.check_rounded, color: AppTheme.red, size: 40)).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.elasticOut),
    const SizedBox(height: 24),
    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)).animate().fadeIn(delay: 200.ms),
    const SizedBox(height: 12),
    Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.65)).animate().fadeIn(delay: 300.ms),
    const SizedBox(height: 28),
    GradientButton(label: 'Back to Hub', onPressed: onHome),
    if (onSub != null) ...[const SizedBox(height: 10), OutlineBtn(label: subLabel!, onPressed: onSub)],
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
              Text('Handover Progress', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
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
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isCompleted
                                ? const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)])
                                : isActive
                                    ? const LinearGradient(colors: [Color(0xFFC41E3A), Color(0xFFE8475F)])
                                    : null,
                            color: isPending ? const Color(0xFFB0BEC5) : null,
                            boxShadow: isActive ? [BoxShadow(color: AppTheme.red.withOpacity(0.3), blurRadius: 8)] : null,
                          ),
                          child: Center(
                            child: isCompleted
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                : Text('$stepNum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isPending ? Colors.white70 : Colors.white)),
                          ),
                        ),
                        // Connector line (not on last step)
                        if (i < _steps.length - 1)
                          Container(
                            width: 2, height: 28,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isCompleted ? const Color(0xFF4CAF50) : isActive ? AppTheme.red : const Color(0xFFE0E0E0),
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
                                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                  color: isCompleted ? const Color(0xFF4CAF50) : isActive ? AppTheme.red : AppTheme.textMuted,
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _steps[i]['subtitle']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isActive ? AppTheme.textSecondary : AppTheme.textMuted,
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
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.2), AppTheme.redLight.withOpacity(0.15)]),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                ),
                child: const Icon(Icons.check_rounded, color: AppTheme.red, size: 40),
              ).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 20),
              const Text('Found Item Reported!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 8),
              const Text('Follow these steps to complete the handover:', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 20),

              // Stepper showing step 1 completed, step 2 active
              const _HandoverStepper(currentStep: 2),

              const SizedBox(height: 24),
              GradientButton(label: 'View My Found Reports', onPressed: onViewReports ?? onHome),
              const SizedBox(height: 10),
              OutlineBtn(label: 'Back to Hub', onPressed: onHome),
            ],
          ),
        ),
      ),
    );
  }
}
