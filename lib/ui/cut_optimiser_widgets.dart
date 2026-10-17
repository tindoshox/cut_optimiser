import 'dart:math' as math;

import 'package:flutter/material.dart';

const ink = Color(0xFF101B2A);
const panel = Color(0xFF182638);
const orange = Color(0xFFFF812D);
const canvas = Color(0xFFF2F5F8);
const muted = Color(0xFF738195);

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.subtitle, {super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class SawBladeIcon extends StatelessWidget {
  const SawBladeIcon({
    super.key,
    this.size = 24,
    this.bladeColor = orange,
    this.hubColor = ink,
  });

  final double size;
  final Color bladeColor;
  final Color hubColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _SawBladePainter(bladeColor: bladeColor, hubColor: hubColor),
      );
}

class _SawBladePainter extends CustomPainter {
  _SawBladePainter({required this.bladeColor, required this.hubColor});

  final Color bladeColor;
  final Color hubColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bladePaint = Paint()..color = bladeColor;
    final hubPaint = Paint()..color = hubColor;
    final bounds = Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.18,
      size.width * 0.64,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(size.width * 0.16)),
      bladePaint,
    );
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.17, hubPaint);
    final bladeLinePaint = Paint()
      ..color = hubColor
      ..strokeWidth = 2.2;
    for (var i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * math.pi;
      final start = center +
          Offset(
            math.cos(angle) * size.width * 0.28,
            math.sin(angle) * size.width * 0.28,
          );
      final end = center +
          Offset(
            math.cos(angle) * size.width * 0.42,
            math.sin(angle) * size.width * 0.42,
          );
      canvas.drawLine(start, end, bladeLinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MetricCard extends StatelessWidget {
  const MetricCard(this.label, this.value, this.icon, this.color, {super.key});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {this.color = orange, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
}

class PrototypeNotice extends StatelessWidget {
  const PrototypeNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF9D8A8)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Prototype planner: this optimiser is intentionally heuristic and best suited to workshop planning rather than certified engineering calculations.',
                style: TextStyle(color: Color(0xFF7A5631), height: 1.45),
              ),
            ),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.subtitle, {this.action, super.key});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted),
              ),
              if (action != null) ...[
                const SizedBox(height: 14),
                action!,
              ],
            ],
          ),
        ),
      );
}
