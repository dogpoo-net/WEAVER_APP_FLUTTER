import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  test('connections are reciprocal, unique and survive renaming', () {
    final store = ElementStore();
    final a = store.add('첫 생각');
    final b = store.add('다른 생각');
    final c = store.add('세 번째 생각');
    store.connect(a.id, [b.id, b.id, c.id, a.id, 'missing']);
    expect(a.connections, {b.id, c.id});
    expect(b.connections, {a.id});
    expect(c.connections, {a.id});
    store.update(b.text, '바뀐 생각');
    expect(a.connections, contains(b.id));
    store.remove('바뀐 생각');
    expect(a.connections, {c.id});
    expect(c.connections, {a.id});
  });
}
