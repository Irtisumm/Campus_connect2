import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/mock_data.dart';
import '../../services/data_service.dart';
import '../../theme/luxe.dart';

const _electionInk = Color(0xFF172944);
const _electionMuted = Color(0xFF596273);

const _electionPositions = <String>[
  'President',
  'Vice President',
  'Secretary General',
  'Treasurer',
];

const _timelineEvents = <_TimelineData>[
  _TimelineData(
      '25 Mar 2026', 'Candidate registration closes', _TimelineTone.accent),
  _TimelineData('28–30 Mar 2026', 'Campaigning period', _TimelineTone.accent),
  _TimelineData('1 Apr 2026', 'Polling Day (Block A Foyer, 8am–5pm)',
      _TimelineTone.current),
  _TimelineData('2 Apr 2026', 'Results announced', _TimelineTone.muted),
];

const _voteSteps = <String>[
  'Go to the designated polling station.',
  'Bring your student ID.',
  'Verify your identity.',
  'Cast your ballot at the station.',
  'Follow all official instructions.',
];

/// Temporary presentation data for the information-only elections page.
/// Firebase-backed election data can later be mapped into this shape without
/// changing the widgets below.
const _electionContent = _ElectionContentData(
  allPositionsLabel: 'All Positions',
  noticeTitle: 'This is an information-only page.',
  noticeBody: 'No online voting is conducted here.',
  aboutTitle: 'About the Elections',
  aboutBody:
      'The Student Council Elections are held annually to elect student representatives. Physical ballot casting is at designated polling stations on campus.',
  timelineTitle: 'Timeline',
  upcomingLabel: 'Upcoming',
  positionsTitle: 'Open Positions',
  howToVoteTitle: 'How to Vote',
  pollingLocation: 'Block A Foyer, Main Campus',
  pollingDate: '1 Apr 2026',
  pollingTime: '8:00 AM – 5:00 PM',
  positions: _electionPositions,
  timeline: _timelineEvents,
  voteSteps: _voteSteps,
);

class _ElectionContentData {
  final String allPositionsLabel;
  final String noticeTitle;
  final String noticeBody;
  final String aboutTitle;
  final String aboutBody;
  final String timelineTitle;
  final String upcomingLabel;
  final String positionsTitle;
  final String howToVoteTitle;
  final String pollingLocation;
  final String pollingDate;
  final String pollingTime;
  final List<String> positions;
  final List<_TimelineData> timeline;
  final List<String> voteSteps;

  const _ElectionContentData({
    required this.allPositionsLabel,
    required this.noticeTitle,
    required this.noticeBody,
    required this.aboutTitle,
    required this.aboutBody,
    required this.timelineTitle,
    required this.upcomingLabel,
    required this.positionsTitle,
    required this.howToVoteTitle,
    required this.pollingLocation,
    required this.pollingDate,
    required this.pollingTime,
    required this.positions,
    required this.timeline,
    required this.voteSteps,
  });
}

/// Information-only student election page. Election content remains sourced
/// from the existing app data; this file only owns the presentation layer.
class ElectionsInfoScreen extends StatefulWidget {
  const ElectionsInfoScreen({super.key});

  @override
  State<ElectionsInfoScreen> createState() => _ElectionsInfoScreenState();
}

class _ElectionsInfoScreenState extends State<ElectionsInfoScreen> {
  String _selectedPosition = _electionContent.allPositionsLabel;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFCFB),
        body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Consumer<DataService>(
                        builder: (context, dataService, child) {
                          final candidates = dataService.candidates;
                          final visibleCandidates = _selectedPosition ==
                                  _electionContent.allPositionsLabel
                              ? candidates
                              : candidates
                                  .where((candidate) =>
                                      candidate.position == _selectedPosition)
                                  .toList();

                          return Column(
                            children: [
                              const _InformationOnlyBanner(
                                  data: _electionContent),
                              const SizedBox(height: 12),
                              const _ElectionOverviewCard(
                                  data: _electionContent),
                              const SizedBox(height: 12),
                              _OpenPositionsCard(
                                positions: _electionContent.positions,
                                title: _electionContent.positionsTitle,
                              ),
                              const SizedBox(height: 12),
                              _CandidatesCard(
                                candidates: visibleCandidates,
                                positions: _electionContent.positions,
                                selectedPosition: _selectedPosition,
                                onPositionSelected: (position) => setState(
                                  () => _selectedPosition = position,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const _HowToVoteCard(data: _electionContent),
                              const SizedBox(height: 18),
                            ],
                          );
                        },
                      ),
                    ),
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

class _InformationOnlyBanner extends StatelessWidget {
  final _ElectionContentData data;

  const _InformationOnlyBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.info_rounded, color: Luxe.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.noticeTitle,
                  style: Luxe.title.copyWith(
                      color: const Color(0xFF873517),
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(data.noticeBody,
                    style: Luxe.body.copyWith(
                        color: const Color(0xFF98432B), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Luxe.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined,
                color: Luxe.primary, size: 23),
          ),
        ],
      ),
    );
  }
}

class _ElectionOverviewCard extends StatelessWidget {
  final _ElectionContentData data;

  const _ElectionOverviewCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionIcon(icon: Icons.menu_book_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.aboutTitle,
                        style: Luxe.title.copyWith(
                            color: _electionInk,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(data.aboutBody,
                        style: Luxe.body.copyWith(
                            color: _electionMuted, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Luxe.hairline),
          ),
          _SectionHeading(
            icon: Icons.calendar_month_rounded,
            title: data.timelineTitle,
            trailing:
                _StatusPill(label: data.upcomingLabel, color: Luxe.primary),
          ),
          const SizedBox(height: 10),
          _ElectionTimeline(events: data.timeline),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeading(
      {required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SectionIcon(icon: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: Luxe.title.copyWith(
                  fontSize: 18,
                  color: _electionInk,
                  fontWeight: FontWeight.w800)),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _SectionIcon extends StatelessWidget {
  final IconData icon;

  const _SectionIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Luxe.primary, size: 22),
    );
  }
}

class _ElectionTimeline extends StatelessWidget {
  final List<_TimelineData> events;

  const _ElectionTimeline({required this.events});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 18,
          top: 19,
          bottom: 12,
          child:
              Container(width: 1, color: Luxe.primary.withValues(alpha: 0.16)),
        ),
        Column(
          children: [
            for (final event in events) _TimelineItem(data: event),
          ],
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final _TimelineData data;

  const _TimelineItem({required this.data});

  @override
  Widget build(BuildContext context) {
    final color = switch (data.tone) {
      _TimelineTone.current => Luxe.primary,
      _TimelineTone.accent => Luxe.secondary,
      _TimelineTone.muted => Luxe.inkMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(
                  alpha: data.tone == _TimelineTone.current ? 0.14 : 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.16)),
            ),
            child: Icon(Icons.calendar_today_rounded, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.date,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2),
                  ),
                  const SizedBox(height: 3),
                  Text(data.description,
                      style: Luxe.body.copyWith(
                          color: _electionMuted, fontSize: 13, height: 1.25)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenPositionsCard extends StatelessWidget {
  final List<String> positions;
  final String title;

  const _OpenPositionsCard({required this.positions, required this.title});

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(icon: Icons.groups_rounded, title: title),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 300 ? 4 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: positions.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 86,
                ),
                itemBuilder: (context, index) => _PositionTile(
                  position: positions[index],
                  icon: _positionIcon(positions[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PositionTile extends StatelessWidget {
  final String position;
  final IconData icon;

  const _PositionTile({required this.position, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Luxe.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Luxe.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Luxe.primary, size: 22),
          const SizedBox(height: 4),
          Text(
            position,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Luxe.caption.copyWith(
                color: Luxe.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.16),
          ),
        ],
      ),
    );
  }
}

class _CandidatesCard extends StatelessWidget {
  final List<Candidate> candidates;
  final List<String> positions;
  final String selectedPosition;
  final ValueChanged<String> onPositionSelected;

  const _CandidatesCard({
    required this.candidates,
    required this.positions,
    required this.selectedPosition,
    required this.onPositionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CandidatesHeading(),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 1),
            child: Row(
              children: [
                for (final position in [
                  _electionContent.allPositionsLabel,
                  ...positions
                ]) ...[
                  _FilterChip(
                    label: position,
                    selected: position == selectedPosition,
                    onTap: () => onPositionSelected(position),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (candidates.isEmpty)
            const _CandidateEmptyState()
          else
            for (var index = 0; index < candidates.length; index++) ...[
              _CandidateCard(candidate: candidates[index], index: index),
              if (index != candidates.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.filter_alt_rounded, color: Luxe.primary, size: 14),
        const SizedBox(width: 4),
        Text('Filter by Position',
            style: Luxe.caption
                .copyWith(color: Luxe.primary, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CandidatesHeading extends StatelessWidget {
  const _CandidatesHeading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('Candidates',
              style: Luxe.title.copyWith(
                  color: _electionInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ),
        const _FilterLabel(),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Luxe.primary : Luxe.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Luxe.primary : Luxe.hairline),
            boxShadow:
                selected ? Luxe.lift(tint: Luxe.primary, strength: 0.5) : null,
          ),
          child: Text(
            label,
            style: Luxe.caption.copyWith(
              color: selected ? Colors.white : Luxe.inkSoft,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final Candidate candidate;
  final int index;

  const _CandidateCard({required this.candidate, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Luxe.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Luxe.hairline),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: 0.32),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CandidateAvatar(name: candidate.name, index: index),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name,
                    style: Luxe.title.copyWith(
                        fontSize: 16,
                        color: _electionInk,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(candidate.programme,
                    style: Luxe.caption
                        .copyWith(color: _electionMuted, fontSize: 12)),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Luxe.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Running for: ${candidate.position}',
                    style: Luxe.caption.copyWith(
                        color: Luxe.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  candidate.manifesto,
                  style: Luxe.body.copyWith(
                      color: _electionMuted, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.bookmark_border_rounded,
              color: Color(0xFF687282), size: 20),
        ],
      ),
    );
  }
}

class _CandidateAvatar extends StatelessWidget {
  final String name;
  final int index;

  const _CandidateAvatar({required this.name, required this.index});

  @override
  Widget build(BuildContext context) {
    final names = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = names.length > 1
        ? '${names.first.substring(0, 1)}${names.last.substring(0, 1)}'
        : name.trim().substring(0, 1);
    final colors = [
      const Color(0xFFFFDCE2),
      const Color(0xFFFFE7D2),
      const Color(0xFFE8E0FF),
      const Color(0xFFDDF3EA),
    ];

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: colors[index % colors.length],
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Luxe.primary.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(initials.toUpperCase(),
                  style:
                      Luxe.title.copyWith(color: Luxe.primary, fontSize: 17)),
            ),
          ),
          Positioned(
            left: -3,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Luxe.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateEmptyState extends StatelessWidget {
  const _CandidateEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Luxe.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Luxe.hairline),
      ),
      child: const Column(
        children: [
          Icon(Icons.how_to_vote_outlined, color: Luxe.inkMuted, size: 34),
          SizedBox(height: 10),
          Text('No candidates published yet.', style: Luxe.title),
          SizedBox(height: 4),
          Text(
            'Check back when the election information is updated.',
            textAlign: TextAlign.center,
            style: Luxe.caption,
          ),
        ],
      ),
    );
  }
}

class _HowToVoteCard extends StatelessWidget {
  final _ElectionContentData data;

  const _HowToVoteCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      color: const Color(0xFFFFFAFB),
      borderColor: Luxe.primary.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
              icon: Icons.how_to_vote_rounded, title: data.howToVoteTitle),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 330) {
                return _VerticalVoteSteps(steps: data.voteSteps);
              }
              return _HorizontalVoteSteps(steps: data.voteSteps);
            },
          ),
          const SizedBox(height: 12),
          _VotingDetailsBar(data: data),
        ],
      ),
    );
  }
}

class _HorizontalVoteSteps extends StatelessWidget {
  final List<String> steps;

  const _HorizontalVoteSteps({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(child: _VoteStep(number: index + 1, label: steps[index])),
          if (index != steps.length - 1)
            const SizedBox(
              width: 7,
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: _DashedLine(),
              ),
            ),
        ],
      ],
    );
  }
}

class _VerticalVoteSteps extends StatelessWidget {
  final List<String> steps;

  const _VerticalVoteSteps({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          Padding(
            padding:
                EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepNumber(number: index + 1),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(steps[index],
                        style: Luxe.body.copyWith(fontSize: 12))),
              ],
            ),
          ),
      ],
    );
  }
}

class _VoteStep extends StatelessWidget {
  final int number;
  final String label;

  const _VoteStep({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StepNumber(number: number),
        const SizedBox(height: 8),
        Text(label,
            textAlign: TextAlign.center,
            style: Luxe.caption
                .copyWith(color: _electionMuted, fontSize: 12, height: 1.3)),
      ],
    );
  }
}

class _StepNumber extends StatelessWidget {
  final int number;

  const _StepNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Luxe.secondary.withValues(alpha: 0.88),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Luxe.secondary.withValues(alpha: 0.20),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Center(
        child: Text('$number',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        3,
        (_) => Container(
            width: 2, height: 1, color: Luxe.secondary.withValues(alpha: 0.45)),
      ),
    );
  }
}

class _VotingDetailsBar extends StatelessWidget {
  final _ElectionContentData data;

  const _VotingDetailsBar({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VotingDetail(
                icon: Icons.location_on_rounded, text: data.pollingLocation),
          ),
          Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Luxe.primary.withValues(alpha: 0.18)),
          Expanded(
            child: _VotingDetail(
                icon: Icons.access_time_rounded,
                text: '${data.pollingDate}, ${data.pollingTime}'),
          ),
        ],
      ),
    );
  }
}

class _VotingDetail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _VotingDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Luxe.primary, size: 15),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Luxe.caption
                .copyWith(color: _electionInk, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;

  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Luxe.surface,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? Luxe.hairline),
        boxShadow: Luxe.lift(tint: Luxe.primary, strength: 0.26),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: Luxe.caption
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TimelineData {
  final String date;
  final String description;
  final _TimelineTone tone;

  const _TimelineData(this.date, this.description, this.tone);
}

enum _TimelineTone { accent, current, muted }

IconData _positionIcon(String position) {
  switch (position) {
    case 'President':
      return Icons.workspace_premium_rounded;
    case 'Vice President':
      return Icons.stars_rounded;
    case 'Secretary General':
      return Icons.description_rounded;
    case 'Treasurer':
      return Icons.account_balance_wallet_rounded;
    default:
      return Icons.person_rounded;
  }
}
