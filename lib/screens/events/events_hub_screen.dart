// ── Screen 22: Events Hub ────────────────────────────────────────
// Presentation rewrite of the events landing screen. Every stream, route
// and status rule is carried over from the previous implementation
// unchanged — only the widgets that render them are new.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/event_widgets.dart';

void _toast(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        duration: const Duration(seconds: 2),
      ),
    );

class EventsHubScreen extends StatefulWidget {
  const EventsHubScreen({super.key});

  @override
  State<EventsHubScreen> createState() => _EventsHubScreenState();
}

class _EventsHubScreenState extends State<EventsHubScreen> {
  // Filtering is view state, so it lives here rather than in AppState —
  // nothing downstream needs to know which chip is lit.
  String _category = 'All';
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The chip vocabulary says 'Sports'; older event records say 'Sport'.
  /// Both must match the same chip or those events silently disappear
  /// behind the filter.
  bool _matches(Event e) {
    if (_category == 'All') return true;
    if (_category == 'Sports')
      return e.category == 'Sport' || e.category == 'Sports';
    return e.category == _category;
  }

  void _resetFilter() {
    setState(() => _category = 'All');
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Scaffold(
          backgroundColor: kEventsSurface,
          body: StreamBuilder<List<Event>>(
            stream: appState.watchPublishedEvents(),
            builder: (context, pubSnap) {
              return StreamBuilder<List<Event>>(
                stream: appState.watchMyEvents(),
                builder: (context, mineSnap) {
                  return StreamBuilder<List<EventJoining>>(
                    stream: appState.watchMyJoinings(),
                    builder: (context, joinSnap) {
                      final all = pubSnap.data ?? const <Event>[];
                      final events = all.where(_matches).toList();
                      final mine = mineSnap.data ?? const <Event>[];

                      // Which events this user has already engaged with,
                      // so the card can say so without a second lookup.
                      final joinedIds = {
                        for (final j
                            in (joinSnap.data ?? const <EventJoining>[]))
                          j.eventId: j.status,
                      };

                      final loading =
                          pubSnap.connectionState == ConnectionState.waiting &&
                              !pubSnap.hasData;

                      return CustomScrollView(
                        controller: _scroll,
                        slivers: [
                          // No hero here: the app shell already renders the
                          // branded header on every tab, and a second copy
                          // was what stacked two headers on the screen.
                          SliverToBoxAdapter(
                            child: const _QuickActions()
                                .animate()
                                .fadeIn(duration: 300.ms)
                                .slideY(begin: 0.12, curve: Curves.easeOut),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 10),
                              child: EventsSectionHeader(
                                title: 'Upcoming Events',
                                actionLabel: 'See all events',
                                onAction: _resetFilter,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: EventCategoryChips(
                                selected: _category,
                                onSelected: (c) =>
                                    setState(() => _category = c),
                              ),
                            ),
                          ),
                          if (mine.isNotEmpty)
                            SliverToBoxAdapter(
                              child: _MySubmissions(events: mine),
                            ),
                          _EventsSliver(
                            events: events,
                            loading: loading,
                            hasError: pubSnap.hasError,
                            filtered: _category != 'All',
                            joinedIds: joinedIds,
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                              child: CreateEventCta(
                                onTap: () => context.push('/events/create'),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ── Quick actions ────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    // Three equal columns sized by the viewport. Expanded divides the width
    // so the third card can no longer run off-screen, and IntrinsicHeight
    // levels them from content instead of a fixed height — the fixed height
    // was what produced the 5px bottom overflow.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EventQuickAction(
                icon: Icons.add_rounded,
                title: 'Create Event',
                subtitle: 'Start a new event',
                iconGradient: const [AppTheme.redLight, AppTheme.red],
                tint: AppTheme.red,
                onTap: () => context.push('/events/create'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EventQuickAction(
                icon: Icons.calendar_month_rounded,
                title: 'My Events',
                subtitle: 'View your events',
                iconGradient: const [Color(0xFF9B7BFF), Color(0xFF6C3DF4)],
                tint: const Color(0xFF7C4DFF),
                onTap: () => context.push('/events/my-events'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EventQuickAction(
                icon: Icons.how_to_vote_rounded,
                title: 'Elections',
                subtitle: 'Campus elections',
                iconGradient: const [Color(0xFFFFB84D), Color(0xFFF08C1A)],
                tint: const Color(0xFFF08C1A),
                onTap: () => context.push('/events/elections'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── My Submissions ───────────────────────────────────────────────

class _MySubmissions extends StatefulWidget {
  final List<Event> events;
  const _MySubmissions({required this.events});

  @override
  State<_MySubmissions> createState() => _MySubmissionsState();
}

class _MySubmissionsState extends State<_MySubmissions> {
  /// Events currently being deleted. Guards against double taps: while an id
  /// is in this set its card shows a spinner and its delete button ignores
  /// taps, so the confirm dialog can never be opened twice for one event.
  final Set<String> _deletingIds = <String>{};

  bool _isDeleteable(Event ev) =>
      kDeleteableSubmissionStatuses.contains(ev.status);

  /// Opens the confirmation dialog. The event is removed only AFTER the
  /// Firestore write succeeds — the live `watchMyEvents` stream then re-emits
  /// and the card disappears on its own, so no manual list mutation is needed.
  void _confirmDelete(Event ev) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text(
          'This will permanently delete this event. This action cannot be undone.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => _delete(ev, dialogCtx),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Event ev, BuildContext dialogCtx) async {
    // Close the dialog immediately; the card's spinner covers the loading
    // state and the id guard blocks any further taps on this event.
    Navigator.of(dialogCtx).pop();
    if (!_deletingIds.add(ev.id))
      return; // already deleting — ignore double fire
    setState(() {}); // show the spinner
    final ok = await context.read<AppState>().deleteEvent(ev.id);
    if (!mounted) return;
    setState(() => _deletingIds.remove(ev.id));
    _toast(
        context,
        ok
            ? 'Event deleted successfully.'
            : 'Unable to delete event. Please try again.');
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusCard),
        boxShadow: kSoftShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          EventsSectionHeader(
            title: 'My Submissions',
            leading: Icons.person_outline_rounded,
            actionLabel: 'View all',
            compact: true,
            onAction: () => context.push('/events/my-events'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            // Compact height: square thumbnail + title + date.
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final ev = events[i];
                return EventSubmissionCard(
                  width: 76,
                  title: ev.title,
                  category: ev.category,
                  status: ev.status,
                  dateLabel: fmtDate(ev.date),
                  coverImageUrl: ev.coverImageUrl,
                  // Unchanged from the previous hub: a live event opens the
                  // management console, anything still in the pipeline opens
                  // its submission record.
                  onTap: () => ev.status == 'Published'
                      ? context.push('/events/manage/${ev.id}')
                      : context.push('/events/my-events/${ev.id}'),
                  // A published or completed event is retired, not deleted —
                  // the rules forbid it, so the affordance is only wired for
                  // statuses the host may actually delete.
                  onDelete: _isDeleteable(ev) && !_deletingIds.contains(ev.id)
                      ? () => _confirmDelete(ev)
                      : null,
                  deleting: _deletingIds.contains(ev.id),
                ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.1);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event list ───────────────────────────────────────────────────

class _EventsSliver extends StatelessWidget {
  final List<Event> events;
  final bool loading;
  final bool hasError;
  final bool filtered;
  final Map<String, String> joinedIds;

  const _EventsSliver({
    required this.events,
    required this.loading,
    required this.hasError,
    required this.filtered,
    required this.joinedIds,
  });

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const SliverToBoxAdapter(
        child: EventsPlaceholder(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load events',
          subtitle: 'Check your connection and pull to try again.',
        ),
      );
    }
    if (loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: CircularProgressIndicator(
                color: AppTheme.red, strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (events.isEmpty) {
      return SliverToBoxAdapter(
        child: EventsPlaceholder(
          icon: Icons.event_busy_rounded,
          title: filtered ? 'No events in this category' : 'No upcoming events',
          subtitle: filtered
              ? 'Try another category, or create the first one yourself.'
              : 'Nothing scheduled yet. Be the first to host something.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      sliver: SliverList.builder(
        itemCount: events.length,
        itemBuilder: (ctx, i) {
          final ev = events[i];
          return PremiumEventCard(
            title: ev.title,
            category: ev.category,
            dateLabel: fmtDate(ev.date),
            time: ev.time,
            location: ev.location,
            organizer: ev.organizer,
            attendees: ev.attendeeIds.length,
            capacity: ev.maxParticipants,
            isPaid: ev.isPaid,
            price: ev.price,
            isCompleted: ev.status == 'Completed',
            joinStatus: joinedIds[ev.id],
            coverImageUrl: ev.coverImageUrl,
            onTap: () => context.push('/events/detail/${ev.id}'),
          )
              // Staggered, but capped: past the first handful the delay is
              // flat so a long list does not take a second to settle.
              .animate()
              .fadeIn(delay: (i < 6 ? i * 70 : 420).ms, duration: 280.ms)
              .slideY(begin: 0.1, curve: Curves.easeOut);
        },
      ),
    );
  }
}
