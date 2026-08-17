import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

// ── Screen: Admin Election Editor ─────────────────────────────────
/// Admin editor for the election configuration document.
///
/// Every field is seeded once from the Firestore stream — a `_loaded` guard
/// keeps later stream re-emits from clobbering in-progress edits — and the
/// whole document is written back through [AppState.updateElectionMeta].
/// Archived elections are frozen: the form renders but has no Save path.
class AdminElectionEditorScreen extends StatefulWidget {
  final String id;
  const AdminElectionEditorScreen({super.key, required this.id});

  @override
  State<AdminElectionEditorScreen> createState() =>
      _AdminElectionEditorScreenState();
}

/// Controllers for one editable timeline row (date + description + tone).
class _TimelineRowCtrls {
  final TextEditingController date;
  final TextEditingController description;
  String tone;

  _TimelineRowCtrls({
    required this.date,
    required this.description,
    this.tone = 'muted',
  });

  void dispose() {
    date.dispose();
    description.dispose();
  }
}

class _AdminElectionEditorScreenState extends State<AdminElectionEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _allPositionsCtrl = TextEditingController();
  final _noticeTitleCtrl = TextEditingController();
  final _noticeBodyCtrl = TextEditingController();
  final _aboutTitleCtrl = TextEditingController();
  final _aboutBodyCtrl = TextEditingController();
  final _timelineTitleCtrl = TextEditingController();
  final _upcomingCtrl = TextEditingController();
  final _positionsTitleCtrl = TextEditingController();
  final _howToVoteTitleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  final List<TextEditingController> _positionCtrls = [];
  final List<TextEditingController> _stepCtrls = [];
  final List<_TimelineRowCtrls> _timelineRows = [];

  StreamSubscription<ElectionMeta?>? _sub;
  ElectionMeta? _meta;
  bool _receivedFirstEmit = false;
  bool _loaded = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<AppState>().watchElectionMeta(widget.id).listen(
          _onMeta,
          onError: (Object _) => setState(() => _error = true),
        );
  }

  /// Stream events only seed the controllers once — user edits must never be
  /// overwritten by a Firestore re-emit. The latest document is still kept in
  /// [_meta] so the save path copies from the freshest status/archive fields.
  void _onMeta(ElectionMeta? meta) {
    setState(() {
      _receivedFirstEmit = true;
      _meta = meta;
      if (meta != null && !_loaded) {
        _seedFrom(meta);
        _loaded = true;
      }
    });
  }

  void _seedFrom(ElectionMeta meta) {
    _titleCtrl.text = meta.title;
    _allPositionsCtrl.text = meta.allPositionsLabel;
    _noticeTitleCtrl.text = meta.noticeTitle;
    _noticeBodyCtrl.text = meta.noticeBody;
    _aboutTitleCtrl.text = meta.aboutTitle;
    _aboutBodyCtrl.text = meta.aboutBody;
    _timelineTitleCtrl.text = meta.timelineTitle;
    _upcomingCtrl.text = meta.upcomingLabel;
    _positionsTitleCtrl.text = meta.positionsTitle;
    _howToVoteTitleCtrl.text = meta.howToVoteTitle;
    _locationCtrl.text = meta.pollingLocation;
    _dateCtrl.text = meta.pollingDate;
    _timeCtrl.text = meta.pollingTime;
    for (final position in meta.positions) {
      _positionCtrls.add(TextEditingController(text: position));
    }
    for (final step in meta.voteSteps) {
      _stepCtrls.add(TextEditingController(text: step));
    }
    for (final entry in meta.timeline) {
      _timelineRows.add(_TimelineRowCtrls(
        date: TextEditingController(text: entry.date),
        description: TextEditingController(text: entry.description),
        tone: entry.tone,
      ));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _titleCtrl.dispose();
    _allPositionsCtrl.dispose();
    _noticeTitleCtrl.dispose();
    _noticeBodyCtrl.dispose();
    _aboutTitleCtrl.dispose();
    _aboutBodyCtrl.dispose();
    _timelineTitleCtrl.dispose();
    _upcomingCtrl.dispose();
    _positionsTitleCtrl.dispose();
    _howToVoteTitleCtrl.dispose();
    _locationCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    for (final c in _positionCtrls) {
      c.dispose();
    }
    for (final c in _stepCtrls) {
      c.dispose();
    }
    for (final row in _timelineRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Validates and writes the edited document. `copyWith` passes only the
  /// edited fields, so the id, status and every archive field survive intact.
  Future<void> _save() async {
    final meta = _meta;
    if (meta == null) return;
    if (_titleCtrl.text.trim().isEmpty) {
      _toast(context, 'Title is required');
      return;
    }
    final updated = meta.copyWith(
      title: _titleCtrl.text.trim(),
      allPositionsLabel: _allPositionsCtrl.text,
      noticeTitle: _noticeTitleCtrl.text,
      noticeBody: _noticeBodyCtrl.text,
      aboutTitle: _aboutTitleCtrl.text,
      aboutBody: _aboutBodyCtrl.text,
      timelineTitle: _timelineTitleCtrl.text,
      upcomingLabel: _upcomingCtrl.text,
      positionsTitle: _positionsTitleCtrl.text,
      howToVoteTitle: _howToVoteTitleCtrl.text,
      pollingLocation: _locationCtrl.text,
      pollingDate: _dateCtrl.text,
      pollingTime: _timeCtrl.text,
      positions: [
        for (final c in _positionCtrls) c.text.trim()
      ].where((s) => s.isNotEmpty).toList(),
      voteSteps: [
        for (final c in _stepCtrls) c.text.trim()
      ].where((s) => s.isNotEmpty).toList(),
      timeline: [
        for (final row in _timelineRows)
          ElectionTimelineEntry(
            date: row.date.text.trim(),
            description: row.description.text.trim(),
            tone: row.tone,
          ),
      ],
    );
    final ok = await context.read<AppState>().updateElectionMeta(updated);
    if (!mounted) return;
    _toast(context, ok ? 'Election updated' : 'Save failed');
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final archived = meta?.isArchived ?? false;

    Widget body;
    if (_error) {
      body = const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Unable to load election',
        subtitle: 'Please check your connection and try again.',
      );
    } else if (!_receivedFirstEmit) {
      body = const Center(child: CircularProgressIndicator());
    } else if (meta == null) {
      body = const EmptyState(
        icon: Icons.how_to_vote_rounded,
        title: 'Election not found',
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminBar(),
            const SizedBox(height: 10),

            // Status indicator for the loaded document.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppTheme.red.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  const Text('Current status: ',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMuted)),
                  StatusBadge(meta.status),
                ],
              ),
            ),

            // Archived elections are frozen — read-only, no save path.
            if (archived)
              const NoticeBox(
                icon: Icons.lock_outline_rounded,
                message:
                    'This election is archived and read-only. Restore it from the Election Archive before editing.',
              ),

            // ── Core fields ───────────────────────────────────────
            TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
                controller: _allPositionsCtrl,
                decoration:
                    const InputDecoration(labelText: 'All Positions Label')),

            // ── Notice ────────────────────────────────────────────
            const SectionLabel('Notice'),
            TextField(
                controller: _noticeTitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Notice Title')),
            const SizedBox(height: 12),
            TextField(
                controller: _noticeBodyCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Notice Body', alignLabelWithHint: true)),

            // ── About ─────────────────────────────────────────────
            const SectionLabel('About'),
            TextField(
                controller: _aboutTitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'About Title')),
            const SizedBox(height: 12),
            TextField(
                controller: _aboutBodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'About Body', alignLabelWithHint: true)),

            // ── Timeline ──────────────────────────────────────────
            const SectionLabel('Timeline'),
            TextField(
                controller: _timelineTitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Timeline Title')),
            const SizedBox(height: 12),
            TextField(
                controller: _upcomingCtrl,
                decoration:
                    const InputDecoration(labelText: 'Upcoming Label')),
            const SizedBox(height: 12),
            for (final row in _timelineRows)
              _TimelineRowEditor(
                row: row,
                onRemove: () => setState(() {
                  row.dispose();
                  _timelineRows.remove(row);
                }),
              ),
            OutlineBtn(
              label: 'Add Timeline Entry',
              onPressed: () => setState(() => _timelineRows.add(
                  _TimelineRowCtrls(
                      date: TextEditingController(),
                      description: TextEditingController()))),
            ),

            // ── Positions ─────────────────────────────────────────
            const SectionLabel('Positions'),
            TextField(
                controller: _positionsTitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Positions Title')),
            const SizedBox(height: 12),
            for (final c in _positionCtrls)
              _TextRowEditor(
                controller: c,
                label: 'Position',
                onRemove: () => setState(() {
                  c.dispose();
                  _positionCtrls.remove(c);
                }),
              ),
            OutlineBtn(
              label: 'Add Position',
              onPressed: () => setState(
                  () => _positionCtrls.add(TextEditingController())),
            ),

            // ── How to Vote ───────────────────────────────────────
            const SectionLabel('How to Vote'),
            TextField(
                controller: _howToVoteTitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'How to Vote Title')),
            const SizedBox(height: 12),
            for (final c in _stepCtrls)
              _TextRowEditor(
                controller: c,
                label: 'Step',
                onRemove: () => setState(() {
                  c.dispose();
                  _stepCtrls.remove(c);
                }),
              ),
            OutlineBtn(
              label: 'Add Step',
              onPressed: () =>
                  setState(() => _stepCtrls.add(TextEditingController())),
            ),

            // ── Polling ───────────────────────────────────────────
            const SectionLabel('Polling'),
            TextField(
                controller: _locationCtrl,
                decoration:
                    const InputDecoration(labelText: 'Polling Location')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _dateCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Polling Date'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _timeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Polling Time'))),
            ]),
            const SizedBox(height: 18),

            // ── Save ──────────────────────────────────────────────
            if (!archived) GradientButton(label: 'Save Changes', onPressed: _save),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _appBar('Election Editor', context),
      body: body,
    );
  }
}

/// One simple list row: a text field plus a remove icon, used by the
/// positions and vote-steps editors.
class _TextRowEditor extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onRemove;

  const _TextRowEditor({
    required this.controller,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
              controller: controller,
              decoration: InputDecoration(labelText: label)),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline,
              size: 20, color: AppTheme.danger),
          tooltip: 'Remove',
          onPressed: onRemove,
        ),
      ],
    );
  }
}

/// One editable timeline row: date + description text fields and a tone
/// dropdown, wrapped in a card so each entry reads as a unit.
class _TimelineRowEditor extends StatelessWidget {
  final _TimelineRowCtrls row;
  final VoidCallback onRemove;

  const _TimelineRowEditor({required this.row, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.creamLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                    controller: row.date,
                    decoration: const InputDecoration(labelText: 'Date')),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    size: 20, color: AppTheme.danger),
                tooltip: 'Remove entry',
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
              controller: row.description,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Description', alignLabelWithHint: true)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: row.tone,
            decoration: const InputDecoration(labelText: 'Tone'),
            items: ['accent', 'current', 'muted']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (val) => row.tone = val ?? row.tone,
          ),
        ],
      ),
    );
  }
}

// ── Helpers (replicated from events_screens.dart) ─────────────────
void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx)
    .showSnackBar(SnackBar(
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => ctx.pop()),
    );
