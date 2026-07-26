import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

// ── Status Badge ──────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  static const _map = {
    'Active':                 [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Matched - Pending':      [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Closed':                 [Color(0xFF4E6272), Color(0x20607080)],
    'In Progress':            [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Resolved':               [Color(0xFF8B1428), Color(0x20C41E3A)],
    'New':                    [Color(0xFF8B1428), Color(0x18C41E3A)],
    'Triaged':                [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'Assigned':               [Color(0xFF8B1428), Color(0x1AC41E3A)],
    'In Inventory':           [Color(0xFF7A5B00), Color(0x28F8D49B)],
    'Pending Pickup':         [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'Overdue':                [Color(0xFFB03030), Color(0x18D65E5E)],
    'Blocked':                [Color(0xFF4E6272), Color(0x18607080)],
    'Published':              [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Draft':                  [Color(0xFF4E6272), Color(0x15607080)],
    'Under Review':           [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'Available':              [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Confirmed':              [Color(0xFF8B1428), Color(0x20C41E3A)],
    'Pending':                [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'Released':               [Color(0xFF4E6272), Color(0x18607080)],
    'Completed':              [Color(0xFF4E6272), Color(0x15607080)],
    'Approved':               [Color(0xFF2E7D32), Color(0x1A4CAF50)],
    'Rejected':               [Color(0xFFB03030), Color(0x18D65E5E)],
    'Received':               [Color(0xFF2E7D32), Color(0x1A4CAF50)],
    'Archived':               [Color(0xFF4E6272), Color(0x15607080)],
    'Claiming':               [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'In Review':              [Color(0xFF8A5F0A), Color(0x28F8D49B)],
    'Closed - Verified':      [Color(0xFF4E6272), Color(0x18607080)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _map[status] ?? [AppTheme.textMuted, const Color(0x18607080)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: colors[1],
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors[0].withOpacity(0.35)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: colors[0],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: AppTheme.textMuted, letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppTheme.red.withOpacity(0.18), height: 1)),
        ],
      ),
    );
  }
}

// ── Card Row (tappable list item) ────────────────────────────────
class CardRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? extra;
  final String? status;
  final Widget? trailing;
  final VoidCallback? onTap;

  const CardRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.extra,
    this.status,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 3, height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                    if (extra != null) ...[
                      const SizedBox(height: 2),
                      Text(extra!, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (status != null) StatusBadge(status!),
                  if (trailing != null) ...[const SizedBox(height: 4), trailing!],
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info Row ──────────────────────────────────────────────────────
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  final Color? bgColor;
  const StatCard({super.key, required this.value, required this.label, this.valueColor, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor ?? AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.red.withOpacity(0.12)),
        boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: valueColor ?? AppTheme.red, height: 1)),
          const SizedBox(height: 5),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ── Hub Button ────────────────────────────────────────────────────
class HubButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isPrimary;
  final bool isAmber;
  final Color? iconColor;
  final VoidCallback? onTap;

  const HubButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.isPrimary = false,
    this.isAmber = false,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isColored = isPrimary || isAmber;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? AppTheme.primaryGradient
              : isAmber
                  ? const LinearGradient(colors: [Color(0xFFF8D49B), Color(0xFFE8B96A)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
          color: isColored ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: isColored ? null : Border.all(color: AppTheme.red.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: isPrimary
                  ? AppTheme.red.withOpacity(0.3)
                  : isAmber
                      ? AppTheme.gold.withOpacity(0.35)
                      : AppTheme.red.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: isColored ? Colors.white.withOpacity(0.2) : AppTheme.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: isColored ? Colors.white : (iconColor ?? AppTheme.red), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            color: isColored ? Colors.white : AppTheme.textPrimary)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: TextStyle(
                            fontSize: 12,
                            color: isColored ? Colors.white.withOpacity(0.8) : AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  if (!isColored) const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notice Box ────────────────────────────────────────────────────
class NoticeBox extends StatelessWidget {
  final String message;
  final Color? borderColor;
  final Color? bgColor;
  final Color? textColor;
  final IconData icon;

  const NoticeBox({
    super.key,
    required this.message,
    this.borderColor,
    this.bgColor,
    this.textColor,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final bc = borderColor ?? AppTheme.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bgColor ?? AppTheme.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: bc, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: bc),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, color: textColor ?? AppTheme.textSecondary, height: 1.55)),
          ),
        ],
      ),
    );
  }
}

// ── Gradient Button ───────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  final bool fullWidth;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.gradient,
    this.color,
    this.textColor = Colors.white,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          gradient: gradient ?? AppTheme.primaryGradient,
          color: gradient == null ? color : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.1)),
      ),
    );
  }
}

// ── Outline Button ────────────────────────────────────────────────
class OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  const OutlineBtn({super.key, required this.label, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.red;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.3), width: 1.5),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
      ),
    );
  }
}

// ── Admin Bar ─────────────────────────────────────────────────────
class AdminBar extends StatelessWidget {
  const AdminBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gold.withOpacity(0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.goldDark.withOpacity(0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_rounded, size: 13, color: Color(0xFF7A5B00)),
          SizedBox(width: 7),
          Text('ADMIN MODE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF7A5B00), letterSpacing: 0.8)),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  const EmptyState({super.key, required this.title, this.subtitle, this.icon = Icons.inbox_rounded});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.textMuted.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.6)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Countdown Badge ───────────────────────────────────────────────
class CountdownBadge extends StatelessWidget {
  final int days;
  const CountdownBadge(this.days, {super.key});

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color bgColor;
    String label;
    if (days < 0) {
      textColor = const Color(0xFFB03030);
      bgColor = const Color(0x18D65E5E);
      label = '${days.abs()}d overdue';
    } else if (days <= 7) {
      textColor = const Color(0xFF8A5F0A);
      bgColor = const Color(0x28F8D49B);
      label = '${days}d left';
    } else {
      textColor = AppTheme.redDark;
      bgColor = AppTheme.red.withOpacity(0.15);
      label = '${days}d left';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
    );
  }
}

// ── Utility: format date ──────────────────────────────────────────
String fmtDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '—';
  try {
    final d = DateTime.parse(dateStr);
    return DateFormat('d MMM yyyy').format(d);
  } catch (_) {
    return dateStr;
  }
}

String relativeTime(String dateStr) {
  try {
    final d = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '$diff days ago';
  } catch (_) {
    return dateStr;
  }
}
