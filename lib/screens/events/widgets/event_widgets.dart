// ── Events design system ─────────────────────────────────────────
// Presentation-only building blocks for the Events module. Nothing here
// talks to Firestore, AppState or go_router: every widget takes plain data
// and hands interactions back through callbacks, so the same card can be
// dropped into the hub, a list screen or a dialog without dragging a data
// dependency with it.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

// ── Tokens ───────────────────────────────────────────────────────

/// The hub sits on a near-white neutral rather than the app's cream so the
/// white cards read as floating rather than flush. Kept in one place so the
/// whole module shifts together.
const Color kEventsSurface = Color(0xFFF6F7F9);

const double kRadiusCard = 24;
const double kRadiusInner = 18;
const double kRadiusPill = 999;

/// The statuses a host may delete their own submission in. Mirrors the
/// Firestore rules exactly (`firestore.rules` → `events` delete rule): a
/// published event is retired by marking it 'Completed', not by deletion, so
/// the delete affordance is never shown for it.
const Set<String> kDeleteableSubmissionStatuses = {
  'Pending',
  'Under Review',
  'Needs Revision',
  'Rejected',
};

/// Soft, wide, low-opacity — a floating card, not a boxed one.
List<BoxShadow> kSoftShadow(
        {double y = 8, double blur = 24, double alpha = 0.07}) =>
    [
      BoxShadow(
        color: const Color(0xFF2B3A4A).withValues(alpha: alpha),
        blurRadius: blur,
        offset: Offset(0, y),
      ),
    ];

/// One event status → one colour, everywhere in the module. Both the mock
/// vocabulary ('Published', 'Under Review') and the reference's wording
/// ('Approved', 'Draft') resolve here, so a rename upstream cannot leave a
/// badge grey by accident.
Color eventStatusColor(String status) => switch (status) {
      'Published' || 'Approved' => const Color(0xFF17A673),
      'Rejected' => const Color(0xFFE03A3A),
      'Pending' || 'Pending Approval' => const Color(0xFFF08C1A),
      'Needs Revision' || 'Under Review' => const Color(0xFF2F6BFF),
      'Completed' => const Color(0xFF6B7A88),
      _ => AppTheme.textMuted,
    };

/// Category → icon + colour. Unknown categories fall back to the brand red
/// rather than throwing, because `category` is a free-text Firestore field.
({IconData icon, Color color}) eventCategoryStyle(String category) =>
    switch (category) {
      'Academic' => (
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF2F6BFF)
        ),
      'Sport' || 'Sports' => (
          icon: Icons.sports_soccer_rounded,
          color: const Color(0xFF17A673)
        ),
      'Club' => (icon: Icons.groups_rounded, color: const Color(0xFF7C4DFF)),
      'Workshop' => (
          icon: Icons.handyman_rounded,
          color: const Color(0xFF00A0B0)
        ),
      'Competition' => (
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFFF08C1A)
        ),
      'Seminar' => (
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF5C6BC0)
        ),
      'Career' => (icon: Icons.work_rounded, color: const Color(0xFF8D6E63)),
      'Community' => (
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFFEC407A)
        ),
      _ => (icon: Icons.local_activity_rounded, color: AppTheme.red),
    };

/// The category list shown as filter chips. 'All' is not a category — it is
/// the absence of a filter, handled by the caller.
const List<String> kEventCategories = [
  'All',
  'Academic',
  'Sports',
  'Club',
  'Workshop',
  'Competition',
  'Seminar',
  'Career',
  'Community',
  'General',
];

// ── Press feedback ───────────────────────────────────────────────

/// Scales its child down slightly while held. Used instead of a bare
/// GestureDetector so every tappable surface in the module answers back.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PressableScale(
      {super.key, required this.child, this.onTap, this.scale = 0.97});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── Quick actions ────────────────────────────────────────────────

class EventQuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> iconGradient;
  final Color tint;
  final VoidCallback onTap;

  const EventQuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconGradient,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Stacked layout: icon on top, text below. Three cards share the
    // screen, so at 320dp each gets ~96dp wide — too narrow for a
    // side-by-side Row. Equal 12px padding on all sides, and the icon
    // is vertically centered with the text block via CrossAxisAlignment.center
    // on a Column so the composition never feels top-heavy.
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, tint.withValues(alpha: 0.10)],
          ),
          borderRadius: BorderRadius.circular(kRadiusCard),
          boxShadow: kSoftShadow(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon container — vertically centered with text block
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: iconGradient),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: iconGradient.last.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 10),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.2,
                )),
            const SizedBox(height: 4),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Category chips ───────────────────────────────────────────────

class EventCategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  const EventCategoryChips(
      {super.key, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kEventCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final cat = kEventCategories[i];
          final isSel = cat == selected;
          final style = cat == 'All'
              ? (icon: Icons.grid_view_rounded, color: AppTheme.red)
              : eventCategoryStyle(cat);
          return PressableScale(
            onTap: () => onSelected(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isSel ? AppTheme.primaryGradient : null,
                color: isSel ? null : Colors.white,
                borderRadius: BorderRadius.circular(kRadiusPill),
                border: Border.all(
                  color: isSel ? Colors.transparent : const Color(0xFFE3E7EC),
                ),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                            color: AppTheme.red.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon,
                      size: 16, color: isSel ? Colors.white : style.color),
                  const SizedBox(width: 6),
                  Text(cat,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : AppTheme.textSecondary,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Category artwork ─────────────────────────────────────────────

/// Displays the event's cover image when [coverImageUrl] is non-null and
/// non-empty; otherwise falls back to the generated category-gradient
/// placeholder with the category icon watermarked. Deterministic, so the
/// same event always looks the same when no image is set.
class EventCover extends StatelessWidget {
  final String category;
  final BorderRadius radius;
  final double iconSize;
  final Widget? overlay;

  /// Optional Firebase Storage download URL for the event's cover image.
  /// When `null` or empty, the generated gradient placeholder is shown.
  final String? coverImageUrl;

  /// How the cover image should fit inside its box. Defaults to
  /// [BoxFit.cover] (used by event feed cards). Submission thumbnails pass
  /// [BoxFit.contain] so the whole image is visible without aggressive
  /// cropping.
  final BoxFit fit;

  const EventCover({
    super.key,
    required this.category,
    required this.radius,
    this.iconSize = 46,
    this.overlay,
    this.coverImageUrl,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    // If a cover image URL is available, show it with a loading placeholder.
    if (coverImageUrl != null && coverImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          // Neutral backdrop so a contained (non-cover) image doesn't sit
          // on a transparent/white seam — keeps the thumbnail polished.
          color: fit == BoxFit.contain
              ? const Color(0xFFF0F2F5)
              : Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                coverImageUrl!,
                fit: fit,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _gradientPlaceholder();
                },
                errorBuilder: (context, error, stackTrace) =>
                    _gradientPlaceholder(),
              ),
              if (overlay != null) overlay!,
            ],
          ),
        ),
      );
    }

    // No cover image — show the generated gradient placeholder.
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _gradientPlaceholder(),
          if (overlay != null) overlay!,
        ],
      ),
    );
  }

  /// The category-gradient placeholder with watermarked icon.
  Widget _gradientPlaceholder() {
    final style = eventCategoryStyle(category);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                style.color.withValues(alpha: 0.92),
                style.color.withValues(alpha: 0.62),
              ],
            ),
          ),
        ),
        Positioned(
          right: -12,
          bottom: -12,
          child: Icon(style.icon,
              size: iconSize + 34, color: Colors.white.withValues(alpha: 0.18)),
        ),
        Center(
          child: Icon(style.icon,
              size: iconSize, color: Colors.white.withValues(alpha: 0.92)),
        ),
      ],
    );
  }
}

// ── My Submissions ───────────────────────────────────────────────

class EventSubmissionCard extends StatelessWidget {
  final double width;
  final String title;
  final String category;
  final String status;
  final String dateLabel;
  final String? coverImageUrl;
  final VoidCallback onTap;

  /// Optional destructive action (delete). When provided, a small delete
  /// button is overlaid on the cover. While [deleting] is true it renders a
  /// spinner and ignores taps, so a double tap cannot double-fire the write.
  final VoidCallback? onDelete;
  final bool deleting;

  const EventSubmissionCard({
    super.key,
    this.width = 116,
    required this.title,
    required this.category,
    required this.status,
    required this.dateLabel,
    required this.onTap,
    this.coverImageUrl,
    this.onDelete,
    this.deleting = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = eventStatusColor(status);
    final compact = width < 100;
    return PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square thumbnail — width ≈ height. BoxFit.contain keeps the
            // whole image visible without aggressive cropping; a soft
            // neutral background fills any letterboxing so it still looks
            // polished for non-square source images.
            SizedBox(
              height: width,
              width: width,
              child: EventCover(
                category: category,
                radius: BorderRadius.circular(compact ? 12 : kRadiusInner),
                iconSize: compact ? 22 : 26,
                coverImageUrl: coverImageUrl,
                fit: BoxFit.contain,
                overlay: Stack(
                  children: [
                    // Status pill — unchanged from the original design.
                    Positioned(
                      left: 5,
                      right: 5,
                      bottom: 5,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 5 : 6,
                            vertical: compact ? 2.5 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(kRadiusPill),
                            boxShadow: kSoftShadow(y: 2, blur: 6, alpha: 0.15),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: compact ? 4.5 : 5,
                                height: compact ? 4.5 : 5,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: compact ? 8.5 : 9,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Small, non-dominant delete affordance. Rendered only when
                    // the caller wires an onDelete (the host's own non-published
                    // submissions) and never changes the card size.
                    if (onDelete != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: deleting ? null : onDelete,
                          child: Container(
                            width: compact ? 20 : 22,
                            height: compact ? 20 : 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow:
                                  kSoftShadow(y: 2, blur: 6, alpha: 0.18),
                            ),
                            child: deleting
                                ? const Padding(
                                    padding: EdgeInsets.all(5),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: AppTheme.red,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline_rounded,
                                    size: 14, color: AppTheme.danger),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: compact ? 11.5 : 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9.5 : 10,
                  color: AppTheme.textMuted,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Event card ───────────────────────────────────────────────────

/// The primary list card: large cover on the left, details on the right.
class PremiumEventCard extends StatelessWidget {
  final String title;
  final String category;
  final String dateLabel;
  final String time;
  final String location;
  final String organizer;
  final int attendees;
  final int capacity;
  final bool isPaid;
  final double price;
  final bool isCompleted;
  final String? joinStatus;
  final String? coverImageUrl;
  final VoidCallback onTap;

  const PremiumEventCard({
    super.key,
    required this.title,
    required this.category,
    required this.dateLabel,
    required this.time,
    required this.location,
    required this.organizer,
    required this.attendees,
    required this.capacity,
    required this.isPaid,
    required this.price,
    required this.onTap,
    this.isCompleted = false,
    this.joinStatus,
    this.coverImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - 32).clamp(300.0, 560.0).toDouble();
    final contentWidth = cardWidth - 24;
    final coverWidth = (contentWidth * 0.35).clamp(108.0, 138.0).toDouble();
    final coverHeight = (coverWidth * 1.06).clamp(116.0, 146.0).toDouble();

    return PressableScale(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusCard),
          boxShadow: kSoftShadow(),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kRadiusCard),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Square cover image on the left — no category accent rail.
                SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: EventCover(
                    category: category,
                    radius: BorderRadius.circular(18),
                    coverImageUrl: coverImageUrl,
                    overlay: Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(kRadiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_alt_rounded,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              capacity > 0
                                  ? '$attendees / $capacity'
                                  : '$attendees',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                _CategoryBadge(category: category),
                                if (isCompleted)
                                  _MiniBadge(
                                    label: 'Completed',
                                    color: eventStatusColor('Completed'),
                                  )
                                else if (isPaid)
                                  _MiniBadge(
                                    label: 'RM ${price.toStringAsFixed(0)}',
                                    color: const Color(0xFFF08C1A),
                                  )
                                else
                                  const _MiniBadge(
                                      label: 'Free', color: Color(0xFF17A673)),
                                if (joinStatus != null)
                                  _MiniBadge(
                                    label: joinStatus == 'Approved'
                                        ? 'Joined'
                                        : joinStatus!,
                                    color: eventStatusColor(joinStatus!),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const _BookmarkAffordance(),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      _MetaRow(
                          icon: Icons.calendar_today_rounded, text: dateLabel),
                      _MetaRow(icon: Icons.schedule_rounded, text: time),
                      _MetaRow(icon: Icons.location_on_rounded, text: location),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(kRadiusPill),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('View Details',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.red)),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: AppTheme.red),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final style = eventCategoryStyle(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kRadiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: style.color)),
          ),
        ],
      ),
    );
  }
}

class _BookmarkAffordance extends StatelessWidget {
  const _BookmarkAffordance();

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E9EF)),
          boxShadow: kSoftShadow(y: 2, blur: 8, alpha: 0.04),
        ),
        child: const Icon(
          Icons.bookmark_border_rounded,
          size: 19,
          color: AppTheme.textPrimary,
        ),
      );
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(kRadiusPill),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
      );
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: AppTheme.textSecondary)),
            ),
          ],
        ),
      );
}

// ── Section header ───────────────────────────────────────────────

class EventsSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? leading;
  final bool compact;

  const EventsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.leading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          Icon(
            leading,
            size: compact ? 17 : 18,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 15.5 : 19,
                fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
                letterSpacing: compact ? 0 : -0.4,
                color: AppTheme.textPrimary,
              )),
        ),
        if (actionLabel != null)
          PressableScale(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.red)),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppTheme.red),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Bottom CTA ───────────────────────────────────────────────────

class CreateEventCta extends StatelessWidget {
  final VoidCallback onTap;
  const CreateEventCta({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.red.withValues(alpha: 0.10),
            AppTheme.redLight.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.14)),
      ),
      // Wraps to a column on narrow screens so the button never has to
      // fight the text for horizontal room.
      child: LayoutBuilder(
        builder: (ctx, c) {
          final stacked = c.maxWidth < 360;
          const text = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Can't find an event you like?",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              SizedBox(height: 3),
              Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Be the change! ',
                        style: TextStyle(color: AppTheme.textMuted)),
                    TextSpan(
                        text: 'Create your own event',
                        style: TextStyle(
                            color: AppTheme.red, fontWeight: FontWeight.w700)),
                  ]),
                  style: TextStyle(fontSize: 12.5)),
            ],
          );
          final button = PressableScale(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(kRadiusPill),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.red.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 7),
                  Text('Create Event',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ],
              ),
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: button),
              ],
            );
          }
          return Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: kSoftShadow(y: 3, blur: 8, alpha: 0.08),
                ),
                child: const Icon(Icons.event_available_rounded,
                    color: AppTheme.red, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(child: text),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

// ── Shared empty / error states ──────────────────────────────────

/// Both the "nothing here yet" and "couldn't load" cases, so the hub does
/// not grow two near-identical inline widgets.
class EventsPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EventsPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: EmptyState(icon: icon, title: title, subtitle: subtitle),
      ).animate().fadeIn(duration: 250.ms);
}
