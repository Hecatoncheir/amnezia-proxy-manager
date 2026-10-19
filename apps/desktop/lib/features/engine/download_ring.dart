import 'dart:math' as math;

import 'package:flutter/material.dart';

class DownloadRing extends StatelessWidget {
  const DownloadRing({
    super.key,
    required this.progress,
    this.label = 'Загрузка движка',
  });
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    final percent = '${(value * 100).floor()}%';
    return Semantics(
      label: label,
      value: percent,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 88,
          child: CustomPaint(
            painter: _RingPainter(
              value,
              colors.primary,
              colors.primary.withValues(alpha: 0.25),
            ),
            child: Center(
              child: Text(
                percent,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.active, this.track);
  final double progress;
  final Color active, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    const start = -math.pi / 2;
    const step = math.pi * 2 / 48;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    paint.color = track;
    for (var i = 0; i < 48; i++) {
      canvas.drawArc(rect, start + step * i, step * 0.42, false, paint);
    }
    if (progress > 0) {
      paint
        ..color = active
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, math.pi * 2 * progress, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      progress != old.progress || active != old.active || track != old.track;
}
