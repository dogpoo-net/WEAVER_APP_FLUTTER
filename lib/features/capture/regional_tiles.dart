import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';

const globalTileTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const koreaTileTemplate = 'https://tiles.osm.kr/hot/{z}/{x}/{y}.png';

/// Regional selection is approximate, not a national-boundary or masking policy.
/// Low zoom tiles cover multiple countries and use the global source.
bool usesKoreaTiles(TileCoordinates tile) {
  if (tile.z < 7) return false;
  final count = math.pow(2, tile.z).toDouble();
  final longitude = ((tile.x % count + .5) / count) * 360 - 180;
  final n = math.pi * (1 - 2 * (tile.y + .5) / count);
  final latitude = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  return latitude >= 33 && latitude <= 38.7 && longitude >= 124.5 && longitude <= 132;
}

class RegionalTileProvider extends NetworkTileProvider {
  RegionalTileProvider() : super(silenceExceptions: true);

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    final count = 1 << coordinates.z;
    final template = usesKoreaTiles(coordinates) ? koreaTileTemplate : globalTileTemplate;
    return template.replaceAll('{z}', '${coordinates.z}')
      .replaceAll('{x}', '${coordinates.x % count}')
      .replaceAll('{y}', '${coordinates.y}');
  }
}
