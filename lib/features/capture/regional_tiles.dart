import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

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
  const mainland = <(double, double)>[
    (124.5, 38.7),
    (128.5, 38.7),
    (129.8, 36.4),
    (129.8, 35.5),
    (129.3, 34.95),
    (128.7, 34.55),
    (128.0, 34.0),
    (125.0, 33.8),
    (124.5, 34.8),
  ];
  var inside = false;
  for (var i = 0, j = mainland.length - 1; i < mainland.length; j = i++) {
    final a = mainland[i], b = mainland[j];
    if ((a.$2 > latitude) != (b.$2 > latitude) &&
        longitude < (b.$1 - a.$1) * (latitude - a.$2) / (b.$2 - a.$2) + a.$1) {
      inside = !inside;
    }
  }
  return inside ||
      latitude >= 32.9 &&
          latitude <= 33.85 &&
          longitude >= 125.9 &&
          longitude <= 127.1 ||
      latitude >= 37.35 &&
          latitude <= 37.65 &&
          longitude >= 130.7 &&
          longitude <= 131.05 ||
      latitude >= 37.15 &&
          latitude <= 37.35 &&
          longitude >= 131.75 &&
          longitude <= 132;
}

class RegionalTileProvider extends NetworkTileProvider {
  // App-lifetime client: closing one map must not cancel a URL-cached image
  // stream that another open map is still using.
  static final http.Client _sharedClient = RetryClient(http.Client());
  RegionalTileProvider({http.Client? httpClient, super.cachingProvider})
    : super(
        httpClient: httpClient ?? _sharedClient,
        silenceExceptions: false,
        attemptDecodeOfHttpErrorResponses: false,
        // flutter_map treats aborted requests as successful transparent images.
        // URL-keyed ImageCache streams are shared between map instances/world
        // copies: pruning one consumer must not blank the surviving consumer.
        abortObsoleteRequests: false,
      );

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    final count = 1 << coordinates.z;
    final template = usesKoreaTiles(coordinates)
        ? koreaTileTemplate
        : globalTileTemplate;
    return template
        .replaceAll('{z}', '${coordinates.z}')
        .replaceAll('{x}', '${coordinates.x % count}')
        .replaceAll('{y}', '${coordinates.y}');
  }
}

/// Keep the provider alive across composer rebuilds. Failed tiles must remain
/// errors, not successful transparent images, so they can be evicted/retried.
class RegionalTileLayer extends StatefulWidget {
  const RegionalTileLayer({super.key, this.onError, this.tileProvider});
  final VoidCallback? onError;
  final TileProvider? tileProvider;
  @override
  State<RegionalTileLayer> createState() => _RegionalTileLayerState();
}

class _RegionalTileLayerState extends State<RegionalTileLayer> {
  late final provider = widget.tileProvider ?? RegionalTileProvider();
  final failedTiles = <TileImage>{};
  Timer? retry;
  int attempts = 0;
  bool active = true;
  DateTime? lastFailure;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    active = TickerMode.valuesOf(context).enabled;
    if (!active) {
      retry?.cancel();
      retry = null;
    } else {
      scheduleRetry();
    }
  }

  void failed(TileImage tile) {
    if (tile.cancelLoading.isCompleted) return;
    final now = DateTime.now();
    if (lastFailure == null ||
        now.difference(lastFailure!) > const Duration(minutes: 1)) {
      attempts = 0;
    }
    lastFailure = now;
    failedTiles.removeWhere((t) => t.cancelLoading.isCompleted);
    failedTiles.add(tile);
    scheduleRetry();
  }

  void scheduleRetry() {
    if (!active || retry != null || failedTiles.isEmpty) return;
    final seconds = math.min(30, 2 * (1 << math.min(attempts, 4)));
    attempts++;
    retry = Timer(Duration(seconds: seconds), () {
      retry = null;
      if (!mounted || !active) return;
      if (attempts >= 3) widget.onError?.call();
      unawaited(retryFailed());
    });
  }

  Future<void> retryFailed() async {
    final tiles = failedTiles.toList();
    failedTiles.clear();
    for (final tile in tiles) {
      if (tile.cancelLoading.isCompleted || !tile.loadError) continue;
      // Reload only failed images. Resetting the entire layer cancels unrelated
      // in-flight tiles and can create another set of transparent survivors.
      try {
        await tile.imageProvider.evict();
      } catch (_) {
        /* Retry the network load. */
      }
      if (!mounted) return;
      if (tile.cancelLoading.isCompleted) continue;
      if (!active) {
        failedTiles.add(tile);
        continue;
      }
      tile.load();
    }
    scheduleRetry();
  }

  @override
  void dispose() {
    retry?.cancel();
    failedTiles.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: globalTileTemplate,
    tileProvider: provider,
    userAgentPackageName: 'net.dogpoo.weaver',
    maxNativeZoom: 19,
    evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
    errorTileCallback: (tile, error, stack) => failed(tile),
  );
}
