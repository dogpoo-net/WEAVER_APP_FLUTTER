import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.bottomRight,
    child: Material(color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [InkWell(onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication),
        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10)))),
        InkWell(onTap: () => launchUrl(Uri.parse('https://tiles.osm.kr/'), mode: LaunchMode.externalApplication),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('한국 상세 타일: tiles.osm.kr', style: TextStyle(fontSize: 10)))),
      ])));
}
