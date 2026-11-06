import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/puzzle_border.dart';

void main() {
  test('different-size blocks dock on all four sides', () {
    const target = Rect.fromLTWH(500, 400, 230, 110);
    const size = Size(190, 90);
    for (final position in [const Offset(500, 494), const Offset(500, 326), const Offset(714, 410), const Offset(326, 410)]) {
      final dock = puzzleDock('moving', {'target': target, 'moving': (position + const Offset(4, 4)) & size});
      expect(dock?.target, 'target'); expect(dock?.position, position);
    }
  });
  test('multiple neighbors dock independently and an occupied port stays unchanged', () {
    final nodes = {'center': const Rect.fromLTWH(500, 400, 230, 110),
      'bottom': const Rect.fromLTWH(500, 494, 230, 110),
      'right': const Rect.fromLTWH(720, 400, 230, 110)};
    expect(puzzleDock('right', nodes)?.position, const Offset(714, 400));
    nodes['right'] = const Rect.fromLTWH(714, 400, 230, 110);
    nodes['left'] = const Rect.fromLTWH(292, 400, 230, 110);
    expect(puzzleDock('left', nodes)?.position, const Offset(286, 400));
    nodes['extra'] = const Rect.fromLTWH(716, 402, 230, 110);
    expect(puzzleDock('extra', nodes), isNull);
    expect(nodes['bottom'], const Rect.fromLTWH(500, 494, 230, 110));
    expect(nodes['center'], const Rect.fromLTWH(500, 400, 230, 110));
  });
}
