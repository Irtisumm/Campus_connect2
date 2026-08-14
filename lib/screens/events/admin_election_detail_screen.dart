import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

// ── Screen: Admin Election Detail ─────────────────────────────────
/// Read-only admin view of a single election configuration document.
///
/// Renders every field the student screen renders (notice, about, timeline,
/// positions, how-to-vote, polling) plus an audit section once the election
/// has been archived. Active elections expose an Edit action that routes into
/// [AdminElectionEditorScreen]; archived elections are view-only.
class AdminElectionDetailScreen extends StatelessWidget {
  final String id;
  const AdminElectionDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return StreamBuilder<ElectionMeta?>(
          stream: appState.watchElectionMeta(id),
          builder: (context, snap) {
            // ── Error state ───────────────────────────────────────
            if (snap.hasError) {
              return Scaffold(
                appBar: _appBar('Election Details', context),
                body: const EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load election',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }

            final meta = snap.data;

            // ── Loading state ─────────────────────────────────────
            if (snap.connectionState == ConnectionState.waiting &&
                meta == null) {
              return Scaffold(
                appBar: _appBar('Election Details', context),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            // ── Missing document ──────────────────────────────────
            if (meta == null) {
              return Scaffold(
                appBar: _appBar('Election Details', context),
                body: const EmptyState(
                  icon: Icons.how_to_vote_rounded,
                  title: 'Election not found',
                ),
              );
            }

            // ── Loaded election ───────────────────────────────────
            return Scaffold(
              appBar: _appBar(
                'Election Details',
                context,
                actions: [
                  // Archived elections are frozen — no edit entry point.
                  if (!meta.isArchived)
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: Colors.white),
                      tooltip: 'Edit election',
                      onPressed: () => context
                          .push('/admin/events/elections/editor/${meta.id}'),
                    ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminBar(),
                    const SizedBox(height: 10),
                    StatusBadge(meta.status),
                    const SizedBox(height: 8),
                    Text(meta.title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            height: 1.25)),

                    // ── Notice ─────────────────────────────────────
                    const SectionLabel('Notice'),
                    NoticeBox(
                      icon: Icons.campaign_rounded,
                      message: meta.noticeTitle.isEmpty
                          ? meta.noticeBody
                          : '${meta.noticeTitle}\n${meta.noticeBody}',
                    ),

                    // ── About ──────────────────────────────────────
                    SectionLabel(
                        meta.aboutTitle.isEmpty ? 'About' : meta.aboutTitle),
                    if (meta.aboutBody.isEmpty)
                      const Text('No description yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted))
                    else
                      Text(meta.aboutBody,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.5)),

                    // ── Timeline ───────────────────────────────────
                    SectionLabel(meta.timelineTitle.isEmpty
                        ? 'Timeline'
                        : meta.timelineTitle),
                    if (meta.timeline.isEmpty)
                      const Text('No timeline entries yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted))
                    else
                      for (final entry in meta.timeline)
                        _TimelineRow(entry: entry),

                    // ── Positions ──────────────────────────────────
                    if (meta.positions.isNotEmpty) ...[
                      SectionLabel(meta.positionsTitle.isEmpty
                          ? 'Positions'
                          : meta.positionsTitle),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final position in meta.positions)
                            Chip(label: Text(position)),
                        ],
                      ),
                    ],

                    // ── How to Vote ────────────────────────────────
                    SectionLabel(meta.howToVoteTitle.isEmpty
                        ? 'How to Vote'
                        : meta.howToVoteTitle),
                    if (meta.voteSteps.isEmpty)
                      const Text('No vote steps yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted))
                    else
                      for (var i = 0; i < meta.voteSteps.length; i++)
                        _VoteStepRow(number: i + 1, text: meta.voteSteps[i]),

                    // ── Polling ────────────────────────────────────
                    const SectionLabel('Polling'),
                    InfoRow(label: 'Location', value: meta.pollingLocation),
                    InfoRow(label: 'Date', value: meta.pollingDate),
                    InfoRow(label: 'Time', value: meta.pollingTime),

                    // ── Archive audit trail ────────────────────────
                    if (meta.isArchived) ...[
                      const SectionLabel('Archive'),
                      InfoRow(
                          label: 'Archived on',
                          value: meta.archivedAt ?? '—'),
                      InfoRow(
                          label: 'Archived by',
                          value: meta.archivedBy ?? '—'),
                      InfoRow(
                          label: 'Previous status',
                          value: meta.previousStatus ?? '—'),
                    ],
                    const SizedBox(height: 20),
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

/// One timeline entry: date in the tone colour, description in secondary ink.
///
/// The tone → colour mapping mirrors the student elections screen
/// (`election_info_screen.dart`), translated onto the admin AppTheme palette:
/// `current` = brand red, `accent` = light red, anything else = muted.
class _TimelineRow extends StatelessWidget {
  final ElectionTimelineEntry entry;
  const _TimelineRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.tone) {
      'current' => AppTheme.red,
      'accent' => AppTheme.redLight,
      _ => AppTheme.textMuted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(entry.date,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(entry.description,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// One numbered how-to-vote step.
class _VoteStepRow extends StatelessWidget {
  final int number;
  final String text;
  const _VoteStepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$number',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers (replicated from events_screens.dart) ─────────────────
AppBar _appBar(String t, BuildContext ctx,
        {List<Widget> actions = const []}) =>
    AppBar(
      title: Text(t),
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
      leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => ctx.pop()),
      actions: actions,
    );
