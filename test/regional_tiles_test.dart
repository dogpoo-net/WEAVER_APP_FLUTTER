import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:weaver/features/capture/regional_tiles.dart';

TileCoordinates tile(double lat, double lon, int z) {
  final n = 1 << z;
  final radians = lat * math.pi / 180;
  return TileCoordinates(((lon + 180) / 360 * n).floor(),
    ((1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2 * n).floor(), z);
}
void main() {
  test('Korean detail includes Seoul, Jeju and Dokdo; overseas and world use global', () {
    for (final point in [(37.56, 126.97), (33.5, 126.5), (37.24, 131.87)]) {
      expect(usesKoreaTiles(tile(point.$1, point.$2, 14)), isTrue);
    }
    for (final point in [(35.68, 139.69), (48.85, 2.35), (40.71, -74.0)]) {
      expect(usesKoreaTiles(tile(point.$1, point.$2, 14)), isFalse);
    }
    expect(usesKoreaTiles(tile(37.56, 126.97, 2)), isFalse);
  });
  test('URLs select one source and normalize repeated world copies', () {
    final provider = RegionalTileProvider();
    addTearDown(provider.dispose);
    final options = TileLayer(urlTemplate: globalTileTemplate);
    final seoul = tile(37.56, 126.97, 14);
    final url = provider.getTileUrl(seoul, options);
    expect(url, startsWith('https://tiles.osm.kr/hot/14/'));
    expect(provider.getTileUrl(TileCoordinates(seoul.x + (1 << 14), seoul.y, 14), options), url);
    expect(provider.getTileUrl(tile(48.85, 2.35, 14), options), startsWith('https://tile.openstreetmap.org/'));
  });
}
