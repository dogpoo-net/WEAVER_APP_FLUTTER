import 'map_marker_style.dart';
import 'regional_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_attribution.dart';
import 'capture_models.dart';

Future<void> showLocationPreview(BuildContext context, ThoughtLocation location,{ValueChanged<ThoughtLocation>? onChanged}) {
 var selected=location;
 return showDialog<void>(
  context: context, builder: (dialogContext) => StatefulBuilder(builder:(context,setState)=>Dialog(child: SizedBox(width: 640, height: 480,
    child: Column(children: [
      Row(children: [const SizedBox(width: 16), const Expanded(child: Text('기록된 위치')),
        IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close))]),
      Expanded(child: FlutterMap(options: MapOptions(initialCenter: LatLng(location.latitude, location.longitude), initialZoom: 16, minZoom: 2, maxZoom: 19), children: [
        const RegionalTileLayer(),
        MarkerLayer(markers: [Marker(point: LatLng(location.latitude, location.longitude), alignment: Alignment.topCenter,
          child: Icon(Icons.location_on, size: 40, color: locationMarkerColor(selected), shadows: const [Shadow(color: Colors.white, blurRadius: 3)]))]),
        const MapAttribution(),
      ])),
      Padding(padding: const EdgeInsets.all(12), child: Row(children:[Expanded(child:Text('${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)} · ${location.isCurrentLocation?(location.accuracy>0?'현재 위치 · 정확도 약 ${location.accuracy.round()}m':'현재 위치'):'지도에서 선택한 위치'}')),
        if(onChanged!=null)IconButton(tooltip:'마커 색상',icon:Container(width:28,height:28,decoration:BoxDecoration(color:locationMarkerColor(selected),shape:BoxShape.circle,border:Border.all(color:Theme.of(context).colorScheme.outlineVariant))),onPressed:()async{
          final color=await showMarkerPalette(context,locationMarkerColor(selected));
          if(color==null||!context.mounted)return;
          setState(()=>selected=selected.withMarkerColor(color));onChanged(selected);
        }),
      ])),
    ])))));
}
