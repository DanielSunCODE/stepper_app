import 'dart:math' as math;

import 'package:flutter/material.dart';

const kCw = Color(0xFF1F7A8C);
const kCcw = Color(0xFFB5532F);
const kInk = Color(0xFF17282E);
const kMuted = Color(0xFF5D6F73);
const kScreen = Color(0xFF10303A);
const kLit = Color(0xFFFFB347);
const kGrid = Color(0xFF245565);
const kScreenText = Color(0xFF9FC3CC);

/// Carátula con aguja, arcos de sentido de giro y marcador de destino.
/// Tocar o arrastrar sobre la carátula elige un ángulo de destino.
class Dial extends StatelessWidget {
  const Dial({
    super.key,
    required this.angle,
    required this.direction,
    required this.target,
    required this.onTarget,
  });

  final double angle;
  final int direction;
  final double? target;
  final ValueChanged<double> onTarget;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = math.min(box.maxWidth, 340.0);
      void pick(Offset p) {
        final c = Offset(size / 2, size / 2);
        final d = p - c;
        if (d.distance < size * 0.08) return;
        var deg = math.atan2(d.dx, -d.dy) * 180 / math.pi; // 0° arriba, horario
        if (deg < 0) deg += 360;
        onTarget((deg * 2).round() / 2);
      }

      return Center(
        child: GestureDetector(
          onTapDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _DialPainter(
                angle: angle,
                direction: direction,
                target: target,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.angle, required this.direction, required this.target, required this.dark});
  final double angle;
  final int direction;
  final double? target;
  final bool dark;

  Offset _polar(Offset c, double deg, double r) {
    final rad = deg * math.pi / 180;
    return Offset(c.dx + r * math.sin(rad), c.dy - r * math.cos(rad));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2;
    final face = outer * 0.78;
    final ink = dark ? const Color(0xFFE6EEF0) : kInk;
    final idle = dark ? const Color(0xFF3A4A4E) : const Color(0xFFAEBCB9);

    // arcos de sentido (compás: 0° arriba, el arco "horario" va a la derecha)
    final arcRect = Rect.fromCircle(center: c, radius: outer - 8);
    Paint arc(bool on, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = on ? col : idle;
    final cw = direction == 1, ccw = direction == -1;
    // Canvas.drawArc: 0 rad = derecha (3 en punto), positivo = horario.
    canvas.drawArc(arcRect, -60 * math.pi / 180, 120 * math.pi / 180, false, arc(cw, kCw));
    canvas.drawArc(arcRect, 120 * math.pi / 180, 120 * math.pi / 180, false, arc(ccw, kCcw));
    _arrowHead(canvas, c, outer - 8, 60, true, cw ? kCw : idle);
    _arrowHead(canvas, c, outer - 8, 240, false, ccw ? kCcw : idle);

    // carátula
    canvas.drawCircle(c, face, Paint()..color = dark ? const Color(0xFF1B2A2E) : Colors.white);
    canvas.drawCircle(
        c,
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ink);
    final tick = Paint()
      ..color = ink
      ..strokeWidth = 2;
    for (var a = 0; a < 360; a += 10) {
      final len = a % 30 == 0 ? 14.0 : 8.0;
      canvas.drawLine(_polar(c, a.toDouble(), face - len), _polar(c, a.toDouble(), face - 3), tick);
    }
    for (final a in [0, 90, 180, 270]) {
      _text(canvas, '$a°', _polar(c, a.toDouble(), face - 28), 11, kMuted);
    }

    // destino
    if (target != null) {
      final t = Paint()
        ..color = kLit
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(_polar(c, target!, face * 0.35), _polar(c, target!, face - 2), t);
      canvas.drawCircle(_polar(c, target!, face - 2), 6, Paint()..color = kLit);
    }

    // aguja
    final needleColor = cw ? kCw : (ccw ? kCcw : kMuted);
    canvas.drawLine(
        c,
        _polar(c, angle, face - 14),
        Paint()
          ..color = needleColor
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 9, Paint()..color = ink);
  }

  void _arrowHead(Canvas canvas, Offset c, double r, double deg, bool clockwise, Color color) {
    final p = _polar(c, deg, r);
    final rad = deg * math.pi / 180;
    var t = Offset(math.cos(rad), math.sin(rad)); // tangente horaria
    if (!clockwise) t = -t;
    final n = Offset(-t.dy, t.dx);
    final path = Path()
      ..moveTo(p.dx + t.dx * 13, p.dy + t.dy * 13)
      ..lineTo(p.dx - t.dx * 4 + n.dx * 10, p.dy - t.dy * 4 + n.dy * 10)
      ..lineTo(p.dx - t.dx * 4 - n.dx * 10, p.dy - t.dy * 4 - n.dy * 10)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _text(Canvas canvas, String s, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.angle != angle || o.direction != direction || o.target != target || o.dark != dark;
}

/// Gráfica en vivo del voltaje medido por el ADC.
class Scope extends StatelessWidget {
  const Scope({super.key, required this.samples, required this.maxMv, required this.capacity});
  final List<double> samples;
  final double maxMv;
  final int capacity;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ScopePainter(samples, maxMv, capacity),
        size: Size.infinite,
      );
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(this.samples, this.maxMv, this.capacity);
  final List<double> samples;
  final double maxMv;
  final int capacity;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 52.0, top = 10.0, bottom = 10.0, right = 8.0;
    final h = size.height - top - bottom;
    final w = size.width - left - right;
    final grid = Paint()
      ..color = kGrid
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = top + h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final tp = TextPainter(
        text: TextSpan(
            text: '${(maxMv * (1 - i / 4)).round()} mV',
            style: const TextStyle(fontSize: 10, color: Color(0xFF7FA8B3))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }
    if (samples.length < 2) return;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = left + w * i / (capacity - 1);
      final y = top + h * (1 - (samples[i] / maxMv).clamp(0.0, 1.0));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = kLit);
  }

  @override
  bool shouldRepaint(_ScopePainter o) => true;
}

/// Display estilo LCD con título y valor.
class Readout extends StatelessWidget {
  const Readout({super.key, required this.title, required this.value, this.unit});
  final String title;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(color: kScreen, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: kScreenText, fontSize: 11)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: value,
                    style: const TextStyle(
                        color: kLit,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
                if (unit != null) TextSpan(text: ' $unit', style: const TextStyle(color: kScreenText, fontSize: 12)),
              ])),
            ),
          ],
        ),
      );
}

/// Indicador de sentido de giro (LED).
class DirLed extends StatelessWidget {
  const DirLed({super.key, required this.label, required this.on, required this.color});
  final String label;
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: on ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: on ? color : kMuted, width: 2),
            boxShadow: on ? [BoxShadow(color: color.withValues(alpha: .6), blurRadius: 8)] : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: on ? color : kMuted)),
      ]);
}
