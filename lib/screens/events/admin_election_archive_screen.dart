import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

// ── Screen: Admin Election Archive ────────────────────────────────
/// Read-only archive of retired election configurations.
///
/// Archived elections are never hard-deleted — this screen lets the admin
/// review them (via the detail screen) and restore one back to its
/// pre-archive status. Restoring flips the document's status, so the live
/// stream re-emits and the item leaves this list automatically.
class AdminElectionArchiveScreen extends StatelessWidget {
  const AdminElectionArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return StreamBuilder<List<ElectionMeta>>(
          stream: appState.watchAllElectionMeta(),
          builder: (context, snap) {
            // ── Error state ───────────────────────────────────────
            if (snap.hasError) {
              return Scaffold(
                appBar: _appBar('Election Archive', context),
                body: const EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load archive',
                  subtitle: 'Please check your connection and try again.',
                ),
              );
            }

            final metas = snap.data ?? const <ElectionMeta>[];
            final archived = metas.where((m) => m.isArchived).toList();

            return Scaffold(
              appBar: _appBar('Election Archive', context),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminBar(),
                    const SizedBox(height: 10),

                    // ── Loading state ─────────────────────────────
                    if (snap.connectionState == ConnectionState.waiting &&
                        metas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )

                    // ── Empty state ───────────────────────────────
                    else if (archived.isEmpty)
                      const EmptyState(
                        icon: Icons.inventory_2_rounded,
                        title: 'No archived elections',
                        subtitle: 'Archived elections will appear here.',
                      )

                    // ── Archived elections ────────────────────────
                    else
                      ...archived.map(
                          (meta) => _ArchivedElectionCard(meta: meta, appState: appState)),
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

/// One archived election: identity, snippet, audit metadata and the
/// view/restore actions.
class _ArchivedElectionCard extends StatelessWidget {
  final ElectionMeta meta;
  final AppState appState;
  const _ArchivedElectionCard({required this.meta, required this.appState});

  @override
  Widget build(BuildContext context) {
    final source = meta.aboutBody.isNotEmpty ? meta.aboutBody : meta.noticeBody;
    final snippet = source.length <= 120
        ? source
        : '${source.substring(0, 120).trimRight()}…';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(meta.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                ),
                const SizedBox(width: 8),
                const StatusBadge('Archived'),
                if (meta.previousStatus?.isNotEmpty == true) ...[
                  const SizedBox(width: 6),
                  StatusBadge(meta.previousStatus!),
                ],
              ],
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(snippet,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.45)),
            ],
            const SizedBox(height: 10),
            _ArchiveMetaRow(label: 'Created', value: meta.createdAt ?? '—'),
            _ArchiveMetaRow(label: 'Archived', value: meta.archivedAt ?? '—'),
            _ArchiveMetaRow(
                label: 'Archived by', value: meta.archivedBy ?? '—'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlineBtn(
                    label: 'View',
                    onPressed: () => context.push(
                        '/admin/events/elections/detail/${meta.id}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: 'Restore',
                    onPressed: () async {
                      final ok = await appState.restoreElectionMeta(
                        meta.id,
                        previousStatus: meta.previousStatus ?? 'Pending',
                      );
                      if (!context.mounted) return;
                      _toast(
                          context, ok ? 'Election restored' : 'Restore failed');
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
}

/// A label + value metadata row inside an archived-election card.
class _ArchiveMetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _ArchiveMetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
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
