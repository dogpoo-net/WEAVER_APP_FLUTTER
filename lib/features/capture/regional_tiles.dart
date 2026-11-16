import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';

const globalTileTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const koreaTileTemplate = 'https://tiles.osm.kr/hot/{z}/{x}/{y}.png';

/// Regional selection is approximate, not a national-boundary or masking policy.
/// Low zoom tiles cover multiple countries and use the global source.
bool usesKoreaTiles(TileCoordinates tile) {
  if (tile.z < 9) return false;
  final count = math.pow(2, tile.z).toDouble();
  final longitude = ((tile.x % count + .5) / count) * 360 - 180;
  final n = math.pi * (1 - 2 * (tile.y + .5) / count);
  final latitude = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  // Operational tile coverage, not a legal border. The sloped southern
  // coast excludes Tsushima and Kyushu; offshore Korean islands are separate.
  const mainland = <(double,double)>[
    (124.5,38.7),(128.5,38.7),(129.8,36.4),(129.8,35.5),
    (129.3,34.95),(128.7,34.55),(128.0,34.0),(125.0,33.8),(124.5,34.8),
  ];
  var inside=false;
  for(var i=0,j=mainland.length-1;i<mainland.length;j=i++){
    final a=mainland[i],b=mainland[j];
    if((a.$2>latitude)!=(b.$2>latitude) && longitude<(b.$1-a.$1)*(latitude-a.$2)/(b.$2-a.$2)+a.$1)inside=!inside;
  }
  return inside ||
    latitude>=32.9 && latitude<=33.85 && longitude>=125.9 && longitude<=127.1 ||
    latitude>=37.35 && latitude<=37.65 && longitude>=130.7 && longitude<=131.05 ||
    latitude>=37.15 && latitude<=37.35 && longitude>=131.75 && longitude<=132;
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
