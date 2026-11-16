import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';

class _PaintCounter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter old) => false;
}

void main() {
  testWidgets('moving a canvas card reuses unchanged card paint', (
    tester,
  ) async {
    final counter = _PaintCounter(), position = ValueNotifier(0.0);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, x, _) => Stack(
              children: [
                Positioned(
                  left: x,
                  top: 20,
                  child: ThoughtInteraction(
                    size: const Size(200, 100),
                    desktop: false,
                    onMove: (_) {},
                    onResize: (_, shift) {},
                    onDrop: (_) {},
                    onEnd: () {},
                    onTap: () {},
                    child: CustomPaint(painter: counter),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final initial = counter.paints;
    for (var i = 1; i <= 10; i++) {
      position.value = i * 5;
      await tester.pump();
    }
    expect(initial, greaterThan(0));
    expect(counter.paints, initial);
    await tester.pumpWidget(const SizedBox());
  });
}
