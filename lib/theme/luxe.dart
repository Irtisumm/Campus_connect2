import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// ── Luxe design system ────────────────────────────────────────────
///
/// A premium visual layer used by the redesigned Lost & Found hub and
/// the app shell chrome. Deliberately additive: it does not modify
/// [AppTheme], so every screen that has not been redesigned yet keeps
/// its existing look.
class Luxe {
  Luxe._();

  // ── Palette ─────────────────────────────────────────────────────
  static const Color primary   = Color(0xFFE53958);
  static const Color secondary = Color(0xFFFF6B6B);
  static const Color accent    = Color(0xFFFFB347);
  static const Color bg        = Color(0xFFFFF8F5);
  static const Color surface   = Color(0xFFFFFFFF);
  static const Color success   = Color(0xFF34C759);
  static const Color warning   = Color(0xFFFFB020);
  static const Color info      = Color(0xFF4A90E2);

  /// Deep end of the cherry ramp — used for header gradients only.
  static const Color primaryDeep = Color(0xFFB81E42);

  // ── Ink ─────────────────────────────────────────────────────────
  static const Color ink      = Color(0xFF1B1620);
  static const Color inkSoft  = Color(0xFF5C5563);
  static const Color inkMuted = Color(0xFF938C99);
  static const Color hairline = Color(0xFFF0E7E4);

  // ── 8-point spacing scale ───────────────────────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 40;

  // ── Radii ───────────────────────────────────────────────────────
  static const double rChip   = 999;
  static const double rSmall  = 14;
  static const double rMedium = 20;
  static const double rCard   = 28;

  // ── Gradients ───────────────────────────────────────────────────
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF04E6B), primary, primaryDeep],
    stops: [0.0, 0.48, 1.0],
  );

  static const LinearGradient lostGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6B), primary, Color(0xFFC9284A)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient foundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC776), accent, Color(0xFFF08A2E)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Diagonal sheen laid over gradient cards for a glass highlight.
  static const LinearGradient glassSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x38FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
    stops: [0.0, 0.55, 1.0],
  );

  // ── Layered soft shadows ────────────────────────────────────────
  /// Two stacked low-opacity shadows: a tight contact shadow plus a
  /// wide ambient one. Reads as float rather than as a hard drop.
  static List<BoxShadow> lift({Color tint = primary, double strength = 1}) => [
        BoxShadow(
          color: tint.withValues(alpha: 0.05 * strength),
          blurRadius: 6 * strength,
          offset: Offset(0, 2 * strength),
        ),
        BoxShadow(
          color: tint.withValues(alpha: 0.07 * strength),
          blurRadius: 28 * strength,
          offset: Offset(0, 12 * strength),
          spreadRadius: -4,
        ),
      ];

  static List<BoxShadow> liftStrong({Color tint = primary}) => [
        BoxShadow(
          color: tint.withValues(alpha: 0.16),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: tint.withValues(alpha: 0.22),
          blurRadius: 34,
          offset: const Offset(0, 16),
          spreadRadius: -6,
        ),
      ];

  // ── Typography ──────────────────────────────────────────────────
  static const String _font = 'Inter';

  static const TextStyle display = TextStyle(
      fontFamily: _font, fontSize: 26, fontWeight: FontWeight.w800,
      letterSpacing: -0.7, height: 1.1);
  static const TextStyle cardTitle = TextStyle(
      fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w800,
      letterSpacing: -0.5, height: 1.15);
  static const TextStyle sectionLabel = TextStyle(
      fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w700,
      letterSpacing: 1.4);
  static const TextStyle title = TextStyle(
      fontFamily: _font, fontSize: 17, fontWeight: FontWeight.w700,
      letterSpacing: -0.3, height: 1.2);
  static const TextStyle body = TextStyle(
      fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w500,
      height: 1.45);
  static const TextStyle caption = TextStyle(
      fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w500,
      height: 1.3);
}

/// ── Frosted glass pill / button ───────────────────────────────────
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final double opacity;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.radius = 16,
    this.onTap,
    this.opacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    final surface = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return surface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: surface,
    );
  }
}

/// ── Section header: accent tick + uppercase label + rule ──────────
class LuxeSectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const LuxeSectionHeader(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Luxe.s4, top: Luxe.s2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Luxe.secondary, Luxe.primary],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: Luxe.s2 + 2),
          Text(label.toUpperCase(),
              style: Luxe.sectionLabel.copyWith(color: Luxe.ink)),
          const SizedBox(width: Luxe.s3),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Luxe.primary.withValues(alpha: 0.22),
                  Luxe.primary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Luxe.s3), trailing!],
        ],
      ),
    );
  }
}

/// ── Status chip (coloured dot + label) ────────────────────────────
class LuxeStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const LuxeStatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Luxe.rChip),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: Luxe.caption.copyWith(
                  color: Color.alphaBlend(
                      color.withValues(alpha: 0.85), Luxe.ink),
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// ── Security chip (✓ Secure · Encrypted · Trusted) ────────────────
class LuxeSecurityChip extends StatelessWidget {
  final String label;
  const LuxeSecurityChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Luxe.success.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(Luxe.rChip),
        border: Border.all(color: Luxe.success.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 12, color: Color(0xFF1F9D45)),
          const SizedBox(width: 4),
          Text(label,
              style: Luxe.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F7A38))),
        ],
      ),
    );
  }
}

/// ── Circular arrow affordance used on every actionable card ───────
class LuxeArrowButton extends StatelessWidget {
  final bool onDark;
  final double size;
  const LuxeArrowButton({super.key, this.onDark = false, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? Colors.white : Luxe.primary.withValues(alpha: 0.07),
        shape: BoxShape.circle,
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.55)
              : Luxe.primary.withValues(alpha: 0.12),
        ),
        boxShadow: onDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: size * 0.44,
        color: onDark ? Luxe.primary : Luxe.primary,
      ),
    );
  }
}

/// ── Drawn shield mark ─────────────────────────────────────────────
///
/// Stands in for the 3D shield illustration: gradient body, inner
/// highlight and a soft ambient glow, painted rather than imported
/// (the project ships no image assets).
class ShieldMark extends StatelessWidget {
  final double size;
  final bool showCheck;
  const ShieldMark({super.key, this.size = 56, this.showCheck = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _ShieldPainter()),
          Icon(Icons.lock_rounded,
              size: size * 0.30, color: Colors.white.withValues(alpha: 0.96)),
          if (showCheck)
            Positioned(
              right: 0,
              bottom: size * 0.12,
              child: Container(
                width: size * 0.30,
                height: size * 0.30,
                decoration: BoxDecoration(
                  color: Luxe.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Luxe.success.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.check_rounded,
                    size: size * 0.17, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.90, h * 0.20)
      ..lineTo(w * 0.90, h * 0.52)
      ..cubicTo(w * 0.90, h * 0.78, w * 0.72, h * 0.92, w * 0.5, h * 0.98)
      ..cubicTo(w * 0.28, h * 0.92, w * 0.10, h * 0.78, w * 0.10, h * 0.52)
      ..lineTo(w * 0.10, h * 0.20)
      ..close();

    // Ambient glow
    canvas.drawPath(
      path,
      Paint()
        ..color = Luxe.primary.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Body
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7E8E), Luxe.primary, Color(0xFFB81E42)],
        ).createShader(Offset.zero & size),
    );

    // Specular highlight on the upper-left facet
    canvas.save();
    canvas.clipPath(path);
    final highlight = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.90, h * 0.20)
      ..lineTo(w * 0.5, h * 0.46)
      ..lineTo(w * 0.10, h * 0.20)
      ..close();
    canvas.drawPath(
      highlight,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.restore();

    // Rim light
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ── Header backdrop: geometric pattern + campus skyline ───────────
class HeaderBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Abstract geometry — concentric arcs and floating circles.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.10);

    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(w * 0.86, h * 0.10), 46.0 + i * 26, stroke);
    }
    canvas.drawCircle(
      Offset(w * 0.14, h * 0.86),
      38,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    canvas.drawCircle(
      Offset(w * 0.72, h * 0.72),
      12,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    // Soft top-left lighting.
    canvas.drawCircle(
      Offset(w * 0.08, -h * 0.15),
      h * 0.85,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ]).createShader(
          Rect.fromCircle(
              center: Offset(w * 0.08, -h * 0.15), radius: h * 0.85),
        ),
    );

    _paintSkyline(canvas, size);
  }

  /// Very subtle university skyline along the bottom edge.
  void _paintSkyline(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final baseline = h;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.055);
    final path = Path()..moveTo(0, baseline);

    // Repeating block silhouette with a domed central tower.
    const blocks = <List<double>>[
      [0.00, 0.30], [0.09, 0.46], [0.17, 0.34], [0.24, 0.52],
      [0.33, 0.38], [0.60, 0.40], [0.68, 0.56], [0.77, 0.36],
      [0.86, 0.48], [0.94, 0.32],
    ];

    for (final b in blocks) {
      final x = w * b[0];
      final top = baseline - h * b[1];
      path
        ..lineTo(x, baseline)
        ..lineTo(x, top)
        ..lineTo(x + w * 0.075, top)
        ..lineTo(x + w * 0.075, baseline);
    }
    path
      ..lineTo(w, baseline)
      ..close();
    canvas.drawPath(path, paint);

    // Central dome + spire (the campus landmark).
    final cx = w * 0.47;
    final domeBase = baseline - h * 0.44;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.055, domeBase)
        ..arcToPoint(Offset(cx + w * 0.055, domeBase),
            radius: Radius.circular(w * 0.055))
        ..close(),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx - w * 0.055, domeBase, cx + w * 0.055, baseline),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx - 1.4, domeBase - h * 0.10, cx + 1.4, domeBase),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ── Decorative object cluster behind the hero cards ───────────────
///
/// Icon-composed illustration at ~6% opacity, as specified. Uses
/// rounded Material icons because the project ships no artwork.
class CardIllustration extends StatelessWidget {
  final List<IconData> icons;
  const CardIllustration({super.key, required this.icons});

  @override
  Widget build(BuildContext context) {
    // NOTE: must be placed inside a Positioned.fill by the parent Stack.
    // It deliberately does not size itself — doing so (e.g. SizedBox.expand)
    // forces infinite height when the card sits in a scroll view.
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Luxe.rCard),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
              Positioned(
                right: -18,
                top: -22,
                child: Transform.rotate(
                  angle: -0.18,
                  child: Icon(icons[0],
                      size: 132, color: Colors.white.withValues(alpha: 0.09)),
                ),
              ),
              Positioned(
                right: 78,
                bottom: -30,
                child: Transform.rotate(
                  angle: 0.22,
                  child: Icon(icons[1],
                      size: 96, color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              Positioned(
                right: 132,
                top: -8,
                child: Transform.rotate(
                  angle: 0.10,
                  child: Icon(icons[2],
                      size: 64, color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ── Pressable wrapper: subtle scale on tap ────────────────────────
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const Pressable({super.key, required this.child, required this.onTap});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Small helper so painters can be reused without magic numbers.
double degToRad(double deg) => deg * math.pi / 180.0;
