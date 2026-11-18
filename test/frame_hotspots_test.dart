import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/thought_label.dart';

void main() {
  test('large workspace link lookup benchmark', () {
    elements.clear();
    addTearDown(elements.clear);
    for (var i=0;i<5000;i++) {
      elements.records['memo $i']=ElementRecord.restored('id$i','memo $i',DateTime(2026));
    }
    final samples=<int>[];
    for(var run=0;run<6;run++) {
      final watch=Stopwatch()..start();
      for(var i=0;i<10000;i++) {
        if(labelTarget('label:id${i%5000}')==null) fail('Missing record');
      }
      watch.stop();if(run>0)samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    // Comparative CPU benchmark, not browser frame timing.
    debugPrint('LINK_LOOKUP_MEDIAN_US=${samples[2]}');
  });
  testWidgets('repeated canvas label measurement benchmark', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(c){context=c;return const SizedBox();})));
    final samples=<int>[];
    for(var run=0;run<6;run++) {
      final watch=Stopwatch()..start();
      for(var i=0;i<2000;i++) {
        expect(ThoughtLabel.width(context,'생각 라벨 ${i%100}'),greaterThan(20));
      }
      watch.stop();if(run>0)samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();debugPrint('LABEL_MEASURE_MEDIAN_US=${samples[2]}');
  });
}
