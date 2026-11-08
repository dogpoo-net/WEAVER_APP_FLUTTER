import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/capture/location_capture.dart';

class FakeLocation extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  int requests = 0, positions = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async { requests++; return permission; }
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    positions++;
    expect(locationSettings!.timeLimit, const Duration(seconds: 20));
    return Position(latitude: 37.5, longitude: 127.1, accuracy: 25, timestamp: DateTime.utc(2026, 11, 9),
      altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
  }
}
void main() {
  late GeolocatorPlatform original;
  late FakeLocation location;
  setUp(() { original = GeolocatorPlatform.instance; location = FakeLocation(); GeolocatorPlatform.instance = location; });
  tearDown(() { GeolocatorPlatform.instance = original; });
  test('disabled location service does not request permission or collect coordinates', () async {
    location.enabled = false;
    await expectLater(captureLocation(), throwsStateError);
    expect(location.requests, 0); expect(location.positions, 0);
  });
  testWidgets('denied location preserves draft and can save a normal thought', (tester) async {
    location.permission = LocationPermission.denied;
    await tester.pumpWidget(const MyApp());
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '남겨둘 생각 #기록');
    await tester.tap(find.byKey(const ValueKey('quick-location'))); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '남겨둘 생각 #기록');
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('quick-location'))).value, isFalse);
    expect(location.positions, 0);
    await tester.ensureVisible(find.text('저장')); await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(elements.records['남겨둘 생각']!.location, isNull);
    expect(elements.records['남겨둘 생각']!.tags, {'기록'});
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
  testWidgets('opt-in location attaches coordinates and resets for the next thought', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(location.positions, 0);
    await tester.enterText(find.byKey(const ValueKey('quick-memo')), '위치가 있는 생각');
    await tester.tap(find.byKey(const ValueKey('quick-location'))); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장')); await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(elements.records['위치가 있는 생각']!.location!.latitude, 37.5);
    expect(elements.records['위치가 있는 생각']!.location!.accuracy, 25);
    expect(location.positions, 1);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('quick-location'))).value, isFalse);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
  testWidgets('location alone saves with timestamp title and preserves tags', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byKey(const ValueKey('quick-memo')), '#산책');
    await tester.tap(find.byKey(const ValueKey('quick-location'))); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장')); await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    final record = elements.records.values.singleWhere((r) => r.text.endsWith('/ 위치 메모'));
    expect(record.text, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} / 위치 메모$')));
    expect(record.tags, contains('산책'));
    expect(record.location!.latitude, 37.5);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

}
