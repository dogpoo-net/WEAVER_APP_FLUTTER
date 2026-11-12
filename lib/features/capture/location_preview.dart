import 'map_marker_style.dart';
import 'regional_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_attribution.dart';
import 'capture_models.dart';

Future<void> showLocationPreview(BuildContext context, ThoughtLocation location) => showDialog<void>(
  context: context, builder: (dialogContext) => Dialog(child: SizedBox(width: 640, height: 480,
    child: Column(children: [
      Row(children: [const SizedBox(width: 16), const Expanded(child: Text('기록된 위치')),
        IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close))]),
      Expanded(child: FlutterMap(options: MapOptions(initialCenter: LatLng(location.latitude, location.longitude), initialZoom: 16, minZoom: 2, maxZoom: 19), children: [
        TileLayer(urlTemplate: globalTileTemplate, tileProvider: RegionalTileProvider(), userAgentPackageName: 'net.dogpoo.weaver', maxNativeZoom: 19),
        MarkerLayer(markers: [Marker(point: LatLng(location.latitude, location.longitude), alignment: Alignment.topCenter,
          child: Icon(Icons.location_on, size: 40, color: activeMapMarkerColor))]),
        const MapAttribution(),
      ])),
      Padding(padding: const EdgeInsets.all(12), child: Text('${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)} · 정확도 약 ${location.accuracy.round()}m')),
    ]))));
